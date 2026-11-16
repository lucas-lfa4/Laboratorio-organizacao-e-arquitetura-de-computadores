# =============================================================================
# pl_top_no_pll.sdc — TimeQuest Timing Constraints (variante sem PLL)
# Projeto : RV32I Pipelined (5 estágios: IF / ID / EX / MEM / WB)
# Alvo    : DE2-115 — Intel Cyclone IV E (EP4CE115F29C7, speed grade -7)
#
# Variante de síntese onde CLOCK_50 (50 MHz) alimenta a CPU diretamente,
# sem passar pelo pll_10mhz. Use este arquivo para testes de síntese e
# análise de timing sem depender do IP de PLL.
#
# Período de 20 ns — orçamento por estágio (Cyclone IV E -7, estimado)
# ──────────────────────────────────────────────────────────────────────
#   IF  : PC-reg → imem (LUT-RAM async) → IF/ID                  ≈ 15 ns
#   ID  : imem → decode → regfile (LUT-RAM async) → ID/EX        ≈ 20 ns  ← crítico
#   EX  : fwd-mux (3:1, 32b) → ALU 32b → EX/MEM                 ≈ 30 ns  ← viola 20 ns
#   MEM : EX/MEM → addr-decode → dmem/MMIO → MEM/WB              ≈ 25 ns  ← viola 20 ns
#   WB  : MEM/WB → MemtoReg-mux → regfile write                  ≈  5 ns
#
# A 50 MHz os estágios EX e MEM provavelmente apresentarão slack negativo.
# O objetivo deste arquivo é identificar esses caminhos críticos via
# timing report, não garantir closure a 50 MHz.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Clock único — CLOCK_50 (50 MHz, PIN_Y2)
#    Alimenta diretamente todos os flip-flops do pipeline e do MMIO.
#    Nesta variante não há PLL; o top-level deve conectar CLOCK_50 → clk_cpu.
# -----------------------------------------------------------------------------
create_clock \
    -name     {CLOCK_50} \
    -period   20.000 \
    -waveform {0.000 10.000} \
    [get_ports {CLOCK_50}]

# -----------------------------------------------------------------------------
# 2. Incerteza de clock
#    Sem PLL, a incerteza é dominada pelo jitter da fonte de clock da placa
#    e pelo skew da rede de distribuição global do Cyclone IV.
#    derive_clock_uncertainty aplica os valores conservadores padrão da Intel.
# -----------------------------------------------------------------------------
derive_clock_uncertainty

# =============================================================================
# FALSE PATHS — Entradas assíncronas / de baixa frequência
# =============================================================================

# -----------------------------------------------------------------------------
# 3. KEY[3:0] — botões push-button
#    KEY[0] : reset ativo-baixo. Sem PLL, rst_n pode ser simplificado para
#             apenas KEY[0] no top-level de teste.
#    KEY[3:1]: lidos pelo MMIO (0x404); escala de tempo humana (ms).
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {KEY[*]}]

# -----------------------------------------------------------------------------
# 4. SW[17:0] — chaves deslizantes
#    Lidas pelo MMIO (0x400); mudança exclusivamente manual (escala de ms).
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {SW[*]}]

# -----------------------------------------------------------------------------
# 5. UART_RXD — recepção serial (9600 baud, 104 µs/bit)
#    Sem relação de fase com CLOCK_50.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {UART_RXD}]

# =============================================================================
# FALSE PATHS — Saídas sem requisito externo de timing
# =============================================================================

# -----------------------------------------------------------------------------
# 6. LEDR[17:0] e LEDG[8:0] — LEDs da placa
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]

# -----------------------------------------------------------------------------
# 7. UART_TXD — transmissão serial (9600 baud, 104 µs/bit)
#    Janela de amostragem do receptor (≥ 52 µs) >> 1 ciclo de 20 ns.
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {UART_TXD}]
