// =============================================================================
// sc_regfile.sv
// 32 x 32-bit Register File - single-cycle RISC-V
//
// Reads  : asynchronous (combinatorial) - results are available immediately
// Writes : synchronous on the rising edge of clk
//
// Register x0 (index 0) is hardwired to zero per the RISC-V specification:
//   - reads always return 0 regardless of what was written
//   - writes to x0 are silently discarded
// =============================================================================

`timescale 1ns / 1ps

module sc_regfile (
    input  logic        clk,
    input  logic        RegWrite,   // 1 = write WriteData into register rd
    input  logic [4:0]  rs1,        // Source register 1 address
    input  logic [4:0]  rs2,        // Source register 2 address
    input  logic [4:0]  rd,         // Destination register address
    input  logic [31:0] WriteData,  // Data to write into rd
    output logic [31:0] ReadData1,  // rs1 value
    output logic [31:0] ReadData2   // rs2 value
);

    logic [31:0] regs [31:0];

    // Initialize to 0 for simulation (ModelSim starts arrays at X).
    // Quartus ignores 'initial' blocks during synthesis; on the FPGA all
    // flip-flops power up at 0 after bitstream programming.
    initial begin
        for (int i = 0; i < 32; i++)
            regs[i] = 32'b0;
    end

    // -------------------------------------------------------------------------
    // Asynchronous reads
    // x0 is hardwired to zero: override any stored value at index 0
    // -------------------------------------------------------------------------
    assign ReadData1 = (rs1 == 5'b0) ? 32'b0 : regs[rs1];
    assign ReadData2 = (rs2 == 5'b0) ? 32'b0 : regs[rs2];

    // -------------------------------------------------------------------------
    // Synchronous write on rising edge
    // Writing to x0 is ignored (rd != 0 guard)
    // Using 'always' instead of 'always_ff' so that ModelSim allows the
    // separate 'initial' block above to coexist on the same variable.
    // Synthesis result is identical: Quartus infers flip-flops either way.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (RegWrite && rd != 5'b0)
            regs[rd] <= WriteData;
    end

endmodule
