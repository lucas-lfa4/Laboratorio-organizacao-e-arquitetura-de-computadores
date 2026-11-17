// =============================================================================
// pl_imem.sv
// Memoria de instrucoes -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : instruction.mif  (sintese Quartus)
//              program.hex      (simulacao ModelSim via $readmemh)
//
// Leitura assincrona (combinatorial): instr = rom[addr]
// Endereco de palavra = PC[9:2]  (8 bits, seleciona 1 de 256 posicoes)
// =============================================================================

`timescale 1ns / 1ps

module pl_imem (
    input  logic [7:0]  addr,    // endereco de palavra: PC[9:2]
    output logic [31:0] instr    // instrucao (combinatorial)
);

    (* ram_init_file = "instruction.mif" *) logic [31:0] rom [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) rom[i] = 32'h00000013; // NOP padrao
        $readmemh("program.hex", rom);
    end
    // synthesis translate_on

    assign instr = rom[addr];

endmodule
