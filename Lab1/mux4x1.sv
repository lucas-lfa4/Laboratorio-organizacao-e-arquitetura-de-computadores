module mux4x1
	(output logic [31:0] f,
	 input logic [31:0] a, b, c, d,
	 input logic [1:0] sel);
	
	always_comb begin
		case(sel)
			2'b00: f = a;
			2'b01: f = b;
			2'b10: f = c;
			2'b11: f = d;
			default: f = '0;
		endcase
	end

endmodule: mux4x1