// =============================================================================
// sc_top.sv
// Top-level module - single-cycle RISC-V
//
// Hierarchy:
//   sc_top
//     sc_cpu          - RISC-V CPU (control + datapath)
//       sc_control
//       sc_datapath
//         sc_imem, sc_regfile, sc_sign_ext
//         sc_alu_ctrl, sc_alu
//         sc_dmem
//
// Target board: DE2-115 (Intel Cyclone IV E, 50 MHz clock)
//   CLOCK_50  -> clk
//   KEY[0]    -> rst_n    (active-low push-button reset)
// =============================================================================

`timescale 1ns / 1ps

module sc_top (
    input  logic        clk,
    input  logic        rst_n,    // active-low reset (KEY[0] on DE2-115)
    output logic [31:0] PC        // current PC (SignalTap / testbench)
);

    sc_cpu cpu (
        .clk   (clk),
        .rst_n (rst_n),
        .PC    (PC)
    );

endmodule
