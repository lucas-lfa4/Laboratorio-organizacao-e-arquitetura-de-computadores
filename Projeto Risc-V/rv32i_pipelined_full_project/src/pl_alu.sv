// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD  -- adicao com sinal
//   4'd02 : SUB  -- subtracao com sinal
//   4'd04 : OR   -- OU bit a bit
//   4'd05 : AND  -- E bit a bit
//   4'd06 : XOR  -- OU exclusivo bit a bit
//   4'd07 : SLL  -- deslocamento logico a esquerda  (usa SrcB[4:0])
//   4'd08 : SRL  -- deslocamento logico a direita   (usa SrcB[4:0])
//   4'd09 : SRA  -- deslocamento aritmetico a direita (usa SrcB[4:0])
//   4'd11 : SLT  -- set-less-than com sinal
//   4'd12 : SLTU -- set-less-than sem sinal
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    output logic [31:0] ALUResult,
    output logic        Zero
);

    always_comb begin
        case (Operation)
            4'd01:   ALUResult = $signed(SrcA) + $signed(SrcB);
            4'd02:   ALUResult = $signed(SrcA) - $signed(SrcB);
            4'd04:   ALUResult = SrcA | SrcB;
            4'd05:   ALUResult = SrcA & SrcB;
            4'd06:   ALUResult = SrcA ^ SrcB;                     // XOR
            4'd07:   ALUResult = SrcA << SrcB[4:0];               // SLL
            4'd08:   ALUResult = SrcA >> SrcB[4:0];               // SRL
            4'd09:   ALUResult = $signed(SrcA) >>> SrcB[4:0];     // SRA
            4'd11:   ALUResult = 32'($signed(SrcA) < $signed(SrcB));
            4'd12:   ALUResult = 32'(SrcA < SrcB);                // SLTU
            default: ALUResult = 32'b0;
        endcase
    end

    assign Zero = (ALUResult == 32'b0);

endmodule
