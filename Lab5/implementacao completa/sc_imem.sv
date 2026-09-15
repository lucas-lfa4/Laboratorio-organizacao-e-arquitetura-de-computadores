// =============================================================================
// sc_imem.sv
// Instruction Memory - single-cycle RISC-V
//
// Capacity  : 256 words x 32 bits = 1 KB
// Init file : program.hex  ($readmemh format, one 32-bit word per line)
//
// -- Async read ---------------------------------------------------------------
//   Implemented as a plain SystemVerilog array with a continuous assignment.
//   instr = rom[addr] is purely combinatorial: no clock is required.
//   Quartus infers MLAB (LUT-RAM) which natively supports async reads.
//
//   Timing view (50 MHz, T = 20 ns):
//     posedge -> PC updated -> addr = pc[9:2] stable ->
//     instr available combinatorially ->
//     decode -> regfile -> ALU -> dmem(async) -> mux -> write_back ->
//     setup before next posedge
//
//   The full 20 ns period is available for the combinatorial datapath.
//
// -- Address mapping ----------------------------------------------------------
//   PC is a byte address (increments by 4).
//   Word address = pc[9:2] (8 bits, selects 1 of 256 locations).
// =============================================================================

`timescale 1ns / 1ps

module sc_imem (
    input  logic [7:0]  addr,    // Word address: connect pc[9:2]
    output logic [31:0] instr    // 32-bit instruction word (combinatorial)
);

    logic [31:0] rom [0:255];

    initial begin
        for (int i = 0; i < 256; i++) rom[i] = 32'h00000013; // default: NOP
        $readmemh("program.hex", rom);
    end

    assign instr = rom[addr];

endmodule
