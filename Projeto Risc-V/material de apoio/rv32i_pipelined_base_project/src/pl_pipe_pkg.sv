// =============================================================================
// pl_pipe_pkg.sv
// Definicoes dos registradores de pipeline -- processador RV32I pipelined
//
// Quatro registradores de pipeline (P&H secao 4.6):
//   IF/ID  : resultado da busca de instrucao
//   ID/EX  : resultado da decodificacao + leitura do banco de registradores
//   EX/MEM : resultado da execucao (ALU)
//   MEM/WB : resultado do acesso a memoria
// =============================================================================

package pl_pipe_pkg;

    // ---- IF/ID --------------------------------------------------------------
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
    } if_id_t;

    // ---- ID/EX --------------------------------------------------------------
    typedef struct packed {
        // sinais de controle propagados para os estagios seguintes
        logic        alu_src;
        logic        mem_to_reg;
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic [1:0]  alu_op;
        logic        branch;
        // dados
        logic [31:0] pc;
        logic [31:0] rd1;       // saida 1 do banco de registradores
        logic [31:0] rd2;       // saida 2 do banco de registradores
        logic [4:0]  rs1;       // endereco rs1 (para forwarding)
        logic [4:0]  rs2;       // endereco rs2 (para forwarding)
        logic [4:0]  rd;        // registrador destino
        logic [31:0] imm_ext;   // imediato com extensao de sinal
        logic [2:0]  funct3;
        logic [6:0]  funct7;
    } id_ex_t;

    // ---- EX/MEM -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic        mem_to_reg;
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        // dados
        logic [31:0] alu_result;
        logic [31:0] write_data;  // valor de rs2 apos forwarding (para SW)
        logic [4:0]  rd;
        logic [2:0]  funct3;
    } ex_mem_t;

    // ---- MEM/WB -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic        mem_to_reg;
        logic        reg_write;
        // dados
        logic [31:0] alu_result;
        logic [31:0] read_data;   // dado lido da memoria (LW)
        logic [4:0]  rd;
    } mem_wb_t;

endpackage
