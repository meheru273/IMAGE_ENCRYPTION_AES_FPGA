//======================================================================
//
// pixel_buffer.v
// --------------
// Accumulates 16 incoming bytes (pixels) into a single 128-bit AES
// block. Asserts block_valid for one cycle when full block is ready.
// Bytes are packed MSB-first: first byte received goes into
// block_out[127:120], last byte into block_out[7:0].
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module pixel_buffer(
    input  wire         clk,
    input  wire         rst,
    input  wire         soft_rst,    // resets byte_cnt without full reset
    input  wire [7:0]   pixel_in,
    input  wire         pixel_valid,
    output reg  [127:0] block_out,
    output reg          block_valid
);

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  reg [3:0]   byte_cnt;     // 0..15
  reg [127:0] shift_reg;

  //----------------------------------------------------------------
  // Shift register logic
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst || soft_rst) begin
      byte_cnt    <= 4'd0;
      shift_reg   <= 128'd0;
      block_out   <= 128'd0;
      block_valid <= 1'b0;
    end else begin
      block_valid <= 1'b0;  // default: one-cycle pulse

      if (pixel_valid) begin
        // Shift left by 8 and insert new byte at LSB
        shift_reg <= {shift_reg[119:0], pixel_in};
        
        if (byte_cnt == 4'd15) begin
          // Full block assembled — output it
          block_out   <= {shift_reg[119:0], pixel_in};
          block_valid <= 1'b1;
          byte_cnt    <= 4'd0;
        end else begin
          byte_cnt <= byte_cnt + 4'd1;
        end
      end
    end
  end

endmodule

//======================================================================
// EOF pixel_buffer.v
//======================================================================
