// =============================================================================
// pl_forward.sv
// Unidade de Forwarding (adiantamento de dados) -- RV32I pipelined
//
// Resolve hazards RAW (Read After Write) por adiantamento:
//   2'b10 -> adiantar de EX/MEM (resultado da ALU do ciclo anterior)
//   2'b01 -> adiantar de MEM/WB (resultado da ALU ou da memoria)
//   2'b00 -> sem adiantamento (usar saida do banco de registradores)
//
// Prioridade: EX/MEM tem precedencia sobre MEM/WB para o mesmo registrador.
// x0 nunca e adiantado (hardwired a zero).
// =============================================================================

`timescale 1ns / 1ps

module pl_forward (
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,
    input  logic [4:0] ex_mem_rd,
    input  logic [4:0] mem_wb_rd,
    input  logic       ex_mem_reg_write,
    input  logic       mem_wb_reg_write,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    assign forward_a =
        (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) ? 2'b10 :
        (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) ? 2'b01 :
                                                                                  2'b00;

    assign forward_b =
        (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) ? 2'b10 :
        (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) ? 2'b01 :
                                                                                  2'b00;

endmodule
