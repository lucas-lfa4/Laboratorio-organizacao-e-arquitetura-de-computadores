// multiplier_top.sv
// Modulo top-level da unidade de multiplicação de 32 bits
// Baseado nas Figuras 3.3 e 3.4 - Patterson & Hennessy, Computer Organization and Design
//
// Conecta o datapath (multiplier_datapath) e a FSM de controle (multiplier_control).
//
// Uso:
//   1. Apresentar os operandos em 'multiplicand_in' e 'multiplier_in'
//   2. Setar o 'start' por pelo menos 1 ciclo de clock
//   3. Aguardar 'done' ser setado (apos ~66 ciclos: 1 LOAD + 32×2 iteracoes)
//   4. Ler o produto de 64 bits em 'product'
//   5. Resetar 'start' para permitir nova operacao

module multiplier_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,           // Inicia a multiplicacao
    input  logic [31:0] multiplicand_in, // Operando A (32 bits)
    input  logic [31:0] multiplier_in,   // Operando B (32 bits)

    output logic [63:0] product,         // Resultado A × B (64 bits)
    output logic        done             // Indica termino da operacao
);

    // -----------------------------------------------------------------------
    // Sinais internos entre controle e datapath
    // -----------------------------------------------------------------------
    logic load;
    logic product_wr;
    logic shift_en;
    logic multiplier_lsb;

    // -----------------------------------------------------------------------
    // Instancia do datapath (Figura 3.3)
    // -----------------------------------------------------------------------
    multiplier_datapath datapath (
        .clk             (clk),
        .rst_n           (rst_n),
        .multiplicand_in (multiplicand_in),
        .multiplier_in   (multiplier_in),
        .load            (load),
        .product_wr      (product_wr),
        .shift_en        (shift_en),
        .multiplier_lsb  (multiplier_lsb),
        .product         (product)
    );

    // -----------------------------------------------------------------------
    // Instancia da FSM de controle (Figura 3.4)
    // -----------------------------------------------------------------------
    multiplier_control control (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .done            (done),
        .multiplier_lsb  (multiplier_lsb),
        .load            (load),
        .product_wr      (product_wr),
        .shift_en        (shift_en)
    );

endmodule
