// =============================================================================
// sc_alu_ctrl.sv
// ALU Control Unit - single-cycle RISC-V (Section 4.4 - Patterson & Hennessy)
//
// Receives the 2-bit ALUOp from the main control unit and the instruction
// function fields (Funct7, Funct3). Produces the 4-bit Operation code for
// the ALU.
//
// ALUOp encoding (defined in sc_control.sv):
//   2'b00 : Load / Store  -> force ADD (compute address: rs1 + imm)
//   2'b01 : Branch BEQ    -> force SUB (compare: rs1 - rs2, check Zero)
//   2'b10 : R-type        -> use Funct7[5] and Funct3 to select operation
//
// Operation output encoding (consumed by sc_alu.sv):
//   4'd01 : ADD
//   4'd02 : SUB
//   4'd04 : OR
//   4'd05 : AND
//   4'd11 : SLT
//
// R-type decoding table (from RISC-V spec):
//   Funct7   | Funct3 | Instruction
//   0000000  |  000   | ADD
//   0100000  |  000   | SUB  (Funct7[5] = 1 distinguishes SUB from ADD)
//   0000000  |  110   | OR
//   0000000  |  111   | AND
//   0000000  |  010   | SLT
// =============================================================================

`timescale 1ns / 1ps

module sc_alu_ctrl (
    input  logic [1:0] ALUOp,
    input  logic [6:0] Funct7,
    input  logic [2:0] Funct3,
    output logic [3:0] Operation
);

    always_comb begin
        case (ALUOp)
            2'b00: Operation = 4'd01; // Load / Store -> ADD

            2'b01: Operation = 4'd02; // Branch BEQ  -> SUB

            2'b10: begin              // R-type: decode from Funct7 and Funct3
                case (Funct3)
                    // Funct7[5]=1 -> SUB, Funct7[5]=0 -> ADD
                    3'h0: Operation = Funct7[5] ? 4'd02 : 4'd01;
                    3'h6: Operation = 4'd04; // OR
                    3'h7: Operation = 4'd05; // AND
                    3'h2: Operation = 4'd11; // SLT
                    default: Operation = 4'd01;
                endcase
            end

            default: Operation = 4'd01;
        endcase
    end

endmodule
