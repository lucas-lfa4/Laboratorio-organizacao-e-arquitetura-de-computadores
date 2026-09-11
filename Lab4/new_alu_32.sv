module alu_32 (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [32:0] sum
);
    assign sum = a + b;
endmodule
