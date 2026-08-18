`timescale 1ns/1ps

module tb_mux4x1;
	logic [31:0] a, b, c, d;
	logic [1:0] sel;

	logic [31:0] f;

	mux4x1 dut (.f(f), .a(a), .b(b), .c(c), .d(d), .sel(sel));

	
	initial begin
		$monitor($time,
		"a = %h | b = %h | c = %h | d = %h | sel = %b | Saida = %h", a, b, c, d, sel, f);
		a = 32'hAAAA_AAAA;
		b = 32'hBBBB_BBBB;
		c = 32'hCCCC_CCCC;
		d = 32'hDDDD_DDDD;
	
		for(int i = 0; i < 4; i++) begin
			sel = i;
			#10;
		end
	
		#10 $finish;
	end

endmodule: tb_mux4x1