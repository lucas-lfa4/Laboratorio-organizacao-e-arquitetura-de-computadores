// =============================================================================
// pl_cpu.sv
// Processador RV32I pipelined -- wrapper CPU (Control + Datapath)
//
// Instancia:
//   pl_control  : unidade de controle principal (estagio ID)
//   pl_alu_ctrl : unidade de controle da ALU    (estagio EX)
//   pl_datapath : datapath de 5 estagios
//
// O pl_control decodifica o opcode do estagio ID; os sinais de controle
// resultantes sao propagados internamente pelo pl_datapath atraves dos
// registradores de pipeline.
//
// O pl_alu_ctrl usa os campos Funct3/Funct7/ALUOp do registrador ID/EX
// (estagio EX) para determinar a operacao da ALU.
// =============================================================================

`timescale 1ns / 1ps

module pl_cpu (
    input  logic        clk,
    input  logic        rst_n,        // reset ativo-baixo assincrono

    output logic [31:0] PC,           // PC atual (observabilidade)

    // E/S Mapeada em Memoria -- DE2-115
    input  logic [17:0] SW,
    input  logic [3:0]  KEY_IO,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    // Observabilidade para o testbench
    output logic        wb_reg_write,
    output logic [4:0]  wb_reg_dst,
    output logic [31:0] wb_reg_data,
    output logic        mem_wr_en,
    output logic [7:0]  mem_wr_addr,
    output logic [31:0] mem_wr_data
);

    // -------------------------------------------------------------------------
    // Sinais internos entre modulos
    // -------------------------------------------------------------------------
    logic [6:0] opcode;

    logic       ALUSrc, MemtoReg, RegWrite, MemRead, MemWrite, Branch;
    logic [1:0] ALUOp;

    logic [2:0] funct3_ex;
    logic [6:0] funct7_ex;
    logic [1:0] aluop_ex;
    logic [3:0] alu_cc;

    // -------------------------------------------------------------------------
    // Unidade de controle principal (estagio ID)
    // -------------------------------------------------------------------------
    pl_control ctrl (
        .Opcode   (opcode),
        .ALUSrc   (ALUSrc),
        .MemtoReg (MemtoReg),
        .RegWrite (RegWrite),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .Branch   (Branch),
        .ALUOp    (ALUOp)
    );

    // -------------------------------------------------------------------------
    // Unidade de controle da ALU (estagio EX -- usa campos do reg ID/EX)
    // -------------------------------------------------------------------------
    pl_alu_ctrl alu_ctrl (
        .ALUOp     (aluop_ex),
        .Funct7    (funct7_ex),
        .Funct3    (funct3_ex),
        .Operation (alu_cc)
    );

    // -------------------------------------------------------------------------
    // Datapath
    // -------------------------------------------------------------------------
    pl_datapath datapath (
        .clk          (clk),
        .rst_n        (rst_n),
        .ALUSrc       (ALUSrc),
        .MemtoReg     (MemtoReg),
        .RegWrite     (RegWrite),
        .MemRead      (MemRead),
        .MemWrite     (MemWrite),
        .Branch       (Branch),
        .ALUOp        (ALUOp),
        .ALU_CC       (alu_cc),
        .Opcode       (opcode),
        .Funct3_EX    (funct3_ex),
        .Funct7_EX    (funct7_ex),
        .ALUOp_EX     (aluop_ex),
        .PC           (PC),
        .SW           (SW),
        .KEY          (KEY_IO),
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

endmodule
