# =============================================================================
# pl_top.sdc — TimeQuest Timing Constraints
# Projeto : RV32I Pipelined (5 estágios: IF / ID / EX / MEM / WB)
# Alvo    : DE2-115 — Intel Cyclone IV E (EP4CE115F29C7, speed grade -7)
# Ferram. : Quartus Prime 21.1.1
#
# Topologia de clock
# ──────────────────
#   CLOCK_50 (50 MHz, PIN_Y2)
#     └─→  pll_10mhz  (ALTPLL ÷5, instância 'pll' em pl_top.sv)
#            └─→  clk_cpu (10 MHz, período 100 ns)
#                   └─→  todos os FFs do pipeline + MMIO
#
# Orçamento de timing por estágio (Cyclone IV E -7, estimado)
# ────────────────────────────────────────────────────────────
#   IF  : PC-reg → imem (LUT-RAM async read) → IF/ID                  ≈ 15 ns
#   ID  : imem → decode → regfile (LUT-RAM async) → sign_ext → ID/EX  ≈ 20 ns
#   EX  : fwd-mux (3:1, 32b) → ALU 32b → branch → EX/MEM             ≈ 30 ns ← crítico
#   MEM : EX/MEM → addr-decode (bit[10]) → dmem/MMIO → MEM/WB        ≈ 25 ns
#   WB  : MEM/WB → MemtoReg-mux → regfile write                       ≈  5 ns
#
# Todos os estágios << 100 ns → slack positivo esperado em todas as trilhas.
# Nenhum multi-cycle path é necessário a 10 MHz.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Clock de referência — CLOCK_50 (50 MHz, PIN_Y2)
#    Alimenta apenas o PLL. Nenhum flip-flop do design captura neste domínio.
# -----------------------------------------------------------------------------
create_clock \
    -name     {CLOCK_50} \
    -period   20.000 \
    -waveform {0.000 10.000} \
    [get_ports {CLOCK_50}]

# -----------------------------------------------------------------------------
# 2. Clock gerado — clk_cpu (10 MHz)
#    Saída c0 do ALTPLL; instância 'pll' declarada em pl_top.sv como:
#      pll_10mhz pll (.inclk0(CLOCK_50), .c0(clk), .locked(pll_locked));
#
#    Hierarquia Cyclone IV E padrão para ALTPLL megafunction:
#      pll | altpll_component | auto_generated | pll1 | clk[0]
#
#    -source aponta para inclk[0] (entrada real do núcleo PLL), não para o
#    port CLOCK_50, pois o atraso de roteamento até o pino de entrada do PLL
#    já está modelado pela ferramenta.
# -----------------------------------------------------------------------------
create_generated_clock \
    -name      {clk_cpu} \
    -source    [get_pins  {pll|altpll_component|auto_generated|pll1|inclk[0]}] \
    -divide_by 5 \
    [get_pins  {pll|altpll_component|auto_generated|pll1|clk[0]}]

# -----------------------------------------------------------------------------
# 3. Incerteza automática de clock
#    derive_clock_uncertainty consulta as specs do PLL Cyclone IV E e calcula
#    jitter + skew para cada aresta. Elimina a necessidade de margens manuais.
# -----------------------------------------------------------------------------
derive_clock_uncertainty

# =============================================================================
# FALSE PATHS — Entradas assíncronas ou de baixíssima frequência
# =============================================================================

# -----------------------------------------------------------------------------
# 4. KEY[3:0] — botões push-button
#    KEY[0] : reset ativo-baixo. Em pl_top: rst_n = pll_locked & KEY[0].
#             O sinal rst_n é tratado como reset assíncrono em todos os FFs
#             do pipeline (negedge rst_n na lista de sensibilidade). Portanto
#             não há requisito de setup/hold em relação a clk_cpu.
#    KEY[3:1]: lidos pelo MMIO (0x404). Mudam na escala de centenas de ms.
#
#    NOTA: o SDC anterior usava set_false_path -from [get_ports {rst_n}],
#    que estava errado — rst_n é sinal interno, não porta do top-level.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {KEY[*]}]

# -----------------------------------------------------------------------------
# 5. SW[17:0] — chaves deslizantes
#    Lidas combinacionalmente pelo MMIO (0x400 → ReadData). Nenhuma relação
#    de fase com clk_cpu; mudança exclusivamente por ação manual (escala de ms).
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {SW[*]}]

# -----------------------------------------------------------------------------
# 6. UART_RXD — recepção serial (9600 baud, 104 µs/bit)
#    Amostrado por pl_uart via detecção de start-bit e amostragem no meio
#    do bit. A janela de amostragem (≥ 52 µs) é ≈ 520× maior que o período
#    de clk_cpu — nenhuma relação de fase válida com o clock do sistema.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {UART_RXD}]

# -----------------------------------------------------------------------------
# 7. PLL locked — sinal de status do ALTPLL
#    Asserta após a estabilização do PLL no power-on. Usado apenas na lógica
#    combinacional de rst_n (pl_top). Não há relação de timing com clk_cpu.
#
#    Se o Timing Analyzer reportar "Node not found" aqui, verifique o caminho
#    exato no Netlist Viewer — em algumas versões do Quartus o 'locked' aparece
#    um nível acima: pll|altpll_component|auto_generated|locked
# -----------------------------------------------------------------------------
set_false_path \
    -from [get_pins {pll|altpll_component|auto_generated|pll1|locked}]

# =============================================================================
# FALSE PATHS — Saídas sem requisito externo de timing
# =============================================================================

# -----------------------------------------------------------------------------
# 8. LEDR[17:0] e LEDG[8:0] — LEDs da placa
#    Registradores de saída clocked em clk_cpu (pl_mmio). Os LEDs não possuem
#    receptor com requisito de setup/hold; o único critério é nível lógico DC.
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]

# -----------------------------------------------------------------------------
# 9. UART_TXD — transmissão serial (9600 baud, 104 µs/bit)
#    Gerado por pl_uart clocked em clk_cpu. O receptor UART amostra no centro
#    do bit (≈ 52 µs após a transição de start). A variação de saída de 1 ciclo
#    (100 ns) representa < 0,2 % do período de bit — sem impacto na recepção.
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {UART_TXD}]

# =============================================================================
# OBSERVAÇÕES SOBRE CAMINHOS INTERNOS
# =============================================================================
# Todos os caminhos FF→FF do pipeline são cobertos automaticamente pelo clock
# clk_cpu (100 ns). Não são necessários multi-cycle paths.
#
# cycle_count (pl_mmio, 0x414):
#   Registrado em posedge clk_cpu; lido combinacionalmente no mux ReadData do
#   MMIO. Caminho FF→FF de 1 ciclo normal — nenhuma constraint adicional.
#
# Forwarding (pl_forward / pl_datapath):
#   Lógica puramente combinacional entre registradores de pipeline (EX/MEM e
#   MEM/WB → muxes de forwarding EX). Contido dentro do estágio EX (≈ 30 ns).
#
# Hazard (pl_hazard):
#   Comparadores de 5 bits entre campos de instrução → sinal stall. Atraso
#   típico < 5 ns; coberto com ampla folga pelo período de 100 ns.
