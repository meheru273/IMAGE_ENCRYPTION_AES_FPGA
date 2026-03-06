//======================================================================
// tb_aes_ctrl.v — Testbench for AES Controller FSM
//
// Uses NIST test vectors to verify:
//   1. Encrypt a plaintext block -> verify ciphertext
//   2. Decrypt the ciphertext -> verify round-trip matches original
//   3. Process a second block (key already expanded, skip KEY_INIT)
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_aes_ctrl();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD = 10;   // 100 MHz

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg          clk;
  reg          rst;
  reg  [127:0] key_in;
  reg  [127:0] block_in;
  reg          mode;        // 1=encrypt, 0=decrypt
  reg          start;
  wire [127:0] block_out;
  wire         done;

  integer      error_ctr;

  //----------------------------------------------------------------
  // NIST Test Vectors (AES-128, ECB)
  //----------------------------------------------------------------
  // Key:       2b7e1516 28aed2a6 abf71588 09cf4f3c
  // Plaintext: 6bc1bee2 2e409f96 e93d7e11 7393172a
  // Cipher:    3ad77bb4 0d7a3660 a89ecaf3 2466ef97
  localparam [127:0] NIST_KEY   = 128'h2b7e151628aed2a6abf7158809cf4f3c;
  localparam [127:0] NIST_PT0   = 128'h6bc1bee22e409f96e93d7e117393172a;
  localparam [127:0] NIST_CT0   = 128'h3ad77bb40d7a3660a89ecaf32466ef97;

  // Second NIST plaintext/ciphertext (same key)
  localparam [127:0] NIST_PT1   = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
  localparam [127:0] NIST_CT1   = 128'hf5d3d58503b9699de785895a96fdbaaf;

  //----------------------------------------------------------------
  // DUT — aes_ctrl instantiates aes_core internally
  //----------------------------------------------------------------
  aes_ctrl dut(
    .clk       (clk),
    .rst       (rst),
    .key_in    (key_in),
    .block_in  (block_in),
    .mode      (mode),
    .start     (start),
    .block_out (block_out),
    .done      (done)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== AES Controller Testbench ===");
    $dumpfile("tb_aes_ctrl.vcd");
    $dumpvars(0, tb_aes_ctrl);

    clk       = 0;
    rst       = 1;
    key_in    = NIST_KEY;
    block_in  = 128'd0;
    mode      = 1'b1;
    start     = 1'b0;
    error_ctr = 0;

    #(20 * CLK_PERIOD);
    rst = 0;
    #(10 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 1: Encrypt NIST_PT0 (includes key expansion)
    // ----------------------------------------------------------
    $display("Test 1: Encrypt (with key expansion)");
    @(posedge clk);
    block_in = NIST_PT0;
    mode     = 1'b1;   // encrypt
    start    = 1'b1;
    @(posedge clk);
    start    = 1'b0;

    // Wait for done
    @(posedge done);
    #1;
    if (block_out !== NIST_CT0) begin
      $display("ERROR: Encrypt failed");
      $display("  Expected: 0x%032h", NIST_CT0);
      $display("  Got:      0x%032h", block_out);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: Ciphertext = 0x%032h", block_out);
    end

    #(10 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 2: Decrypt NIST_CT0 -> should recover NIST_PT0
    // ----------------------------------------------------------
    $display("Test 2: Decrypt (key already expanded)");
    @(posedge clk);
    block_in = NIST_CT0;
    mode     = 1'b0;   // decrypt
    start    = 1'b1;
    @(posedge clk);
    start    = 1'b0;

    @(posedge done);
    #1;
    if (block_out !== NIST_PT0) begin
      $display("ERROR: Decrypt failed");
      $display("  Expected: 0x%032h", NIST_PT0);
      $display("  Got:      0x%032h", block_out);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: Plaintext = 0x%032h", block_out);
    end

    #(10 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Test 3: Encrypt second block NIST_PT1 (key already expanded)
    // ----------------------------------------------------------
    $display("Test 3: Encrypt second block (no key expansion)");
    @(posedge clk);
    block_in = NIST_PT1;
    mode     = 1'b1;
    start    = 1'b1;
    @(posedge clk);
    start    = 1'b0;

    @(posedge done);
    #1;
    if (block_out !== NIST_CT1) begin
      $display("ERROR: Encrypt block 2 failed");
      $display("  Expected: 0x%032h", NIST_CT1);
      $display("  Got:      0x%032h", block_out);
      error_ctr = error_ctr + 1;
    end else begin
      $display("OK: Ciphertext 2 = 0x%032h", block_out);
    end

    #(20 * CLK_PERIOD);

    // Results
    $display("");
    if (error_ctr == 0)
      $display("*** ALL AES CTRL TESTS PASSED ***");
    else
      $display("*** %0d TESTS FAILED ***", error_ctr);

    $finish;
  end

  // Timeout watchdog
  initial begin
    #(50000 * CLK_PERIOD);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
