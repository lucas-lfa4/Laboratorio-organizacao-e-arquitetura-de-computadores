// =============================================================================
// sc_cpu_tb.sv
// Testbench for sc_cpu - verification against golden.txt
//
// -- What this testbench does --------------------------------------------------
//   1. Runs the CPU until halt (PC stable for two consecutive cycles).
//   2. Prints to console every register write and every memory write.
//   3. Writes output.txt with the PC trace and final state (registers + memory).
//   4. Compares output.txt line-by-line against golden.txt and prints PASS/FAIL.
//
// -- Prerequisites -------------------------------------------------------------
//   golden.txt must be present in the ModelSim working directory.
//   program.hex and data.hex must also be present there.
//
// -- Expected results for program.hex -----------------------------------------
//   x0  = 00000000  (hardwired zero)
//   x1  = 00000005  (A = 5,    lw)
//   x2  = 00000003  (B = 3,    lw)
//   x3  = 00000008  (A+B = 8,  add)
//   x4  = 00000002  (A-B = 2,  sub)
//   x5  = 00000001  (A AND B,  and)
//   x6  = 00000007  (A OR  B,  or)
//   x7  = 00000001  (3 < 5,    slt true)
//   x8  = 00000000  (5 < 3,    slt false)
//   x9  = 00000008  (lw roundtrip: mem[8] = x3)
//   x10 = 00000000  (SKIPPED by taken beq; if executed wrongly, x10 = 16)
//   MEM[00] = 00000005  (initial A, not overwritten)
//   MEM[01] = 00000003  (initial B, not overwritten)
//   MEM[02] = 00000008  (sw x3)
//   MEM[03] = 00000002  (sw x4)
//   MEM[04] = 00000001  (sw x5)
//   MEM[05] = 00000007  (sw x6)
//   MEM[06] = 00000001  (sw x7)
//   MEM[07] = 00000000  (sw x8)
//
// -- How to run (ModelSim) -----------------------------------------------------
//   vlog -sv ../sc_alu.sv ../sc_alu_ctrl.sv ../sc_control.sv  \
//             ../sc_sign_ext.sv ../sc_regfile.sv               \
//             ../sc_imem.sv ../sc_dmem.sv                      \
//             ../sc_datapath.sv ../sc_cpu.sv ../sc_cpu_tb.sv
//   vsim work.sc_cpu_tb
//   run -all
// =============================================================================

`timescale 1ns / 1ps

module sc_cpu_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter int CLK_PERIOD   = 20;   // ns - 50 MHz
    parameter int RESET_CYCLES = 4;    // cycles rst_n held low
    parameter int MAX_CYCLES   = 60;   // timeout budget

    // =========================================================================
    // DUT
    // =========================================================================
    logic        clk;
    logic        rst_n;
    logic [31:0] PC;

    sc_cpu dut (
        .clk   (clk),
        .rst_n (rst_n),
        .PC    (PC)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Cycle counter (shared between monitors and main sequence)
    // =========================================================================
    int cycle = 0;

    // =========================================================================
    // Register-write monitor (rising edge - same edge regfile writes)
    // Prints every write to x1..x31 as it happens.
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n &&
            dut.datapath.regfile.RegWrite &&
            dut.datapath.regfile.rd != 5'b0)
        begin
            $display("[cycle %3d] REG  x%-2d <= %08h",
                cycle + 1,
                dut.datapath.regfile.rd,
                dut.datapath.regfile.WriteData);
        end
    end

    // =========================================================================
    // Memory-write monitor (rising edge - same edge sc_dmem writes)
    // Prints every SW as it happens.
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && dut.datapath.dmem.MemWrite) begin
            $display("[cycle %3d] MEM  [word %02h] <= %08h",
                cycle + 1,
                dut.datapath.dmem.addr,
                dut.datapath.dmem.WriteData);
        end
    end

    // =========================================================================
    // Data-memory write shadow
    // Mirrors every SW so dump_state() can report the final memory contents.
    // =========================================================================
    logic [31:0] mem_shadow [0:255];

    initial
        for (int i = 0; i < 256; i++) mem_shadow[i] = '0;

    always @(posedge clk)
        if (rst_n && dut.datapath.dmem.MemWrite)
            mem_shadow[dut.datapath.dmem.addr] <= dut.datapath.dmem.WriteData;

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("sc_cpu_tb.vcd");
        $dumpvars(0, sc_cpu_tb);
    end

    // =========================================================================
    // Main sequence
    // =========================================================================
    integer      fd;
    logic [31:0] prev_pc;

    initial begin
        // --- Reset -----------------------------------------------------------
        rst_n = 0;
        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);         // release between posedges to avoid metastability
        rst_n = 1;

        // --- Open output file ------------------------------------------------
        fd = $fopen("output.txt", "w");
        if (fd == 0) begin
            $display("ERROR: could not open output.txt.");
            $finish;
        end

        // --- Run until halt (PC stable for two consecutive cycles) -----------
        prev_pc = ~32'h0;   // sentinel - never equals a real PC on cycle 1

        while (1) begin
            @(posedge clk);
            cycle++;

            $fdisplay(fd, "CYCLE %3d  PC=%08h", cycle, PC);

            if (PC === prev_pc) begin
                dump_state();
                break;
            end

            prev_pc = PC;

            if (cycle >= MAX_CYCLES) begin
                $display("TIMEOUT: halt not reached after %0d cycles.", MAX_CYCLES);
                $fclose(fd);
                $finish;
            end
        end

        $fclose(fd);

        // --- Verify against golden -------------------------------------------
        verify_output();

        $finish;
    end

    // =========================================================================
    // dump_state
    // Appends registers x0..x10 and data-memory words 00..07 to output.txt.
    // =========================================================================
    task automatic dump_state;
        logic [31:0] v;

        $fdisplay(fd, "---");
        for (int i = 0; i <= 10; i++) begin
            v = (i == 0) ? 32'h0 : dut.datapath.regfile.regs[i];
            $fdisplay(fd, "x%-2d = %08h", i, v);
        end

        $fdisplay(fd, "---");
        for (int w = 0; w <= 7; w++)
            $fdisplay(fd, "MEM[%02d] = %08h", w, mem_shadow[w]);
    endtask

    // =========================================================================
    // verify_output
    // Compares output.txt line-by-line against golden.txt.
    // =========================================================================
    task automatic verify_output;
        integer fg, fo;
        string  lg, lo;
        int     ng, no;
        int     lineno, errs;

        fg = $fopen("golden.txt", "r");
        if (fg == 0) begin
            $display("ERROR: golden.txt not found.");
            return;
        end
        fo = $fopen("output.txt", "r");

        lineno = 0;
        errs   = 0;

        forever begin
            ng = $fgets(lg, fg);
            no = $fgets(lo, fo);

            if (ng == 0 && no == 0) break;

            lineno++;

            if (ng == 0) begin
                $display("  MISMATCH: golden.txt ended before output.txt (line %0d)", lineno);
                errs++;
                break;
            end
            if (no == 0) begin
                $display("  MISMATCH: output.txt ended before golden.txt (line %0d)", lineno);
                errs++;
                break;
            end

            if (lg != lo) begin
                errs++;
                $display("  line %3d MISMATCH", lineno);
                $display("    expected: %s", lg.substr(0, lg.len() - 2));
                $display("    got:      %s", lo.substr(0, lo.len() - 2));
            end
        end

        $fclose(fg);
        $fclose(fo);

        $display("");
        if (errs == 0)
            $display("=== PASS: all %0d lines match ===", lineno);
        else
            $display("=== FAIL: %0d mismatch(es) in %0d lines ===", errs, lineno);
    endtask

endmodule
