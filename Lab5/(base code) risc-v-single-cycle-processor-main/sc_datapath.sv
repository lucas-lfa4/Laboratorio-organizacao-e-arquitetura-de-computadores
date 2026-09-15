// =============================================================================
// sc_datapath.sv
// Datapath - single-cycle RISC-V (Figure 4.17 - Patterson & Hennessy)
//
// Instantiates and connects all datapath components:
//
//   sc_imem    : instruction memory (256 words, program.hex)
//   sc_regfile : 32 x 32-bit register file
//   sc_sign_ext: sign extender (I / S / B immediate formats)
//   sc_alu_ctrl: ALU control (ALUOp + Funct3/Funct7 -> Operation)
//   sc_alu     : 32-bit ALU (add, sub, or, and, slt)
//   sc_dmem    : data memory (256 words, data.hex)
//
// Muxes implemented as combinatorial assigns:
//   ALU Source  : ALUSrc  -> selects register rs2 or sign-extended immediate
//   Write-back  : MemtoReg-> selects ALU result or data memory output
//   PC source   : PCSrc   -> selects PC+4 or branch target
//
// PC computation:
//   pc_plus4   = pc_reg + 4          (sequential fetch)
//   pc_branch  = pc_reg + ImmExt     (branch target; B-type imm includes the x2 shift)
//   PCSrc      = Branch AND Zero     (take branch only on BEQ with equal operands)
//   pc_next    = PCSrc ? pc_branch : pc_plus4
// =============================================================================

`timescale 1ns / 1ps

module sc_datapath (
    input  logic        clk,
    input  logic        rst_n,    // Active-low asynchronous reset -> PC = 0
    // Control signals (from sc_control)
    input  logic        ALUSrc,
    input  logic        MemtoReg,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic [1:0]  ALUOp,
    // Opcode fed back to the control unit
    output logic [6:0]  Opcode,
    // Observability: current PC (useful for SignalTap / testbench)
    output logic [31:0] PC
);

    // -------------------------------------------------------------------------
    // Internal wires
    // -------------------------------------------------------------------------
    logic [31:0] pc_reg;        // Current program counter
    logic [31:0] pc_plus4;      // pc + 4
    logic [31:0] pc_branch;     // pc + ImmExt  (branch target)
    logic [31:0] pc_next;       // Selected next PC
    logic        pc_src;        // 1 = take branch

    logic [31:0] instr;         // Instruction word from imem

    // Instruction fields (combinatorial decode)
    logic [4:0]  rs1, rs2, rd;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    logic [31:0] read_data1;    // Register file rs1 output
    logic [31:0] read_data2;    // Register file rs2 output
    logic [31:0] imm_ext;       // Sign-extended immediate
    logic [31:0] alu_srcb;      // ALU second operand (mux output)
    logic [3:0]  alu_op;        // ALU operation code
    logic [31:0] alu_result;    // ALU computation result
    logic        zero;          // ALU zero flag (1 when alu_result == 0)
    logic [31:0] mem_read_data; // Data memory read output
    logic [31:0] write_back;    // Value written into the register file

    // -------------------------------------------------------------------------
    // PC Register (asynchronous reset to address 0)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_reg <= 32'b0;
        else        pc_reg <= pc_next;
    end

    assign PC = pc_reg;

    // -------------------------------------------------------------------------
    // Instruction Memory
    // Word address = pc[9:2]; async read - addr drives rom[] combinatorially
    // -------------------------------------------------------------------------
    sc_imem imem (
        .addr  (pc_reg[9:2]),
        .instr (instr)
    );

    // -------------------------------------------------------------------------
    // Instruction Decode
    // RISC-V 32-bit instruction layout:
    //   [31:25] funct7  [24:20] rs2  [19:15] rs1
    //   [14:12] funct3  [11:7]  rd   [6:0]   opcode
    // -------------------------------------------------------------------------
    assign Opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // -------------------------------------------------------------------------
    // Register File
    // -------------------------------------------------------------------------
    sc_regfile regfile (
        .clk       (clk),
        .RegWrite  (RegWrite),
        .rs1       (rs1),
        .rs2       (rs2),
        .rd        (rd),
        .WriteData (write_back),
        .ReadData1 (read_data1),
        .ReadData2 (read_data2)
    );

    // -------------------------------------------------------------------------
    // Sign Extender
    // -------------------------------------------------------------------------
    sc_sign_ext sign_ext (
        .Instr  (instr),
        .ImmExt (imm_ext)
    );

    // -------------------------------------------------------------------------
    // ALU Source Mux
    //   ALUSrc = 0 -> use rs2 register value (R-type, BEQ)
    //   ALUSrc = 1 -> use sign-extended immediate (LW, SW)
    // -------------------------------------------------------------------------
    assign alu_srcb = ALUSrc ? imm_ext : read_data2;

    // -------------------------------------------------------------------------
    // ALU Control
    // -------------------------------------------------------------------------
    sc_alu_ctrl alu_ctrl (
        .ALUOp    (ALUOp),
        .Funct7   (funct7),
        .Funct3   (funct3),
        .Operation(alu_op)
    );

    // -------------------------------------------------------------------------
    // ALU
    // -------------------------------------------------------------------------
    sc_alu alu (
        .SrcA     (read_data1),
        .SrcB     (alu_srcb),
        .Operation(alu_op),
        .ALUResult(alu_result),
        .Zero     (zero)
    );

    // -------------------------------------------------------------------------
    // Data Memory
    // Word address = alu_result[9:2]; async read - addr drives ram[] combinatorially
    // -------------------------------------------------------------------------
    sc_dmem dmem (
        .clk       (clk),
        .MemWrite  (MemWrite),
        .addr      (alu_result[9:2]),
        .WriteData (read_data2),
        .ReadData  (mem_read_data)
    );

    // -------------------------------------------------------------------------
    // Write-Back Mux
    //   MemtoReg = 0 -> write ALU result  (R-type)
    //   MemtoReg = 1 -> write memory data (LW)
    // -------------------------------------------------------------------------
    assign write_back = MemtoReg ? mem_read_data : alu_result;

    // -------------------------------------------------------------------------
    // Branch Logic and Next-PC Selection
    //   BEQ is taken when Branch=1 AND Zero=1 (rs1 == rs2 after SUB)
    //   Branch target = pc_reg + ImmExt  (B-type immediate, bit 0 = 0)
    // -------------------------------------------------------------------------
    assign pc_plus4  = pc_reg + 32'd4;
    assign pc_branch = pc_reg + imm_ext;
    assign pc_src    = Branch & zero;
    assign pc_next   = pc_src ? pc_branch : pc_plus4;

endmodule
