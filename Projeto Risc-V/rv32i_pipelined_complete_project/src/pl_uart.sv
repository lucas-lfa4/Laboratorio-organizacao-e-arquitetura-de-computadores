// =============================================================================
// pl_uart.sv
// Simple RS-232 UART -- 8N1 (8 data bits, no parity, 1 stop bit)
//
// Parameters:
//   CLK_HZ : CPU clock frequency in Hz (default 50 MHz)
//   BAUD   : desired baud rate         (default 9600)
//
// TX interface:
//   tx_write  -- 1-cycle strobe: load tx_data and begin transmission.
//               Writes asserted while tx_busy is high are ignored.
//   tx_data   -- byte to transmit (7:0)
//   tx_busy   -- high while the shift register is active
//   TXD       -- RS-232 transmit pin (idle HIGH)
//
// RX interface:
//   rx_data   -- last received byte (held until next reception)
//   rx_valid  -- pulses HIGH for exactly one clock cycle when rx_data
//               is updated (start-bit validated, 8 data bits sampled,
//               stop bit confirmed HIGH)
//   RXD       -- RS-232 receive pin (idle HIGH), double-flopped internally
//
// Baud-rate error at 9600 baud / 50 MHz:
//   CLKS_PER_BIT = 50_000_000 / 9_600 = 5208
//   Actual baud  = 50_000_000 / 5208  = 9601  (error < 0.1 % -- well within RS-232 spec)
// =============================================================================

`timescale 1ns / 1ps

module pl_uart #(
    parameter int CLK_HZ = 50_000_000,
    parameter int BAUD   =      9_600
) (
    input  logic       clk,
    input  logic       rst_n,     // active-low asynchronous reset

    // CPU-side interface
    input  logic       tx_write,  // 1-cycle write strobe from MMIO
    input  logic [7:0] tx_data,   // byte to transmit
    output logic       tx_busy,   // 1 while transmitting
    output logic [7:0] rx_data,   // last received byte
    output logic       rx_valid,  // 1-cycle pulse on new byte

    // Physical RS-232 pins (TTL level -- connect to FPGA I/O, MAX232 handles V-level)
    output logic       TXD,       // to RS-232 connector (via MAX232)
    input  logic       RXD        // from RS-232 connector (via MAX232)
);

    // -------------------------------------------------------------------------
    // Derived parameter: clock ticks per bit period
    // -------------------------------------------------------------------------
    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;   // 1041 @ 9600 / 10 MHz

    // =========================================================================
    // Transmitter
    // =========================================================================
    typedef enum logic [1:0] {
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3
    } tx_state_t;

    tx_state_t   tx_state;
    logic [15:0] tx_cnt;       // bit-period counter (needs >= log2(CLKS_PER_BIT) bits)
    logic [2:0]  tx_bit_idx;   // current data bit index (0..7)
    logic [7:0]  tx_sr;        // transmit shift register

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            TXD        <= 1'b1;     // idle line = HIGH
            tx_busy    <= 1'b0;
            tx_cnt     <= '0;
            tx_bit_idx <= '0;
            tx_sr      <= '0;
        end else begin
            case (tx_state)

                // ---- IDLE: wait for write strobe ----------------------------
                TX_IDLE: begin
                    TXD     <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_write) begin
                        tx_sr      <= tx_data;
                        tx_busy    <= 1'b1;
                        tx_cnt     <= '0;
                        tx_state   <= TX_START;
                    end
                end

                // ---- START bit (LOW) ----------------------------------------
                TX_START: begin
                    TXD <= 1'b0;
                    if (tx_cnt == CLKS_PER_BIT - 1) begin
                        tx_cnt     <= '0;
                        tx_bit_idx <= '0;
                        tx_state   <= TX_DATA;
                    end else begin
                        tx_cnt <= tx_cnt + 1;
                    end
                end

                // ---- 8 DATA bits (LSB first) --------------------------------
                TX_DATA: begin
                    TXD <= tx_sr[0];
                    if (tx_cnt == CLKS_PER_BIT - 1) begin
                        tx_cnt <= '0;
                        tx_sr  <= {1'b0, tx_sr[7:1]};   // shift right
                        if (tx_bit_idx == 3'd7) begin
                            tx_bit_idx <= '0;
                            tx_state   <= TX_STOP;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1;
                        end
                    end else begin
                        tx_cnt <= tx_cnt + 1;
                    end
                end

                // ---- STOP bit (HIGH) ----------------------------------------
                TX_STOP: begin
                    TXD <= 1'b1;
                    if (tx_cnt == CLKS_PER_BIT - 1) begin
                        tx_cnt   <= '0;
                        tx_busy  <= 1'b0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_cnt <= tx_cnt + 1;
                    end
                end

            endcase
        end
    end

    // =========================================================================
    // Receiver
    // =========================================================================

    // --- Two-stage synchronizer: bring RXD into the clk domain --------------
    logic rxd_s, rxd_q;    // rxd_q is the stable, synchronized value

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_s <= 1'b1;
            rxd_q <= 1'b1;
        end else begin
            rxd_s <= RXD;
            rxd_q <= rxd_s;
        end
    end

    // --- Receiver state machine ----------------------------------------------
    typedef enum logic [1:0] {
        RX_IDLE  = 2'd0,
        RX_START = 2'd1,
        RX_DATA  = 2'd2,
        RX_STOP  = 2'd3
    } rx_state_t;

    rx_state_t   rx_state;
    logic [15:0] rx_cnt;
    logic [2:0]  rx_bit_idx;
    logic [7:0]  rx_sr;       // receive shift register

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_data    <= 8'b0;
            rx_valid   <= 1'b0;
            rx_cnt     <= '0;
            rx_bit_idx <= '0;
            rx_sr      <= '0;
        end else begin
            rx_valid <= 1'b0;   // default: pulse lasts exactly one cycle

            case (rx_state)

                // ---- IDLE: detect falling edge of start bit -----------------
                RX_IDLE: begin
                    if (!rxd_q) begin               // line went LOW -> start bit
                        rx_cnt   <= '0;
                        rx_state <= RX_START;
                    end
                end

                // ---- START: sample at mid-bit to confirm >= 0 ---------------
                RX_START: begin
                    if (rx_cnt == CLKS_PER_BIT / 2 - 1) begin
                        if (!rxd_q) begin           // still LOW: valid start bit
                            rx_cnt     <= '0;
                            rx_bit_idx <= '0;
                            rx_state   <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;    // glitch: discard
                        end
                    end else begin
                        rx_cnt <= rx_cnt + 1;
                    end
                end

                // ---- DATA: sample 8 bits at full-period intervals -----------
                RX_DATA: begin
                    if (rx_cnt == CLKS_PER_BIT - 1) begin
                        rx_cnt <= '0;
                        rx_sr  <= {rxd_q, rx_sr[7:1]};  // LSB first -> shift into MSB
                        if (rx_bit_idx == 3'd7) begin
                            rx_bit_idx <= '0;
                            rx_state   <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 1;
                        end
                    end else begin
                        rx_cnt <= rx_cnt + 1;
                    end
                end

                // ---- STOP: confirm HIGH, then latch byte --------------------
                RX_STOP: begin
                    if (rx_cnt == CLKS_PER_BIT - 1) begin
                        rx_cnt   <= '0;
                        rx_state <= RX_IDLE;
                        if (rxd_q) begin            // valid stop bit
                            rx_data  <= rx_sr;
                            rx_valid <= 1'b1;
                        end
                        // framing error (stop=0): silently discard
                    end else begin
                        rx_cnt <= rx_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
