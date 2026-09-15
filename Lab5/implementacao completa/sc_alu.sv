// =============================================================================
// sc_alu.sv
// 32-bit ALU for single-cycle RISC-V (Section 4.4 - Patterson & Hennessy)
//
// Supported operations (encoding matches the existing project alu.sv):
//   4'd01 : ADD  (R-type add, lw/sw address)
//   4'd02 : SUB  (R-type sub, beq comparison)
//   4'd04 : OR   (R-type or)
//   4'd05 : AND  (R-type and)
//   4'd11 : SLT  (R-type slt, signed)
//
// Zero output: asserted when ALUResult == 0
//   -> used by the branch logic (BEQ takes branch when Zero = 1)
// =============================================================================

`timescale 1ns / 1ps

module sc_alu #(
    parameter DATA_W = 32,
    parameter OP_W   = 4
) (
    input  logic [DATA_W-1:0] SrcA,
    input  logic [DATA_W-1:0] SrcB,
    input  logic [OP_W-1:0]   Operation,
    output logic [DATA_W-1:0] ALUResult,
    output logic               Zero
);

    always_comb begin
        case (Operation)
            4'd01:   ALUResult = signed'(SrcA) + signed'(SrcB);        // ADD
            4'd02:   ALUResult = signed'(SrcA) - signed'(SrcB);        // SUB
            4'd04:   ALUResult = SrcA | SrcB;                          // OR
            4'd05:   ALUResult = SrcA & SrcB;                          // AND
            4'd11:   ALUResult = 32'(signed'(SrcA) < signed'(SrcB));   // SLT
            default: ALUResult = 32'b0;
        endcase
    end

    // Zero flag: used by BEQ (BEQ subtracts rs1 - rs2 and checks if result == 0)
    assign Zero = (ALUResult == 32'b0);

endmodule
