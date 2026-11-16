// =============================================================================
// pl_sign_ext.sv
// Extensao de Sinal de Imediatos -- RV32I pipelined (P&H secao 4.4)
//
// Formatos suportados:
//   I-type (lw)  : imm[11:0]  = inst[31:20]
//   S-type (sw)  : imm[11:5]  = inst[31:25], imm[4:0] = inst[11:7]
//   B-type (beq) : imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
//                  imm[4:1]=inst[11:8], imm[0]=0
// =============================================================================

`timescale 1ns / 1ps

module pl_sign_ext (
    input  logic [31:0] Instr,
    output logic [31:0] ImmExt
);

    localparam LOAD   = 7'b0000011;
    localparam STORE  = 7'b0100011;
    localparam BRANCH = 7'b1100011;

    always_comb begin
        case (Instr[6:0])
            LOAD:   ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            STORE:  ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

            BRANCH: ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                               Instr[30:25], Instr[11:8], 1'b0};

            default: ImmExt = 32'b0;
        endcase
    end

endmodule
