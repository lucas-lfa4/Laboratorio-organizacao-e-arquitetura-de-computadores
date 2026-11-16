// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined (P&H secao 4.4)
//
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Instrucoes suportadas:
//   R-type  (0110011): add, sub, and, or, xor, sll, srl, sra, slt, sltu
//   I-type  (0010011): addi, andi, ori, xori, slti, slli, srli, srai
//   U-type  (0110111): lui
//   U-type  (0010111): auipc
//   I-type  (0000011): lb, lh, lw, lbu, lhu   
//   S-type  (0100011): sb, sh, sw             
//   B-type  (1100011): beq, bne, blt, bge, bltu, bgeu 
//   J-type  (1101111): jal
//   I-type  (1100111): jalr
//
// Tabela de sinais de controle:
//   Sinal     | R  | I-arit | lui | auipc | load | store | branch | jal | jalr
//   ----------|----|--------|-----|-------|------|-------|--------|-----|-----
//   ALUSrc    | 0  |   1    |  1  |   1   |  1   |   1   |   0    |  -  |  1
//   ALUSrcA   | 00 |   00   |  10 |   01  |  00  |   00  |   00   |  -  |  00
//   MemtoReg  | 0  |   0    |  0  |   0   |  1   |   -   |   -    |  0  |  0
//   RegWrite  | 1  |   1    |  1  |   1   |  1   |   0   |   0    |  1  |  1
//   MemRead   | 0  |   0    |  0  |   0   |  1   |   0   |   0    |  0  |  0
//   MemWrite  | 0  |   0    |  0  |   0   |  0   |   1   |   0    |  0  |  0
//   Branch    | 0  |   0    |  0  |   0   |  0   |   0   |   1    |  0  |  0
//   Jal       | 0  |   0    |  0  |   0   |  0   |   0   |   0    |  1  |  0
//   Jalr      | 0  |   0    |  0  |   0   |  0   |   0   |   0    |  0  |  1
//   ALUOp     | 10 |   11   |  00 |   00  |  00  |   00  |   01   |  00 |  00
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic [1:0] ALUSrcA,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic       Jal,
    output logic       Jalr,
    output logic [1:0] ALUOp
);

    localparam R_TYPE = 7'b0110011;
    localparam OP_IMM = 7'b0010011;
    localparam LUI    = 7'b0110111;
    localparam AUIPC  = 7'b0010111;
    localparam LOAD   = 7'b0000011;
    localparam STORE  = 7'b0100011;
    localparam BRANCH = 7'b1100011;
    localparam JAL    = 7'b1101111;
    localparam JALR   = 7'b1100111;

    always_comb begin
        ALUSrc   = 1'b0;
        ALUSrcA  = 2'b00;
        MemtoReg = 1'b0;
        RegWrite = 1'b0;
        MemRead  = 1'b0;
        MemWrite = 1'b0;
        Branch   = 1'b0;
        Jal      = 1'b0;
        Jalr     = 1'b0;
        ALUOp    = 2'b00;

        case (Opcode)
            R_TYPE: begin
                ALUSrc   = 1'b0;
                MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            OP_IMM: begin               // addi, andi, ori, xori, slti, slli, srli, srai
                ALUSrc   = 1'b1;        // B = imediato
                RegWrite = 1'b1;
                ALUOp    = 2'b11;       // decodificar funct3 (pl_alu_ctrl)
            end
            LUI: begin                  // rd = 0 + (imm << 12)
                ALUSrc   = 1'b1;
                ALUSrcA  = 2'b10;       // A = zero
                RegWrite = 1'b1;
                ALUOp    = 2'b00;       // ADD
            end
            AUIPC: begin                // rd = PC + (imm << 12)
                ALUSrc   = 1'b1;
                ALUSrcA  = 2'b01;       // A = PC
                RegWrite = 1'b1;
                ALUOp    = 2'b00;       // ADD
            end
            LOAD: begin                 // lb, lh, lw, lbu, lhu
                ALUSrc   = 1'b1;
                MemtoReg = 1'b1;
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                ALUOp    = 2'b00;       // endereco = rs1 + imm
            end
            STORE: begin                // sb, sh, sw
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = 2'b00;       // endereco = rs1 + imm
            end
            BRANCH: begin               // beq, bne, blt, bge, bltu, bgeu
                Branch   = 1'b1;        // condicao avaliada no estagio EX
                ALUOp    = 2'b01;
            end
            JAL: begin                  // rd = PC+4 ; PC = PC + imm
                Jal      = 1'b1;
                RegWrite = 1'b1;
            end
            JALR: begin                 // rd = PC+4 ; PC = (rs1 + imm) & ~1
                Jalr     = 1'b1;
                ALUSrc   = 1'b1;        // ALU calcula rs1 + imm (alvo)
                RegWrite = 1'b1;
                ALUOp    = 2'b00;       // ADD
            end
            default: ; // sinais permanecem em zero (seguro)
        endcase
    end

endmodule
