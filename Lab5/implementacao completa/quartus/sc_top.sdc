# =============================================================================
# sc_top.sdc  —  TimeQuest timing constraints
# Target : DE2-115  (Intel Cyclone IV E)  /  50 MHz
#
# Caminho crítico
# ---------------
# As memórias (sc_imem / sc_dmem) usam MLAB com leitura assíncrona
# (address_reg_b = "UNREGISTERED").  Não há mais o truque do ~clk.
#
# Todo o caminho combinacional corre no período completo de 20 ns:
#   posedge → PC → imem(async) → decode → regfile(async) → ALU →
#   dmem(async) → mux → write_back → setup antes do próximo posedge
#
# Só existe um domínio de clock: clk (posedge).
#
# Otimizações se o timing não fechar
# ------------------------------------
#   a) Assignments → Settings → Compiler Settings
#         Optimization Mode: "Performance (High effort)"
#         Physical Synthesis: habilitar todas as opções
#         Gate-Level Register Retiming: ON
#   b) Tente diferentes seeds: Assignments → Settings → Fitter → Seed (1–10)
#   c) Se ainda falhar, reduza para 40 MHz (altere -period para 25.000)
# =============================================================================

# -----------------------------------------------------------------------------
# 1.  Clock principal — CLOCK_50 (pino P11 no DE2-115)
# -----------------------------------------------------------------------------
create_clock \
    -name    {clk} \
    -period  20.000 \
    -waveform {0.000 10.000} \
    [get_ports {clk}]

# -----------------------------------------------------------------------------
# 2.  Incerteza de clock (jitter + skew)
#     Sem clocks derivados: não é necessário derive_clocks.
# -----------------------------------------------------------------------------
derive_clock_uncertainty

# -----------------------------------------------------------------------------
# 3.  Reset assíncrono  (KEY[0] → rst_n, ativo-baixo)
#
#     O botão é mecânico (bounce) e não tem requisito de timing.
#     Elimina verificações de recovery/removal no FF do PC.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports {rst_n}]

# -----------------------------------------------------------------------------
# 4.  Saída PC  (LEDs / SignalTap — sem requisito externo de timing)
# -----------------------------------------------------------------------------
set_false_path -to [get_ports {PC[*]}]

