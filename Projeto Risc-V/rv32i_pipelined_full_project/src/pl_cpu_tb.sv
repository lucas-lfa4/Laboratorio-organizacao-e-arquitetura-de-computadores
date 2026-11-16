// =============================================================================
// pl_cpu_tb.sv
// Testbench -- RV32I pipelined
//
// Instancia pl_cpu diretamente (sem PLL); gera clock e reset internamente.
//
// Programa de teste (instruction.mif / program.hex):
//   000: lw  x1,  0(x0)    x1 = 10
//   001: lw  x2,  4(x0)    x2 = 20
//   002: add x3, x1, x2    x3 = 30   (forwarding MEM/WB->EX)
//   003: and x4, x3, x1    x4 = 10   (0x1E & 0x0A, forwarding EX/MEM->EX)
//   004: lw  x5,  0(x0)    x5 = 10   (provoca load-use stall em 005)
//   005: add x6, x5, x2    x6 = 30   (1 ciclo de stall)
//   006: sw  x3,  8(x0)    dmem[2] = 30
//   007: beq x1, x2, +8    NAO tomado (x1=10 != x2=20)
//   008: add x7, x1, x2    x7 = 30
//   009: beq x1, x5, +8    TOMADO (x1=x5=10) -> salta 00A, executa 00B
//   00A: add x8, x0, x0    DESCARTADO (flush)
//   00B: add x8, x1, x4    x8 = 20
//   00C: beq x0, x0,  0    halt (loop infinito)
//
// Estado esperado apos halt:
//   x1=10 x2=20 x3=30 x4=10 x5=10 x6=30 x7=30 x8=20
//   dmem[2]=30
//
// O testbench:
//   1. Monitora cada escrita no banco de registradores (estagio WB)
//   2. Monitora cada escrita na memoria de dados (estagio MEM)
//   3. Detecta halt (periodo-3 de PC por HALT_CONFIRM ciclos consecutivos)
//   4. Faz dump do estado final dos registradores e da dmem
//   5. Grava output.txt e compara com golden.txt
// =============================================================================

`timescale 1ns / 1ps

module pl_cpu_tb;

    // =========================================================================
    // Parametros
    // =========================================================================
    localparam CLK_PERIOD  = 100;   // 10 MHz  (100 ns)
    localparam CLK_HALF    = CLK_PERIOD / 2;
    localparam RESET_CYCLES = 4;
    localparam MAX_CYCLES  = 2000;  // timeout de seguranca


    // =========================================================================
    // Sinais do DUT
    // =========================================================================
    logic        clk, rst_n;
    logic [31:0] PC;
    logic [17:0] SW    = 18'h15555;   // chaves com padrao alternado
    logic [3:0]  KEY   = 4'hF;        // nenhum botao pressionado
    logic [17:0] LEDR;
    logic [8:0]  LEDG;
    logic        UART_TXD;
    logic        UART_RXD = 1'b1;     // linha idle

    logic        wb_reg_write;
    logic [4:0]  wb_reg_dst;
    logic [31:0] wb_reg_data;
    logic        mem_wr_en;
    logic [7:0]  mem_wr_addr;
    logic [31:0] mem_wr_data;

    // =========================================================================
    // Instancia do DUT
    // =========================================================================
    pl_cpu dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .PC           (PC),
        .SW           (SW),
        .KEY_IO       (KEY),
        .LEDR         (LEDR),
        .LEDG         (LEDG),
        .UART_TXD     (UART_TXD),
        .UART_RXD     (UART_RXD),
        .wb_reg_write (wb_reg_write),
        .wb_reg_dst   (wb_reg_dst),
        .wb_reg_data  (wb_reg_data),
        .mem_wr_en    (mem_wr_en),
        .mem_wr_addr  (mem_wr_addr),
        .mem_wr_data  (mem_wr_data)
    );

    // =========================================================================
    // Clock e reset
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    // =========================================================================
    // Arquivo de saida
    // =========================================================================
    integer out_fd;
    integer golden_fd;

    // =========================================================================
    // Sombra da memoria de dados (copia local para dump final)
    // =========================================================================
    logic [31:0] dmem_shadow [0:255];

    // =========================================================================
    // Monitor de escrita no banco de registradores (estagio WB)
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && wb_reg_write && wb_reg_dst != 5'b0) begin
            $display("[WB] REG x%0d = 0x%08X", wb_reg_dst, wb_reg_data);
            $fdisplay(out_fd, "REG %2d = 0x%08X", wb_reg_dst, wb_reg_data);
        end
    end

    // =========================================================================
    // Monitor de escrita na memoria de dados (estagio MEM)
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && mem_wr_en) begin
            dmem_shadow[mem_wr_addr] <= mem_wr_data;
            $display("[MEM] dmem[%0d] = 0x%08X", mem_wr_addr, mem_wr_data);
            $fdisplay(out_fd, "MEM[%3d] = 0x%08X", mem_wr_addr, mem_wr_data);
        end
    end

    // =========================================================================
    // Deteccao de halt e execucao principal
    // =========================================================================
    //
    // No pipeline com resolucao de branch no estagio EX, a instrucao
    // "beq x0, x0, 0" causa dois flushes por ciclo, fazendo o PC oscilar
    // com periodo 3:  H -> H+4 -> H+8 -> H -> H+4 -> H+8 -> ...
    //
    // Por isso NAO e possivel detectar halt por estabilidade de PC.
    // A estrategia correta e detectar a repeticao periodica:
    //   se PC_atual == PC_de_BRANCH_PERIOD_ciclos_atras por HALT_CONFIRM
    //   ciclos consecutivos, o programa esta em halt.
    //
    localparam BRANCH_PERIOD = 3;    // periodo da oscilacao do PC (EX-stage branch)
    localparam HALT_CONFIRM  = 9;    // 3 periodos completos para confirmar

    logic [31:0] pc_hist [0:BRANCH_PERIOD];
    integer      halt_cnt;
    integer      cycle_cnt;
    logic        halted;

    integer i, j, errors;

    initial begin
        out_fd    = $fopen("output.txt", "w");
        halt_cnt  = 0;
        cycle_cnt = 0;
        halted    = 1'b0;

        for (j = 0; j <= BRANCH_PERIOD; j++) pc_hist[j] = 32'hFFFFFFFF;
        for (i = 0; i < 256; i++)            dmem_shadow[i] = 32'b0;

        // Aguarda fim do reset
        @(posedge rst_n);

        // Loop principal: roda ate halt ou timeout
        while (!halted && cycle_cnt < MAX_CYCLES) begin
            @(posedge clk);
            #1;   // aguarda NBA e logica combinacional estabilizarem

            cycle_cnt++;

            // Desloca historico de PCs
            for (j = BRANCH_PERIOD; j > 0; j--)
                pc_hist[j] = pc_hist[j-1];
            pc_hist[0] = PC;

            // Detecta repeticao com periodo BRANCH_PERIOD:
            //   beq x0,x0,0 faz PC=H -> H+4 -> H+8 -> H -> ...
            //   pc_hist[0] == pc_hist[BRANCH_PERIOD] quando o ciclo se fecha
            if (pc_hist[0] != 32'hFFFFFFFF &&
                pc_hist[BRANCH_PERIOD] != 32'hFFFFFFFF &&
                pc_hist[0] == pc_hist[BRANCH_PERIOD]) begin
                halt_cnt++;
                if (halt_cnt >= HALT_CONFIRM)
                    halted = 1'b1;
            end else begin
                halt_cnt = 0;
            end
        end

        if (cycle_cnt >= MAX_CYCLES)
            $display("AVISO: timeout apos %0d ciclos (halt nao detectado)", MAX_CYCLES);
        else
            $display("Halt detectado em PC=0x%08X apos %0d ciclos.", PC, cycle_cnt);

        // =====================================================================
        // Dump do estado final
        // =====================================================================
        $display("--- Estado final dos registradores ---");
        $fdisplay(out_fd, "--- estado final ---");

        // Acessa registradores diretamente via hierarquia
        for (i = 1; i < 32; i++) begin
            if (dut.datapath.regfile.rf[i] !== 32'b0) begin
                $display("  x%0d = 0x%08X", i, dut.datapath.regfile.rf[i]);
                $fdisplay(out_fd, "FINAL REG %2d = 0x%08X", i, dut.datapath.regfile.rf[i]);
            end
        end

        $display("--- Estado final da dmem (palavras nao-zero) ---");
        for (i = 0; i < 16; i++) begin
            if (dut.datapath.dmem.ram[i] !== 32'b0) begin
                $display("  dmem[%0d] = 0x%08X", i, dut.datapath.dmem.ram[i]);
                $fdisplay(out_fd, "FINAL MEM[%3d] = 0x%08X", i, dut.datapath.dmem.ram[i]);
            end
        end

        $fclose(out_fd);

        // =====================================================================
        // Comparacao com golden.txt
        // =====================================================================
        $display("--- Comparacao com golden.txt ---");
        errors = compare_with_golden();
        if (errors == 0)
            $display("PASS: saida corresponde ao golden.");
        else
            $display("FAIL: %0d diferenca(s) encontrada(s).", errors);

        $stop;
    end

    // =========================================================================
    // Funcao de comparacao com golden.txt
    // =========================================================================
    function automatic integer compare_with_golden();
        integer gfd, ofd;
        string  gline, oline;
        integer errs;
        errs = 0;

        gfd = $fopen("golden.txt", "r");
        ofd = $fopen("output.txt", "r");

        if (gfd == 0) begin
            $display("AVISO: golden.txt nao encontrado -- pulando comparacao.");
            return 0;
        end
        if (ofd == 0) begin
            $display("ERRO: output.txt nao pode ser aberto.");
            return 1;
        end

        while (!$feof(gfd)) begin
            void'($fgets(gline, gfd));
            void'($fgets(oline, ofd));
            if (gline != oline) begin
                $display("DIFF golden: %s  output: %s", gline, oline);
                errs++;
            end
        end

        $fclose(gfd);
        $fclose(ofd);
        return errs;
    endfunction

endmodule
