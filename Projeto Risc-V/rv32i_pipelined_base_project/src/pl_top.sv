// =============================================================================
// pl_top.sv
// Top-level -- RV32I pipelined (DE2-115)
//
// Instancia a PLL (50 MHz -> 10 MHz) e o processador (pl_cpu).
// O reset do CPU e mantido enquanto a PLL nao estiver travada, garantindo
// que o pipeline so inicie com clock estavel.
//
// Pinagem (DE2-115):
//   CLOCK_50  : clock de 50 MHz da placa
//   KEY[0]    : reset manual ativo-baixo (pressionado = reset)
//   KEY[3:1]  : lidos como entrada no banco de registradores MMIO
//   SW[17:0]  : chaves deslizantes (leitura via MMIO 0x400)
//   LEDR[17:0]: LEDs vermelhos (escrita via MMIO 0x408)
//   LEDG[8:0] : LEDs verdes   (escrita via MMIO 0x40C)
//   UART_TXD  : transmissao RS-232 (9600 8N1)
//   UART_RXD  : recepcao  RS-232
// =============================================================================

`timescale 1ns / 1ps

module pl_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,          // KEY[0] = reset (ativo-baixo)
    input  logic [17:0] SW,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD
);

    logic clk;          // 10 MHz (saida da PLL)
    logic pll_locked;   // 1 quando a PLL esta estabilizada
    logic rst_n;        // reset ativo-baixo sincronizado com PLL

    // -------------------------------------------------------------------------
    // PLL: 50 MHz -> 10 MHz
    // -------------------------------------------------------------------------
    pll_10mhz pll (
        .inclk0 (CLOCK_50),
        .c0     (clk),
        .locked (pll_locked)
    );

    // O CPU so sai do reset quando a PLL esta travada e KEY[0] nao e pressionado
    assign rst_n = pll_locked & KEY[0];


    // -------------------------------------------------------------------------
    // CPU pipelined
    // -------------------------------------------------------------------------
    pl_cpu cpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .PC           (),           // nao conectado no top-level da placa
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
