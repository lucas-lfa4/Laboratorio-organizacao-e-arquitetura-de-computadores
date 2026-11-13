// =============================================================================
// pl_datapath.sv
// Datapath pipeline de 5 estagios -- RV32I (P&H secoes 4.6-4.10)
//
// Estagios:
//   IF  -- busca instrucao (pl_imem, PC)
//   ID  -- decodificacao, leitura de registradores, deteccao de hazard
//   EX  -- execucao (ALU), resolucao de branch, forwarding
//   MEM -- acesso a memoria de dados / MMIO
//   WB  -- escrita no banco de registradores
//
// Tratamento de hazards:
//   Load-use stall : 1 ciclo de bolha (pl_hazard)
//   RAW data       : forwarding EX/MEM -> EX e MEM/WB -> EX (pl_forward)
//   Branch taken / JAL / JALR : flush de IF e ID (2 NOPs) na resolucao em EX
//
// Decodificacao de endereco (estagio MEM):
//   alu_result[10] = 0 -> memoria de dados  (0x000-0x3FF)
//   alu_result[10] = 1 -> MMIO              (0x400-0x7FF)
//     alu_result[4:2] seleciona periferico dentro da janela MMIO
// =============================================================================

`timescale 1ns / 1ps

import pl_pipe_pkg::*;

module pl_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Sinais de controle vindos do estagio ID (pl_control)
    input  logic        ALUSrc,
    input  logic [1:0]  ALUSrcA,      // 00=rs1, 01=PC (AUIPC), 10=zero (LUI)
    input  logic        MemtoReg,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic        Jal,
    input  logic        Jalr,
    input  logic [1:0]  ALUOp,

    // Codigo de operacao da ALU (pl_alu_ctrl, usa campos do estagio EX)
    input  logic [3:0]  ALU_CC,

    // Campos realimentados ao pl_cpu para controle e ALU ctrl
    output logic [6:0]  Opcode,       // opcode do estagio ID (para pl_control)
    output logic [2:0]  Funct3_EX,    // funct3 do estagio EX (para pl_alu_ctrl)
    output logic [6:0]  Funct7_EX,    // funct7 do estagio EX (para pl_alu_ctrl)
    output logic [1:0]  ALUOp_EX,     // ALUOp do estagio EX  (para pl_alu_ctrl)

    output logic [31:0] PC,           // PC atual (testbench / debug)

    // E/S Mapeada em Memoria -- DE2-115
    input  logic [17:0] SW,
    input  logic [3:0]  KEY,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    // Observabilidade para o testbench
    output logic        wb_reg_write,   // pulso quando WB escreve registrador
    output logic [4:0]  wb_reg_dst,     // registrador destino (WB)
    output logic [31:0] wb_reg_data,    // dado escrito (WB)
    output logic        mem_wr_en,      // escrita na dmem (nao MMIO)
    output logic [7:0]  mem_wr_addr,    // endereco de palavra da dmem (MEM)
    output logic [31:0] mem_wr_data     // dado escrito na dmem (MEM)
);

    // =========================================================================
    // Sinais internos
    // =========================================================================

    // PC
    logic [31:0] pc_reg, pc_plus4;

    // Registradores de pipeline
    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    // Hazard / branch
    logic        stall;
    logic        pc_src;          // 1 = desviar (branch tomado, JAL ou JALR)
    logic        branch_taken;    // resultado da comparacao do branch
    logic [31:0] branch_target;   // PC + imm      (branches e JAL)
    logic [31:0] pc_target;       // alvo final    (JALR usa rs1 + imm)

    // ID
    logic [31:0] rd1, rd2, imm_ext;

    // EX -- forwarding
    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] fwd_srca, fwd_srcb, alu_srca, alu_srcb;
    logic [31:0] alu_result;
    logic [31:0] ex_result;       // alu_result ou PC+4 (JAL/JALR)
    logic        zero;

    // WB
    logic [31:0] wb_data;

    // MEM
    logic        mmio_sel;
    logic [31:0] dmem_rd, mmio_rd, mem_read_data;
    logic [31:0] load_data;       // dado lido apos selecao de byte/halfword
    logic [31:0] store_data;      // dado de escrita alinhado (SB/SH/SW)
    logic [3:0]  byte_en;         // bytes da palavra que serao escritos
    logic [31:0] dmem_wdata;      // palavra final escrita na dmem

    // =========================================================================
    // IF -- Busca de instrucao
    // =========================================================================
    logic [31:0] instr_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'b0;
        else if (pc_src) pc_reg <= pc_target;       // desvio tem prioridade
        else if (!stall) pc_reg <= pc_plus4;
        // else stall: PC mantido
    end

    assign PC       = pc_reg;
    assign pc_plus4 = pc_reg + 32'd4;

    pl_imem imem (
        .addr  (pc_reg[9:2]),
        .instr (instr_if)
    );

    // =========================================================================
    // Registrador IF/ID
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                    // reset assicrono (unico sinal na lista)
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (pc_src) begin           // flush sincrono: branch taken
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (!stall) begin           // avanco normal
            if_id.pc    <= pc_reg;
            if_id.instr <= instr_if;
        end
        // else stall: mantido
    end

    // =========================================================================
    // ID -- Decodificacao, banco de registradores, imediato, hazard
    // =========================================================================
    assign Opcode = if_id.instr[6:0];

    // Deteccao de hazard load-use
    pl_hazard hazard (
        .if_id_rs1      (if_id.instr[19:15]),
        .if_id_rs2      (if_id.instr[24:20]),
        .id_ex_rd       (id_ex.rd),
        .id_ex_mem_read (id_ex.mem_read),
        .stall          (stall)
    );

    // Dado de write-back (mux WB): usado tambem pelo forwarding MEM/WB->EX
    assign wb_data = mem_wb.mem_to_reg ? mem_wb.read_data : mem_wb.alu_result;

    pl_regfile regfile (
        .clk       (clk),
        .RegWrite  (mem_wb.reg_write),
        .rs1       (if_id.instr[19:15]),
        .rs2       (if_id.instr[24:20]),
        .rd        (mem_wb.rd),
        .WriteData (wb_data),
        .ReadData1 (rd1),
        .ReadData2 (rd2)
    );

    pl_sign_ext sign_ext (
        .Instr  (if_id.instr),
        .ImmExt (imm_ext)
    );

    // Saidas para o testbench (estagio WB)
    assign wb_reg_write = mem_wb.reg_write;
    assign wb_reg_dst   = mem_wb.rd;
    assign wb_reg_data  = wb_data;

    // =========================================================================
    // Registrador ID/EX
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      // reset assicrono (unico sinal na lista)
            id_ex.alu_src    <= 1'b0;
            id_ex.alu_src_a  <= 2'b00;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.jal        <= 1'b0;
            id_ex.jalr       <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else if (stall || pc_src) begin    // NOP sincrono: load-use ou branch
            id_ex.alu_src    <= 1'b0;
            id_ex.alu_src_a  <= 2'b00;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.jal        <= 1'b0;
            id_ex.jalr       <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else begin
            id_ex.alu_src    <= ALUSrc;
            id_ex.alu_src_a  <= ALUSrcA;
            id_ex.mem_to_reg <= MemtoReg;
            id_ex.reg_write  <= RegWrite;
            id_ex.mem_read   <= MemRead;
            id_ex.mem_write  <= MemWrite;
            id_ex.alu_op     <= ALUOp;
            id_ex.branch     <= Branch;
            id_ex.jal        <= Jal;
            id_ex.jalr       <= Jalr;
            id_ex.pc         <= if_id.pc;
            id_ex.rd1        <= rd1;
            id_ex.rd2        <= rd2;
            id_ex.rs1        <= if_id.instr[19:15];
            id_ex.rs2        <= if_id.instr[24:20];
            id_ex.rd         <= if_id.instr[11:7];
            id_ex.imm_ext    <= imm_ext;
            id_ex.funct3     <= if_id.instr[14:12];
            id_ex.funct7     <= if_id.instr[31:25];
        end
    end

    // Realimentacao para pl_alu_ctrl (usa campos do estagio EX)
    assign Funct3_EX = id_ex.funct3;
    assign Funct7_EX = id_ex.funct7;
    assign ALUOp_EX  = id_ex.alu_op;

    // =========================================================================
    // EX -- Forwarding, ALU, resolucao de branch
    // =========================================================================
    pl_forward forward (
        .id_ex_rs1        (id_ex.rs1),
        .id_ex_rs2        (id_ex.rs2),
        .ex_mem_rd        (ex_mem.rd),
        .mem_wb_rd        (mem_wb.rd),
        .ex_mem_reg_write (ex_mem.reg_write),
        .mem_wb_reg_write (mem_wb.reg_write),
        .forward_a        (fwd_a),
        .forward_b        (fwd_b)
    );

    // Mux de forwarding para SrcA
    always_comb begin
        case (fwd_a)
            2'b10:   fwd_srca = ex_mem.alu_result;
            2'b01:   fwd_srca = wb_data;
            default: fwd_srca = id_ex.rd1;
        endcase
    end

    // Mux de forwarding para SrcB (antes do mux ALUSrc)
    always_comb begin
        case (fwd_b)
            2'b10:   fwd_srcb = ex_mem.alu_result;
            2'b01:   fwd_srcb = wb_data;
            default: fwd_srcb = id_ex.rd2;
        endcase
    end

    // Mux ALUSrcA: rs1 (ja com forwarding), PC ou zero
    //   Fica DEPOIS do forwarding: em LUI/AUIPC os bits [19:15] sao parte do
    //   imediato, e o valor que o forwarding encaminhar e simplesmente descartado.
    always_comb begin
        case (id_ex.alu_src_a)
            2'b01:   alu_srca = id_ex.pc;    // AUIPC: PC + imm
            2'b10:   alu_srca = 32'b0;       // LUI:   0  + imm
            default: alu_srca = fwd_srca;    // demais instrucoes: rs1
        endcase
    end

    // Mux ALUSrc: imediato ou registrador
    assign alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb;

    pl_alu alu (
        .SrcA      (alu_srca),
        .SrcB      (alu_srcb),
        .Operation (ALU_CC),
        .ALUResult (alu_result),
        .Zero      (zero)
    );

    // -------------------------------------------------------------------------
    // Branch / jumps -- resolvidos no estagio EX (flush de 2 instrucoes)
    // -------------------------------------------------------------------------
    // Comparador de branch: usa os operandos ja com forwarding (rs1, rs2).
    // A condicao e escolhida pelo funct3 da instrucao.
    always_comb begin
        case (id_ex.funct3)
            3'b000:  branch_taken = (fwd_srca == fwd_srcb);                  // BEQ
            3'b001:  branch_taken = (fwd_srca != fwd_srcb);                  // BNE
            3'b100:  branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb)); // BLT
            3'b101:  branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb)); // BGE
            3'b110:  branch_taken = (fwd_srca <  fwd_srcb);                  // BLTU
            3'b111:  branch_taken = (fwd_srca >= fwd_srcb);                  // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // Alvos:
    //   branches e JAL -> PC + imm
    //   JALR           -> (rs1 + imm) & ~1   (a soma e feita pela ALU)
    assign branch_target = id_ex.pc + id_ex.imm_ext;
    assign pc_target     = id_ex.jalr ? {alu_result[31:1], 1'b0} : branch_target;
    assign pc_src        = (id_ex.branch && branch_taken) || id_ex.jal || id_ex.jalr;

    // JAL/JALR escrevem o endereco de retorno (PC+4) em rd
    assign ex_result = (id_ex.jal || id_ex.jalr) ? (id_ex.pc + 32'd4) : alu_result;

    // =========================================================================
    // Registrador EX/MEM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.mem_to_reg  <= 1'b0;
            ex_mem.reg_write   <= 1'b0;
            ex_mem.mem_read    <= 1'b0;
            ex_mem.mem_write   <= 1'b0;
            ex_mem.alu_result  <= 32'b0;
            ex_mem.write_data  <= 32'b0;
            ex_mem.rd          <= 5'b0;
            ex_mem.funct3      <= 3'b0;
        end else begin
            ex_mem.mem_to_reg  <= id_ex.mem_to_reg;
            ex_mem.reg_write   <= id_ex.reg_write;
            ex_mem.mem_read    <= id_ex.mem_read;
            ex_mem.mem_write   <= id_ex.mem_write;
            ex_mem.alu_result  <= ex_result;   // inclui PC+4 de JAL/JALR
            ex_mem.write_data  <= fwd_srcb;   // rs2 adiantado (para SW/MMIO)
            ex_mem.rd          <= id_ex.rd;
            ex_mem.funct3      <= id_ex.funct3;
        end
    end

    // =========================================================================
    // MEM -- Memoria de dados + MMIO
    // =========================================================================
    assign mmio_sel = ex_mem.alu_result[10];

    // -------------------------------------------------------------------------
    // Stores: SB / SH / SW
    // -------------------------------------------------------------------------
    // A dmem e organizada em palavras de 32 bits. Para SB/SH, o dado de rs2 e
    // replicado nas posicoes possiveis e byte_en indica quais bytes mudam,
    // conforme o offset alu_result[1:0] (little-endian: byte 0 = bits 7:0).
    always_comb begin
        case (ex_mem.funct3[1:0])
            2'b00: begin                                       // SB
                store_data = {4{ex_mem.write_data[7:0]}};
                byte_en    = 4'b0001 << ex_mem.alu_result[1:0];
            end
            2'b01: begin                                       // SH
                store_data = {2{ex_mem.write_data[15:0]}};
                byte_en    = ex_mem.alu_result[1] ? 4'b1100 : 4'b0011;
            end
            default: begin                                     // SW
                store_data = ex_mem.write_data;
                byte_en    = 4'b1111;
            end
        endcase
    end

    // Read-modify-write: a leitura da dmem e assincrona, entao a palavra atual
    // (dmem_rd) esta disponivel no mesmo ciclo. Os bytes habilitados vem do
    // store_data e os demais sao mantidos.
    assign dmem_wdata = { byte_en[3] ? store_data[31:24] : dmem_rd[31:24],
                          byte_en[2] ? store_data[23:16] : dmem_rd[23:16],
                          byte_en[1] ? store_data[15:8]  : dmem_rd[15:8],
                          byte_en[0] ? store_data[7:0]   : dmem_rd[7:0] };

    pl_dmem dmem (
        .clk       (clk),
        .MemWrite  (ex_mem.mem_write & ~mmio_sel),
        .addr      (ex_mem.alu_result[9:2]),
        .WriteData (dmem_wdata),
        .ReadData  (dmem_rd)
    );

    pl_mmio mmio (
        .clk       (clk),
        .rst_n     (rst_n),
        .MemWrite  (ex_mem.mem_write &  mmio_sel),
        .MemRead   (ex_mem.mem_read  &  mmio_sel),
        .addr      (ex_mem.alu_result[4:2]),
        .WriteData (ex_mem.write_data),
        .SW        (SW),
        .KEY       (KEY),
        .ReadData  (mmio_rd),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

    assign mem_read_data = mmio_sel ? mmio_rd : dmem_rd;

    // -------------------------------------------------------------------------
    // Loads: LB / LH / LW / LBU / LHU
    // -------------------------------------------------------------------------
    // Seleciona o byte/halfword pelo offset alu_result[1:0] e estende com
    // sinal (LB, LH) ou com zeros (LBU, LHU). Feito no estagio MEM, entao o
    // forwarding MEM/WB -> EX ja recebe o valor final.
    logic [7:0]  ld_byte;
    logic [15:0] ld_half;

    always_comb begin
        case (ex_mem.alu_result[1:0])
            2'b00:   ld_byte = mem_read_data[7:0];
            2'b01:   ld_byte = mem_read_data[15:8];
            2'b10:   ld_byte = mem_read_data[23:16];
            default: ld_byte = mem_read_data[31:24];
        endcase

        ld_half = ex_mem.alu_result[1] ? mem_read_data[31:16] : mem_read_data[15:0];

        case (ex_mem.funct3)
            3'b000:  load_data = {{24{ld_byte[7]}},  ld_byte};   // LB
            3'b001:  load_data = {{16{ld_half[15]}}, ld_half};   // LH
            3'b100:  load_data = {24'b0, ld_byte};               // LBU
            3'b101:  load_data = {16'b0, ld_half};               // LHU
            default: load_data = mem_read_data;                  // LW
        endcase
    end

    // Saidas de observabilidade para o testbench
    assign mem_wr_en   = ex_mem.mem_write & ~mmio_sel;
    assign mem_wr_addr = ex_mem.alu_result[9:2];
    assign mem_wr_data = dmem_wdata;     // palavra completa apos SB/SH/SW

    // =========================================================================
    // Registrador MEM/WB
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb.mem_to_reg <= 1'b0;
            mem_wb.reg_write  <= 1'b0;
            mem_wb.alu_result <= 32'b0;
            mem_wb.read_data  <= 32'b0;
            mem_wb.rd         <= 5'b0;
        end else begin
            mem_wb.mem_to_reg <= ex_mem.mem_to_reg;
            mem_wb.reg_write  <= ex_mem.reg_write;
            mem_wb.alu_result <= ex_mem.alu_result;
            mem_wb.read_data  <= load_data;   // ja com selecao/extensao
            mem_wb.rd         <= ex_mem.rd;
        end
    end

    // WB: wb_data = mem_to_reg ? read_data : alu_result  (definido acima, no bloco ID)

endmodule
