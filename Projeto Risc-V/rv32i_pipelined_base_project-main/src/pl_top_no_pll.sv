// =============================================================================
// pl_top_no_pll.sv
// Top-level alternativo — RV32I pipelined sem PLL (DE2-115)
//
// Variante de síntese/teste onde CLOCK_50 (50 MHz) alimenta a CPU diretamente,
// sem o bloco pll_10mhz. Use este arquivo para:
//   - Testes de síntese independentes do IP de PLL
//   - Análise de timing com o SDC pl_top_no_pll.sdc
//
// Diferenças em relação a pl_top.sv:
//   - Sem instância pll_10mhz
//   - clk = CLOCK_50 (50 MHz)
//   - rst_n = KEY[0] diretamente (sem aguardar pll_locked)
//   - CLK_FREQ_HZ = 50_000_000 propagado para pl_mmio via pl_cpu
//
// ATENÇÃO — UART a 50 MHz:
//   pl_mmio instancia pl_uart com CLK_HZ = 10_000_000 (hardcoded).
//   A 50 MHz o divisor de baud estará errado por fator 5, portanto a
//   comunicação serial NÃO funcionará corretamente nesta variante.
//   Para corrigir, altere pl_mmio.sv: .CLK_HZ(50_000_000)
//
// Pinagem (DE2-115) — idêntica a pl_top.sv:
//   CLOCK_50  : clock de 50 MHz da placa
//   KEY[0]    : reset manual ativo-baixo (pressionado = reset)
//   KEY[3:1]  : botões lidos via MMIO 0x404
//   SW[17:0]  : chaves deslizantes — MMIO 0x400
//   LEDR[17:0]: LEDs vermelhos     — MMIO 0x408
//   LEDG[8:0] : LEDs verdes        — MMIO 0x40C
//   UART_TXD  : transmissão RS-232 (baud incorreto sem ajuste de CLK_HZ)
//   UART_RXD  : recepção  RS-232
// =============================================================================

`timescale 1ns / 1ps

module pl_top_no_pll (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,          // KEY[0] = reset ativo-baixo
    input  logic [17:0] SW,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD
);

    // rst_n liberado imediatamente ao soltar KEY[0].
    // Sem PLL não há sinal locked para aguardar.
    logic rst_n;
    assign rst_n = KEY[0];

    // -------------------------------------------------------------------------
    // CPU pipelined — clock direto de 50 MHz
    // -------------------------------------------------------------------------
    pl_cpu cpu (
        .clk          (CLOCK_50),
        .rst_n        (rst_n),
        .PC           (),
        .SW           (SW),
        .KEY_IO       (KEY),
        .LEDR         (LEDR),
        .LEDG         (LEDG),
        .UART_TXD     (UART_TXD),
        .UART_RXD     (UART_RXD),
        .wb_reg_write (),
        .wb_reg_dst   (),
        .wb_reg_data  (),
        .mem_wr_en    (),
        .mem_wr_addr  (),
        .mem_wr_data  ()
    );

endmodule
