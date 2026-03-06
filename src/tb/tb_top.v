//======================================================================
// tb_top.v — End-to-end testbench for top module
//
// Simulates: UART byte stream in -> pixel buffer -> AES encrypt ->
//            BRAM store -> mode switch -> AES decrypt -> UART out
//
// Tests with one AES block (16 bytes) for simulation speed.
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
  reg        btn_start;
  wire [3:0] status_led;

  integer    error_ctr;
  integer    i;
  reg  [7:0] test_data [0:15];   // 16 test bytes
  reg  [7:0] rx_captured [0:15]; // captured from UART TX
  integer    rx_idx;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  top dut(
    .clk         (clk),
    .rst_btn     (rst_btn),
    .uart_rx_pin (uart_rx_pin),
    .uart_tx_pin (uart_tx_pin),
    .mode_sw     (mode_sw),
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
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== Top-Level End-to-End Testbench ===");
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);

    clk         = 0;
    rst_btn     = 1;
    uart_rx_pin = 1;  // idle high
    mode_sw     = 0;  // encrypt mode
    btn_start   = 0;
    error_ctr   = 0;

    // Initialize test data: bytes 0x10..0x1F
    for (i = 0; i < 16; i = i + 1)
      test_data[i] = 8'h10 + i[7:0];

    #(50 * CLK_PERIOD);
    rst_btn = 0;
    #(50 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Phase 1: ENCRYPT — send 16 bytes over UART
    // ----------------------------------------------------------
    $display("Phase 1: Sending 16 bytes for encryption...");
    for (i = 0; i < 16; i = i + 1) begin
      uart_send(test_data[i]);
      $display("  Sent byte[%0d] = 0x%02h", i, test_data[i]);
    end

    // Wait for encryption and BRAM write to complete
    $display("Waiting for encryption to complete...");
    #(5000 * CLK_PERIOD);

    // ----------------------------------------------------------
    // Phase 2: DECRYPT — switch mode and trigger readback
    // ----------------------------------------------------------
    $display("Phase 2: Switching to decrypt mode...");
    mode_sw = 1;  // decrypt mode
    #(100 * CLK_PERIOD);

    // Note: in real hardware, encrypt_done_flag would need all 1024 blocks.
    // For simulation we directly check the BRAM content and decrypt.
    // We force the encrypt_done_flag for testing:
    force dut.encrypt_done_flag = 1'b1;
    force dut.wr_addr = 10'd1;  // pretend 1 block was stored
    #(10 * CLK_PERIOD);

    $display("Triggering decrypt readback...");
    @(posedge clk);
    btn_start = 1;
    #(2 * CLK_PERIOD);
    btn_start = 0;

    // Override TOTAL_BLOCKS check: we only encrypted 1 block
    // Force the system to stop after 1 block by adjusting addressing
    // (In simulation the FSM will handle this naturally for 1 block if rd_addr+1 matches)

    // ----------------------------------------------------------
    // Phase 3: Capture 16 decrypted bytes from UART TX
    // ----------------------------------------------------------
    $display("Phase 3: Capturing decrypted bytes from UART TX...");
    for (i = 0; i < 16; i = i + 1) begin
      uart_capture(rx_captured[i]);
      $display("  Captured byte[%0d] = 0x%02h", i, rx_captured[i]);
    end

    // ----------------------------------------------------------
    // Verify: decrypted bytes should match our original test_data
    // ----------------------------------------------------------
    $display("");
    $display("Verification:");
    for (i = 0; i < 16; i = i + 1) begin
      if (rx_captured[i] !== test_data[i]) begin
        $display("  MISMATCH byte[%0d]: sent 0x%02h, got 0x%02h",
                 i, test_data[i], rx_captured[i]);
        error_ctr = error_ctr + 1;
      end
    end

    if (error_ctr == 0)
      $display("*** END-TO-END TEST PASSED: All 16 bytes match ***");
    else
      $display("*** %0d BYTE MISMATCHES ***", error_ctr);

    #(100 * CLK_PERIOD);
    $finish;
  end

  // Timeout watchdog (generous for UART timing)
  initial begin
    #(500000 * CLK_PERIOD);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
