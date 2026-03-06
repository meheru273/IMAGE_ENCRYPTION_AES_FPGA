//======================================================================
//
// uart_rx.v
// ---------
// UART Receiver module. Deserialises incoming serial bits into 8-bit
// bytes at 115200 baud with a 100 MHz system clock.
// Samples at the mid-point of each bit for noise immunity.
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868 for 100MHz/115200
  localparam HALF_BIT     = CLKS_PER_BIT / 2;      // 434 — sample mid-bit

  //----------------------------------------------------------------
  // FSM States
  //----------------------------------------------------------------
  localparam S_IDLE  = 3'd0;
  localparam S_START = 3'd1;
  localparam S_DATA  = 3'd2;
  localparam S_STOP  = 3'd3;

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  reg [2:0]  state;
  reg [15:0] clk_cnt;     // bit-period counter
  reg [2:0]  bit_idx;     // 0..7 data bit index
  reg [7:0]  rx_shift;    // shift register

  // Double-flop synchroniser for metastability
  reg rx_sync_0, rx_sync_1;

  //----------------------------------------------------------------
  // Synchroniser
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      rx_sync_0 <= 1'b1;
      rx_sync_1 <= 1'b1;
    end else begin
      rx_sync_0 <= rx;
      rx_sync_1 <= rx_sync_0;
    end
  end

  //----------------------------------------------------------------
  // UART RX FSM
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      state      <= S_IDLE;
      clk_cnt    <= 16'd0;
      bit_idx    <= 3'd0;
      rx_shift   <= 8'd0;
      data_out   <= 8'd0;
      data_valid <= 1'b0;
    end else begin
      data_valid <= 1'b0;  // default: one-cycle pulse

      case (state)
        // ----- IDLE: wait for start bit (falling edge) -----
        S_IDLE: begin
          clk_cnt <= 16'd0;
          bit_idx <= 3'd0;
          if (rx_sync_1 == 1'b0)
            state <= S_START;
        end

        // ----- START: wait half bit period, verify still low -----
        S_START: begin
          if (clk_cnt == HALF_BIT - 1) begin
            clk_cnt <= 16'd0;
            if (rx_sync_1 == 1'b0)
              state <= S_DATA;   // valid start bit
            else
              state <= S_IDLE;   // glitch — abort
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end

        // ----- DATA: sample 8 bits at mid-bit -----
        S_DATA: begin
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 16'd0;
            rx_shift[bit_idx] <= rx_sync_1;  // LSB first
            if (bit_idx == 3'd7) begin
              bit_idx <= 3'd0;
              state   <= S_STOP;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end

        // ----- STOP: wait full bit period, output byte -----
        S_STOP: begin
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt    <= 16'd0;
            data_out   <= rx_shift;
            data_valid <= 1'b1;
            state      <= S_IDLE;
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

//======================================================================
// EOF uart_rx.v
//======================================================================
