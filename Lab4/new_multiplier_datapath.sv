module multiplier_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Entradas de dados
    input  logic [31:0] multiplicand_in,
    input  logic [31:0] multiplier_in,

    // Sinais de controle vindos da FSM
    input  logic        load,        
    input  logic        product_wr,  
    input  logic        shift_en,    

    // Saidas de status para a FSM
    output logic        multiplier_lsb, 

    // Saída do resultado
    output logic [63:0] product
);

    logic [31:0] multiplicand_reg;
    logic [64:0] product_reg; // 64 bits + 1 bit de Carry out

    logic [32:0] alu_sum; // 33 bits para capturar o carry

    // ALU de 32 bits conectada a metade superior do produto
    alu_32 alu (
        .a   (product_reg[63:32]),
        .b   (multiplicand_reg),
        .sum (alu_sum)
    );

    // O LSB a ser testado agora é o bit 0 do proprio registrador de produto
    assign multiplier_lsb = product_reg[0];
    
    // A saída final ignora o 65º bit (Carry)
    assign product = product_reg[63:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            multiplicand_reg <= '0;
            product_reg      <= '0;
        end else if (load) begin
            // Inicialização: Multiplicando em 32 bits; Multiplicador na base do Produto
            multiplicand_reg <= multiplicand_in;
            product_reg      <= {33'b0, multiplier_in};
        end else begin
            // Se habilitado, guarda a soma de 32 bits + 1 de carry na metade superior
            if (product_wr) begin
                product_reg[64:32] <= alu_sum;
            end
            
            // Shift right em todos os 65 bits simultaneamente
            if (shift_en) begin
                product_reg <= {1'b0, product_reg[64:1]}; 
            end
        end
    end

endmodule
