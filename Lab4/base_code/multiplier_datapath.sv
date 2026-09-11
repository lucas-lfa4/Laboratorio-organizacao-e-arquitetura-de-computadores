// multiplier_datapath.sv
// Datapath da unidade de multiplicacao (32 bits → produto de 64 bits)
// Baseado na Figura 3.3 - Patterson & Hennessy, Computer Organization and Design
//
// Registradores conforme a figura:
//   multiplicand_reg [63:0] — comeca com multiplicando nos bits [31:0], zeros nos [63:32]
//                             shift left a cada iteracao
//   multiplier_reg   [31:0] — contem o multiplicador
//                             shift right a cada iteracao
//   product_reg      [63:0] — inicializado em 0; acumula o resultado
//
// Sinais de controle vindos da FSM:
//   load       — carrega os operandos iniciais nos registradores
//   product_wr — habilita a escrita do resultado da ALU em product_reg
//   shift_en   — desloca multiplicand_reg a esquerda e multiplier_reg a direita

module multiplier_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Entradas de dados
    input  logic [31:0] multiplicand_in,
    input  logic [31:0] multiplier_in,

    // Sinais de controle vindos da FSM
    input  logic        load,        // Carrega operandos iniciais
    input  logic        product_wr,  // Escreve soma da ALU em product_reg
    input  logic        shift_en,    // Shift left em multiplicand, shift right em multiplier

    // Saidas de status para a FSM
    output logic        multiplier_lsb, // Bit 0 do registrador multiplier (testa Multiplier0)

    // Saída do resultado
    output logic [63:0] product
);

    // -----------------------------------------------------------------------
    // Registradores internos (Figura 3.4)
    // -----------------------------------------------------------------------
    logic [63:0] multiplicand_reg;
    logic [31:0] multiplier_reg;
    logic [63:0] product_reg;

    // -----------------------------------------------------------------------
    // ALU (Figura 3.3 — "64-bit ALU")
    // -----------------------------------------------------------------------
    logic [63:0] alu_sum;

    alu_64 alu (
        .a   (product_reg),
        .b   (multiplicand_reg),
        .sum (alu_sum)
    );

    // -----------------------------------------------------------------------
    // Saídas combinacionais
    // -----------------------------------------------------------------------
    assign multiplier_lsb = multiplier_reg[0];
    assign product        = product_reg;

    // -----------------------------------------------------------------------
    // Atualizacao dos registradores
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            multiplicand_reg <= '0;
            multiplier_reg   <= '0;
            product_reg      <= '0;

        end else if (load) begin
            // Inicializacao conforme Figura 3.4:
            // Multiplicand -> bits [31:0], bits [63:32] = 0
            multiplicand_reg <= {32'b0, multiplicand_in};
            multiplier_reg   <= multiplier_in;
            product_reg      <= '0;

        end else begin
            // Passo 1 (Figura 3.4): Product = Product + Multiplicand (se habilitado)
            if (product_wr)
                product_reg <= alu_sum;

            // Passos 2 e 3 (Figura 3.4): deslocamentos
            if (shift_en) begin
                multiplicand_reg <= {multiplicand_reg[62:0], 1'b0}; // shift left
                multiplier_reg   <= {1'b0, multiplier_reg[31:1]};   // shift right (lógico)
            end
        end
    end

endmodule
