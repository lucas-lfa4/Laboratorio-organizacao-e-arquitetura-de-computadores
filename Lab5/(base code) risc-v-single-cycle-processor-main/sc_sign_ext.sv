// =============================================================================
// sc_sign_ext.sv
// Sign Extender - single-cycle RISC-V (Section 4.4 - Patterson & Hennessy)
//
// Reads the opcode to select the correct immediate format and sign-extends
// the immediate field to 32 bits.
//
// Supported formats:
//
//   I-type (lw):
//     imm[11:0]  = inst[31:20]
//     ImmExt     = { {20{inst[31]}}, inst[31:20] }
//
//   S-type (sw):
//     imm[11:5]  = inst[31:25]
//     imm[4:0]   = inst[11:7]
//     ImmExt     = { {20{inst[31]}}, inst[31:25], inst[11:7] }
//
//   B-type (beq):
//     imm[12]    = inst[31]
//     imm[11]    = inst[7]
//     imm[10:5]  = inst[30:25]
//     imm[4:1]   = inst[11:8]
//     imm[0]     = 0   (branch offsets are always 2-byte aligned)
//     ImmExt     = { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 }
// =============================================================================

`timescale 1ns / 1ps

module sc_sign_ext (
    input  logic [31:0] Instr,   // Full 32-bit instruction word
    output logic [31:0] ImmExt   // Sign-extended 32-bit immediate
);

    localparam LOAD   = 7'b0000011; // lw  (I-type)
    localparam STORE  = 7'b0100011; // sw  (S-type)
    localparam BRANCH = 7'b1100011; // beq (B-type)

    always_comb begin
        case (Instr[6:0])
            LOAD:   // I-type: 12-bit immediate in inst[31:20]
                ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            STORE:  // S-type: split immediate inst[31:25] | inst[11:7]
                ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

            BRANCH: // B-type: inst[31] inst[7] inst[30:25] inst[11:8] 0
                ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                          Instr[30:25], Instr[11:8], 1'b0};

            default:
                ImmExt = 32'b0;
        endcase
    end

endmodule
