// =============================================================================
// pl_hazard.sv
// Unidade de Deteccao de Hazard -- RV32I pipelined
//
// Detecta hazard load-use: instrucao LW seguida imediatamente por instrucao
// que le o registrador destino do LW.
//
// Acao ao detectar stall:
//   - PC mantido (nao avanca)
//   - IF/ID mantido (instrucao dependente fica em ID mais um ciclo)
//   - ID/EX zerado (NOP/bolha injetada no pipeline)
// =============================================================================

`timescale 1ns / 1ps

module pl_hazard (
    input  logic [4:0] if_id_rs1,       // rs1 da instrucao em ID
    input  logic [4:0] if_id_rs2,       // rs2 da instrucao em ID
    input  logic [4:0] id_ex_rd,        // rd da instrucao em EX
    input  logic       id_ex_mem_read,  // instrucao em EX e LW?
    output logic       stall            // 1 = inserir bolha
);

    assign stall = id_ex_mem_read &&
                   ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2)) &&
                   (id_ex_rd != 5'b0);

endmodule
