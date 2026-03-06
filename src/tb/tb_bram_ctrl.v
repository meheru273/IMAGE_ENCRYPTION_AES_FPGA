//======================================================================
// tb_bram_ctrl.v — Testbench for BRAM Controller
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_bram_ctrl();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD = 10;

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg          clk;
  reg          wr_en;
  reg          rd_en;
  reg  [9:0]   addr;
  reg  [127:0] din;
  wire [127:0] dout;

  integer      error_ctr;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  bram_ctrl dut(
    .clk   (clk),
    .wr_en (wr_en),
    .rd_en (rd_en),
    .addr  (addr),
    .din   (din),
    .dout  (dout)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== BRAM Controller Testbench ===");
    $dumpfile("tb_bram_ctrl.vcd");
    $dumpvars(0, tb_bram_ctrl);

    clk       = 0;
    wr_en     = 0;
    rd_en     = 0;
    addr      = 10'd0;
    din       = 128'd0;
    error_ctr = 0;

    #(20 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 1: Write then read a known pattern at address 0
    // ----------------------------------------------------------
    $display("Test 1: Write/Read at addr 0");
    @(posedge clk);
    addr  = 10'd0;
    din   = 128'hDEADBEEFCAFEBABE0123456789ABCDEF;
    wr_en = 1;
    @(posedge clk);
    wr_en = 0;

    // Read back
    @(posedge clk);
    addr  = 10'd0;
    rd_en = 1;
    @(posedge clk);
    rd_en = 0;
    @(posedge clk);  // one cycle read latency

    if (dout !== 128'hDEADBEEFCAFEBABE0123456789ABCDEF) begin
      $display("ERROR: addr 0 mismatch. Got 0x%032h", dout);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: addr 0 = 0x%032h", dout);
    end

    // ----------------------------------------------------------
    // Test 2: Write at addr 100, read at addr 100
    // ----------------------------------------------------------
    $display("Test 2: Write/Read at addr 100");
    @(posedge clk);
    addr  = 10'd100;
    din   = 128'h112233445566778899AABBCCDDEEFF00;
    wr_en = 1;
    @(posedge clk);
    wr_en = 0;

    @(posedge clk);
    addr  = 10'd100;
    rd_en = 1;
    @(posedge clk);
    rd_en = 0;
    @(posedge clk);

    if (dout !== 128'h112233445566778899AABBCCDDEEFF00) begin
      $display("ERROR: addr 100 mismatch. Got 0x%032h", dout);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: addr 100 = 0x%032h", dout);
    end

    // ----------------------------------------------------------
    // Test 3: Write at addr 1023 (max), verify
    // ----------------------------------------------------------
    $display("Test 3: Write/Read at addr 1023");
    @(posedge clk);
    addr  = 10'd1023;
    din   = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    wr_en = 1;
    @(posedge clk);
    wr_en = 0;

    @(posedge clk);
    addr  = 10'd1023;
    rd_en = 1;
    @(posedge clk);
    rd_en = 0;
    @(posedge clk);

    if (dout !== 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin
      $display("ERROR: addr 1023 mismatch. Got 0x%032h", dout);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: addr 1023 = 0x%032h", dout);
    end

    // ----------------------------------------------------------
    // Test 4: Verify addr 0 still has original data (no corruption)
    // ----------------------------------------------------------
    $display("Test 4: Re-read addr 0 (no corruption check)");
    @(posedge clk);
    addr  = 10'd0;
    rd_en = 1;
    @(posedge clk);
    rd_en = 0;
    @(posedge clk);

    if (dout !== 128'hDEADBEEFCAFEBABE0123456789ABCDEF) begin
      $display("ERROR: addr 0 corrupted. Got 0x%032h", dout);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: addr 0 still intact");
    end

    #(10 * CLK_PERIOD);

    // Results
    if (error_ctr == 0)
      $display("*** ALL BRAM TESTS PASSED ***");
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
