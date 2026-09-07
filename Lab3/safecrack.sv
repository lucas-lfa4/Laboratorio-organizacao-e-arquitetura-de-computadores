// =============================================================================
// safecrack.sv
// Implementacao do Cofre Eletronico baseada no modelo button_fsm.sv
// =============================================================================

module safecrack (
    input  logic       clk,    // Clock de 50 MHz
    input  logic       rst_n,  // Reset assincrono, ativo baixo (KEY[0])
    input  logic [3:0] btn,    // Botoes: [Vermelho, Verde, Amarelo, Azul] (KEY[4:1], ativos baixos)
    output logic       unlocked// LED indicador de cofre aberto (ex: LEDR[0])
);

// -----------------------------------------------------------------------------
// [1] DEFINICAO DOS ESTADOS E CONSTANTES
// -----------------------------------------------------------------------------
typedef enum logic [4:0] {
    S_INIT     = 5'b00001, // Estado inicial
    S_B        = 5'b00010, // Azul pressionado
    S_BY       = 5'b00100, // Azul -> Amarelo
    S_BYY      = 5'b01000, // Azul -> Amarelo -> Amarelo
    S_UNLOCKED = 5'b10000  // Cofre Aberto
} state_t;

state_t state, next_state;

// Mapeamento dos botoes em logica positiva (mascaras de bits)
localparam BLUE   = 4'b0001;
localparam YELLOW = 4'b0010;
localparam GREEN  = 4'b0100;
localparam RED    = 4'b1000;

// -----------------------------------------------------------------------------
// [2] DETECCAO DE BORDA DE SUBIDA PARA 4 BOTOES
// -----------------------------------------------------------------------------
logic [3:0] btn_active;  
logic [3:0] btn_prev;    
logic [3:0] btn_rise;    
logic       any_btn_rise; // Flag: foi detectada borda em qualquer botao?

// Inverte a polaridade (botoes ativos baixos na placa)
assign btn_active   = ~btn;
// Detecta borda de subida individualmente para os 4 botoes
assign btn_rise     = btn_active & ~btn_prev;
// Verifica se ALGUM botao gerou borda de subida (operador OR de reducao)
assign any_btn_rise = |btn_rise; 

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) btn_prev <= 4'b0000;
    else        btn_prev <= btn_active;
end

// -----------------------------------------------------------------------------
// [3] PROCESSO SEQUENCIAL -- Registro de estado
// -----------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_INIT;
    else        state <= next_state;
end

// -----------------------------------------------------------------------------
// [4] PROCESSO COMBINACIONAL -- Logica de proximo estado
// -----------------------------------------------------------------------------
always_comb begin
    next_state = state;  // Default: mantem o estado

    unique case (state)
        S_INIT: begin
            if (any_btn_rise) 
                next_state = (btn_rise == BLUE) ? S_B : S_INIT;
        end
        
        S_B: begin
            if (any_btn_rise) 
                next_state = (btn_rise == YELLOW) ? S_BY : S_INIT;
        end
        
        S_BY: begin
            if (any_btn_rise) 
                next_state = (btn_rise == YELLOW) ? S_BYY : S_INIT;
        end
        
        S_BYY: begin
            if (any_btn_rise) 
                next_state = (btn_rise == RED) ? S_UNLOCKED : S_INIT;
        end
        
        S_UNLOCKED: begin
            next_state = S_UNLOCKED; // Trava aqui ate o reset_n ser acionado
        end
        
        default: next_state = S_INIT;
    endcase
end

// -----------------------------------------------------------------------------
// [5] SAIDA -- Logica de Moore
// -----------------------------------------------------------------------------
assign unlocked = (state == S_UNLOCKED);

endmodule
