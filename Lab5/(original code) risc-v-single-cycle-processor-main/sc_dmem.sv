// =============================================================================
// sc_dmem.sv
// Data Memory - single-cycle RISC-V
//
// Capacity  : 256 words x 32 bits = 1 KB (word-aligned, LW/SW only)
// Init file : data.hex  ($readmemh format, one 32-bit word per line)
//
// -- Async read ---------------------------------------------------------------
//   ReadData = ram[addr] is a continuous assignment - purely combinatorial.
//   As soon as alu_result is stable, ReadData is valid with no clock needed.
//   Quartus infers MLAB (LUT-RAM) which natively supports async reads.
//
// -- Sync write ---------------------------------------------------------------
//   SW writes are committed on posedge clk, the same edge used by the
//   register file. A SW in cycle N writes memory at the end of cycle N;
//   the next LW in cycle N+1 reads the updated value.
//
// -- Address mapping ----------------------------------------------------------
//   ALU computes a byte address; the word address is alu_result[9:2].
//   Only word-aligned LW/SW are supported (Section 4.4 subset).
// =============================================================================

`timescale 1ns / 1ps

module sc_dmem (
    input  logic        clk,
    input  logic        MemWrite,    // 1 = write WriteData to addr (SW)
    input  logic [7:0]  addr,        // Word address: connect alu_result[9:2]
    input  logic [31:0] WriteData,   // Data to write (rs2 value)
    output logic [31:0] ReadData     // Data read (combinatorial)
);

    logic [31:0] ram [0:255];

    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h0;
        $readmemh("data.hex", ram);
    end

    assign ReadData = ram[addr];   // async read

    always @(posedge clk)          // sync write
        if (MemWrite) ram[addr] <= WriteData;

endmodule
