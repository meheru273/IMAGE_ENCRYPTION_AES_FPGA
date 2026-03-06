//======================================================================
// tb_pixel_buffer.v — Testbench for Pixel Buffer
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_pixel_buffer();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD = 10;

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg          clk;
  reg          rst;
  reg  [7:0]   pixel_in;
  reg          pixel_valid;
  wire [127:0] block_out;
  wire         block_valid;

  integer      error_ctr;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  pixel_buffer dut(
    .clk        (clk),
    .rst        (rst),
    .pixel_in   (pixel_in),
    .pixel_valid(pixel_valid),
    .block_out  (block_out),
    .block_valid(block_valid)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== Pixel Buffer Testbench ===");
    $dumpfile("tb_pixel_buffer.vcd");
    $dumpvars(0, tb_pixel_buffer);

    clk         = 0;
    rst         = 1;
    pixel_in    = 8'h00;
    pixel_valid = 0;
    error_ctr   = 0;

    #(20 * CLK_PERIOD);
    rst = 0;
    #(10 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 1: Send bytes 0x00..0x0F, expect block = 0x000102...0E0F
    // ----------------------------------------------------------
    $display("Test 1: Sequential bytes 0x00..0x0F");
    begin : test1_block
      integer i;
      for (i = 0; i < 16; i = i + 1) begin
        @(posedge clk);
        pixel_in    = i[7:0];
        pixel_valid = 1;
        @(posedge clk);
        pixel_valid = 0;
        #(2 * CLK_PERIOD);  // gap between bytes
      end
    end

    // Wait for block_valid
    @(posedge block_valid);
    #1;
    if (block_out !== 128'h000102030405060708090a0b0c0d0e0f) begin
      $display("ERROR: Expected 0x000102030405060708090a0b0c0d0e0f");
      $display("       Got      0x%032h", block_out);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: Block = 0x%032h", block_out);
    end

    #(10 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 2: Send bytes 0xFF repeated, expect block = 0xFFFF...FF
    // ----------------------------------------------------------
    $display("Test 2: All 0xFF bytes");
    begin : test2_block
      integer i;
      for (i = 0; i < 16; i = i + 1) begin
        @(posedge clk);
        pixel_in    = 8'hFF;
        pixel_valid = 1;
        @(posedge clk);
        pixel_valid = 0;
        #(2 * CLK_PERIOD);
      end
    end

    @(posedge block_valid);
    #1;
    if (block_out !== 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin
      $display("ERROR: Expected all FF, got 0x%032h", block_out);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: Block = 0x%032h", block_out);
    end

    #(10 * CLK_PERIOD);

    // Results
    if (error_ctr == 0)
      $display("*** ALL PIXEL BUFFER TESTS PASSED ***");
    else
      $display("*** %0d TESTS FAILED ***", error_ctr);

    $finish;
  end

  // Timeout
  initial begin
    #(5000 * CLK_PERIOD);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
