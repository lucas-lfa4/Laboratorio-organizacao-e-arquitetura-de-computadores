// alu_64.sv
// ALU de 64 bits para a unidade de multiplicacao
// Baseado na Figura 3.3 - Patterson & Hennessy, Computer Organization and Design
//
// Para o algoritmo de multiplicacao, apenas a operacao de soma e necessaria.

module alu_64 (
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] sum
);
    assign sum = a + b;

endmodule
