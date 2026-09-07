`timescale 1ns/1ps

module safecrack_tb;

    logic       clk;
    logic       rst_n;
    logic [3:0] btn;
    logic       unlocked;

    // Instancia do DUT
    safecrack dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .btn      (btn),
        .unlocked (unlocked)
    );

    // Geracao de clock (50 MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // Task para pressionar um botao (b_mask indica qual botao apertar em logica positiva)
    task press_button(input logic [3:0] b_mask, input int hold_cycles);
        @(negedge clk);
        btn = ~b_mask;                 // Pressiona (aplica logica negativa)
        repeat (hold_cycles) @(posedge clk);
        @(negedge clk);
        btn = 4'b1111;                 // Solta todos (ativo baixo)
        repeat (3) @(posedge clk);     
    endtask

    initial begin
        $dumpfile("safecrack.vcd");
        $dumpvars(0, safecrack_tb);

        // Condicao inicial
        rst_n = 1'b1;
        btn   = 4'b1111;  // Todos soltos (1)

        // ------------------------------------------------------------------
        // Teste 1: Reset
        // ------------------------------------------------------------------
        $display("\n=== Teste 1: Inicializacao e Reset ===");
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ------------------------------------------------------------------
        // Teste 2: Sequencia Incorreta (Azul -> Verde)
        // ------------------------------------------------------------------
        $display("\n=== Teste 2: Sequencia Errada ===");
        press_button(4'b0001, 2); // Azul
        press_button(4'b0100, 2); // Verde (Errado, deve resetar a FSM)
        
        // ------------------------------------------------------------------
        // Teste 3: Sequencia Correta (Azul -> Amarelo -> Amarelo -> Vermelho)
        // ------------------------------------------------------------------
        $display("\n=== Teste 3: Sequencia Correta ===");
        press_button(4'b0001, 2); // Azul
        press_button(4'b0010, 2); // Amarelo
        press_button(4'b0010, 2); // Amarelo
        press_button(4'b1000, 20); // Vermelho (Segurado por 20 ciclos para testar borda)

        @(negedge clk);
        if (unlocked) $display("[PASS] Cofre abriu com sucesso!");
        else          $display("[FAIL] Cofre nao abriu.");

        // ------------------------------------------------------------------
        // Teste 4: Reset apos abrir
        // ------------------------------------------------------------------
        $display("\n=== Teste 4: Trancar cofre (Reset) ===");
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        if (!unlocked) $display("[PASS] Cofre trancado com sucesso.");

        $display("\n=== Simulacao concluida ===\n");
        $finish;
    end

endmodule
