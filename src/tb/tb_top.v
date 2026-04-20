//======================================================================
// tb_top.v — End-to-end testbench for top module (4-mode system)
//
// Tests:
//   Phase 1: Mode 1 (Full encrypt) — send key + 16 plaintext bytes,
//            receive 16 encrypted bytes back
//   Phase 2: Mode 3 (Key-only retrieve, correct key) — send key,
//            receive 16 encrypted bytes, verify match
//   Phase 3: Mode 3 (Key-only retrieve, wrong key) — send wrong key,
//            receive single 0xFF byte
//   Phase 4: Mode 4 (Key-only decrypt) — send key, receive 16
//            decrypted bytes, verify match with original plaintext
//
// Uses 1 block (16 bytes) via parameter override for speed.
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_top();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD = 10;       // 100 MHz
  parameter BIT_PERIOD = 8680;     // 115200 baud

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg        clk;
  reg        rst_btn;
  reg        uart_rx_pin;
  wire       uart_tx_pin;
  reg        mode_sw;
  reg        mode_sw1;
  reg        btn_start;
  wire [3:0] status_led;

  integer    error_ctr;
  integer    total_errors;
  integer    i;
  reg  [7:0] test_data [0:15];         // 16 test plaintext bytes
  reg  [7:0] test_key [0:15];          // 16 test key bytes
  reg  [7:0] wrong_key [0:15];         // 16 wrong key bytes
  reg  [7:0] rx_captured [0:15];       // captured from UART TX
  reg  [7:0] encrypted_captured [0:15]; // encrypted output for Mode 3 verify
  integer    rx_idx;

  //----------------------------------------------------------------
  // DUT — override TOTAL_BLOCKS to 1 for simulation speed
  //----------------------------------------------------------------
  top #(.TOTAL_BLOCKS(10'd1)) dut(
    .clk         (clk),
    .rst_btn     (rst_btn),
    .uart_rx_pin (uart_rx_pin),
    .uart_tx_pin (uart_tx_pin),
    .mode_sw     (mode_sw),
    .mode_sw1    (mode_sw1),
    .btn_start   (btn_start),
    .status_led  (status_led)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Task: send one UART byte (LSB first)
  //----------------------------------------------------------------
  task uart_send(input [7:0] byte_val);
    integer b;
    begin
      // Start bit
      uart_rx_pin = 1'b0;
      #(BIT_PERIOD);
      // 8 data bits
      for (b = 0; b < 8; b = b + 1) begin
        uart_rx_pin = byte_val[b];
        #(BIT_PERIOD);
      end
      // Stop bit
      uart_rx_pin = 1'b1;
      #(BIT_PERIOD);
    end
  endtask

  //----------------------------------------------------------------
  // Task: capture one byte from UART TX line
  //----------------------------------------------------------------
  task uart_capture(output [7:0] captured);
    integer b;
    begin
      // Wait for start bit
      @(negedge uart_tx_pin);
      #(BIT_PERIOD / 2);  // move to mid-bit
      // Sample 8 data bits
      for (b = 0; b < 8; b = b + 1) begin
        #(BIT_PERIOD);
        captured[b] = uart_tx_pin;
      end
      // Wait through stop bit
      #(BIT_PERIOD);
    end
  endtask

  //----------------------------------------------------------------
  // Task: send 16-byte key over UART
  //----------------------------------------------------------------
  task send_key_bytes;
    integer k;
    begin
      for (k = 0; k < 16; k = k + 1) begin
        uart_send(test_key[k]);
      end
    end
  endtask

  //----------------------------------------------------------------
  // Task: send 16-byte wrong key over UART
  //----------------------------------------------------------------
  task send_wrong_key_bytes;
    integer k;
    begin
      for (k = 0; k < 16; k = k + 1) begin
        uart_send(wrong_key[k]);
      end
    end
  endtask

  //----------------------------------------------------------------
  // Task: press btnR (rising edge)
  //----------------------------------------------------------------
  task press_btn_start;
    begin
      @(posedge clk);
      btn_start = 1;
      #(2 * CLK_PERIOD);
      btn_start = 0;
      #(2 * CLK_PERIOD);
    end
  endtask

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("============================================================");
    $display("=== Top-Level 4-Mode End-to-End Testbench ===");
    $display("============================================================");
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);

    clk         = 0;
    rst_btn     = 1;
    uart_rx_pin = 1;  // idle high
    mode_sw     = 0;
    mode_sw1    = 0;
    btn_start   = 0;
    total_errors = 0;

    // Initialize test data: bytes 0x10..0x1F
    for (i = 0; i < 16; i = i + 1)
      test_data[i] = 8'h10 + i[7:0];

    // Initialize test key: NIST AES-128 key 2b7e151628aed2a6abf7158809cf4f3c
    test_key[0]  = 8'h2b; test_key[1]  = 8'h7e; test_key[2]  = 8'h15; test_key[3]  = 8'h16;
    test_key[4]  = 8'h28; test_key[5]  = 8'hae; test_key[6]  = 8'hd2; test_key[7]  = 8'ha6;
    test_key[8]  = 8'hab; test_key[9]  = 8'hf7; test_key[10] = 8'h15; test_key[11] = 8'h88;
    test_key[12] = 8'h09; test_key[13] = 8'hcf; test_key[14] = 8'h4f; test_key[15] = 8'h3c;

    // Initialize wrong key: all 0xAA
    for (i = 0; i < 16; i = i + 1)
      wrong_key[i] = 8'hAA;

    // Release reset
    #(50 * CLK_PERIOD);
    rst_btn = 0;
    #(50 * CLK_PERIOD);

    // ==========================================================
    // PHASE 1: MODE 1 — Full Encrypt
    // SW1=0, SW0=0: send key + 16 plaintext bytes, get encrypted
    // ==========================================================
    $display("");
    $display("--- Phase 1: Mode 1 (Full Encrypt) ---");
    mode_sw  = 0;
    mode_sw1 = 0;
    #(10 * CLK_PERIOD);

    press_btn_start;

    // Send 16-byte key
    $display("Sending 16-byte key...");
    send_key_bytes;

    // Send 16 plaintext bytes
    $display("Sending 16 plaintext bytes...");
    for (i = 0; i < 16; i = i + 1) begin
      uart_send(test_data[i]);
    end

    // Wait for encryption
    $display("Waiting for encryption...");
    #(5000 * CLK_PERIOD);

    // Capture 16 encrypted bytes streamed back
    $display("Capturing 16 encrypted bytes...");
    error_ctr = 0;
    for (i = 0; i < 16; i = i + 1) begin
      uart_capture(encrypted_captured[i]);
      $display("  Encrypted byte[%0d] = 0x%02h", i, encrypted_captured[i]);
    end

    // Verify encrypted output is not all-zero (basic sanity check)
    begin : enc_check
      reg all_zero;
      all_zero = 1;
      for (i = 0; i < 16; i = i + 1) begin
        if (encrypted_captured[i] != 8'h00)
          all_zero = 0;
      end
      if (all_zero) begin
        $display("  FAIL: Encrypted output is all zeros!");
        error_ctr = error_ctr + 1;
      end else begin
        $display("  OK: Encrypted output is non-zero.");
      end
    end

    total_errors = total_errors + error_ctr;
    if (error_ctr == 0)
      $display("Phase 1 PASSED");
    else
      $display("Phase 1 FAILED (%0d errors)", error_ctr);

    #(500 * CLK_PERIOD);

    // ==========================================================
    // PHASE 2: MODE 3 — Key-only Retrieve (correct key)
    // SW1=1, SW0=0: send key, get encrypted BRAM back
    // ==========================================================
    $display("");
    $display("--- Phase 2: Mode 3 (Key-only Retrieve, correct key) ---");
    mode_sw  = 0;
    mode_sw1 = 1;
    #(10 * CLK_PERIOD);

    press_btn_start;

    // Send same key
    $display("Sending correct key...");
    send_key_bytes;

    // Wait for key verification
    #(500 * CLK_PERIOD);

    // Capture 16 bytes — should match encrypted output from Phase 1
    $display("Capturing 16 retrieved bytes...");
    error_ctr = 0;
    for (i = 0; i < 16; i = i + 1) begin
      uart_capture(rx_captured[i]);
      $display("  Retrieved byte[%0d] = 0x%02h", i, rx_captured[i]);
    end

    // Verify match with Phase 1 encrypted output
    for (i = 0; i < 16; i = i + 1) begin
      if (rx_captured[i] !== encrypted_captured[i]) begin
        $display("  MISMATCH byte[%0d]: encrypted=0x%02h, retrieved=0x%02h",
                 i, encrypted_captured[i], rx_captured[i]);
        error_ctr = error_ctr + 1;
      end
    end

    total_errors = total_errors + error_ctr;
    if (error_ctr == 0)
      $display("Phase 2 PASSED");
    else
      $display("Phase 2 FAILED (%0d errors)", error_ctr);

    #(500 * CLK_PERIOD);

    // ==========================================================
    // PHASE 3: MODE 3 — Key-only Retrieve (wrong key)
    // SW1=1, SW0=0: send wrong key, expect single 0xFF
    // ==========================================================
    $display("");
    $display("--- Phase 3: Mode 3 (Key-only Retrieve, wrong key) ---");
    mode_sw  = 0;
    mode_sw1 = 1;
    #(10 * CLK_PERIOD);

    press_btn_start;

    // Send wrong key
    $display("Sending wrong key...");
    send_wrong_key_bytes;

    // Wait for key verification
    #(500 * CLK_PERIOD);

    // Capture 1 byte — should be 0xFF
    $display("Capturing error byte...");
    error_ctr = 0;
    begin : wrong_key_check
      reg [7:0] error_byte;
      uart_capture(error_byte);
      $display("  Error byte = 0x%02h", error_byte);
      if (error_byte !== 8'hFF) begin
        $display("  FAIL: Expected 0xFF, got 0x%02h", error_byte);
        error_ctr = error_ctr + 1;
      end else begin
        $display("  OK: Received expected 0xFF error byte.");
      end
    end

    total_errors = total_errors + error_ctr;
    if (error_ctr == 0)
      $display("Phase 3 PASSED");
    else
      $display("Phase 3 FAILED (%0d errors)", error_ctr);

    #(500 * CLK_PERIOD);

    // ==========================================================
    // PHASE 4: MODE 4 — Key-only Decrypt Stored
    // SW1=1, SW0=1: send key, receive decrypted image
    // ==========================================================
    $display("");
    $display("--- Phase 4: Mode 4 (Key-only Decrypt Stored) ---");
    mode_sw  = 1;
    mode_sw1 = 1;
    #(10 * CLK_PERIOD);

    press_btn_start;

    // Send correct key
    $display("Sending key for decrypt...");
    send_key_bytes;

    // Wait for decryption
    #(5000 * CLK_PERIOD);

    // Capture 16 decrypted bytes — should match original plaintext
    $display("Capturing 16 decrypted bytes...");
    error_ctr = 0;
    for (i = 0; i < 16; i = i + 1) begin
      uart_capture(rx_captured[i]);
      $display("  Decrypted byte[%0d] = 0x%02h", i, rx_captured[i]);
    end

    // Verify match with original plaintext
    for (i = 0; i < 16; i = i + 1) begin
      if (rx_captured[i] !== test_data[i]) begin
        $display("  MISMATCH byte[%0d]: original=0x%02h, decrypted=0x%02h",
                 i, test_data[i], rx_captured[i]);
        error_ctr = error_ctr + 1;
      end
    end

    total_errors = total_errors + error_ctr;
    if (error_ctr == 0)
      $display("Phase 4 PASSED");
    else
      $display("Phase 4 FAILED (%0d errors)", error_ctr);

    // ==========================================================
    // Final summary
    // ==========================================================
    $display("");
    $display("============================================================");
    if (total_errors == 0)
      $display("*** ALL TESTS PASSED ***");
    else
      $display("*** %0d TOTAL ERRORS ***", total_errors);
    $display("============================================================");

    #(100 * CLK_PERIOD);
    $finish;
  end

  // Timeout watchdog (generous for UART timing across 4 phases)
  initial begin
    #(2000000 * CLK_PERIOD);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
