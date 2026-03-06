//======================================================================
//
// bram_ctrl.v
// -----------
// Simple BRAM wrapper. Inferred by Vivado as BRAM36 primitives.
// 1024 entries x 128 bits = 16 KB of encrypted block storage.
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module bram_ctrl(
    input  wire          clk,
    input  wire          wr_en,
    input  wire          rd_en,
    input  wire  [9:0]   addr,
    input  wire  [127:0] din,
    output reg   [127:0] dout
);

  //----------------------------------------------------------------
  // Memory array — Vivado auto-infers as BRAM
  //----------------------------------------------------------------
  reg [127:0] mem [0:1023];

  //----------------------------------------------------------------
  // Read/Write logic
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (wr_en)
      mem[addr] <= din;
    if (rd_en)
      dout <= mem[addr];
  end

endmodule

//======================================================================
// EOF bram_ctrl.v
//======================================================================
