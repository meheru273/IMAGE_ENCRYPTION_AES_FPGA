//======================================================================
//
// uart_tx.v
// ---------
// UART Transmitter module. Serialises 8-bit bytes onto the TX line
// at 115200 baud with a 100 MHz system clock.
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire       send,
    output reg        tx,
    output wire       ready
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868

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
  reg [15:0] clk_cnt;
  reg [2:0]  bit_idx;
  reg [7:0]  tx_shift;

  //----------------------------------------------------------------
  // Output assignment
  //----------------------------------------------------------------
  assign ready = (state == S_IDLE);

  //----------------------------------------------------------------
  // UART TX FSM
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      state    <= S_IDLE;
      clk_cnt  <= 16'd0;
      bit_idx  <= 3'd0;
      tx_shift <= 8'd0;
      tx       <= 1'b1;   // idle high
    end else begin
      case (state)
        // ----- IDLE: wait for send pulse -----
        S_IDLE: begin
          tx <= 1'b1;
          if (send) begin
            tx_shift <= data_in;
            state    <= S_START;
            clk_cnt  <= 16'd0;
          end
        end

        // ----- START BIT: drive low for one bit period -----
        S_START: begin
          tx <= 1'b0;
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            state   <= S_DATA;
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end

        // ----- DATA: send 8 bits LSB first -----
        S_DATA: begin
          tx <= tx_shift[bit_idx];
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 16'd0;
            if (bit_idx == 3'd7) begin
              state <= S_STOP;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end

        // ----- STOP BIT: drive high for one bit period -----
        S_STOP: begin
          tx <= 1'b1;
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 16'd0;
            state   <= S_IDLE;
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
// EOF uart_tx.v
//======================================================================
