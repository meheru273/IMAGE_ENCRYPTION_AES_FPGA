//======================================================================
// tb_uart_tx.v — Testbench for UART Transmitter
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_uart_tx();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD  = 10;         // 100 MHz
  parameter BIT_PERIOD  = 8680;       // 115200 baud

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg        clk;
  reg        rst;
  reg  [7:0] data_in;
  reg        send;
  wire       tx;
  wire       ready;

  integer    error_ctr;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  uart_tx dut(
    .clk     (clk),
    .rst     (rst),
    .data_in (data_in),
    .send    (send),
    .tx      (tx),
    .ready   (ready)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Task: capture and verify one UART frame from TX line
  //----------------------------------------------------------------
  task capture_and_verify(input [7:0] expected);
    reg [7:0] captured;
    integer i;
    begin
      // Wait for start bit (falling edge of TX)
      @(negedge tx);

      // Wait to mid-point of start bit
      #(BIT_PERIOD / 2);

      // Verify start bit is low
      if (tx !== 1'b0) begin
        $display("ERROR: Start bit not low");
        error_ctr = error_ctr + 1;
      end

      // Sample 8 data bits at mid-point
      for (i = 0; i < 8; i = i + 1) begin
        #(BIT_PERIOD);
        captured[i] = tx;
      end

      // Verify stop bit
      #(BIT_PERIOD);
      if (tx !== 1'b1) begin
        $display("ERROR: Stop bit not high");
        error_ctr = error_ctr + 1;
      end

      // Compare
      if (captured !== expected) begin
        $display("ERROR: Expected 0x%02h, captured 0x%02h", expected, captured);
        error_ctr = error_ctr + 1;
      end else begin
        $display("OK: Captured 0x%02h from TX", captured);
      end
    end
  endtask

  //----------------------------------------------------------------
  // Task: trigger send
  //----------------------------------------------------------------
  task send_byte(input [7:0] byte_val);
    begin
      @(posedge clk);
      data_in = byte_val;
      send    = 1;
      @(posedge clk);
      send    = 0;
    end
  endtask

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== UART TX Testbench ===");
    $dumpfile("tb_uart_tx.vcd");
    $dumpvars(0, tb_uart_tx);

    clk       = 0;
    rst       = 1;
    data_in   = 8'h00;
    send      = 0;
    error_ctr = 0;

    #(20 * CLK_PERIOD);
    rst = 0;
    #(10 * CLK_PERIOD);

    // Test 1: Send 0x41 ('A')
    $display("Test 1: Sending 0x41");
    send_byte(8'h41);
    capture_and_verify(8'h41);
    #(2 * BIT_PERIOD);

    // Test 2: Send 0xBE
    $display("Test 2: Sending 0xBE");
    send_byte(8'hBE);
    capture_and_verify(8'hBE);
    #(2 * BIT_PERIOD);

    // Test 3: Send 0x00
    $display("Test 3: Sending 0x00");
    send_byte(8'h00);
    capture_and_verify(8'h00);
    #(2 * BIT_PERIOD);

    // Test 4: Send 0xFF
    $display("Test 4: Sending 0xFF");
    send_byte(8'hFF);
    capture_and_verify(8'hFF);
    #(2 * BIT_PERIOD);

    // Results
    if (error_ctr == 0)
      $display("*** ALL UART TX TESTS PASSED ***");
    else
      $display("*** %0d TESTS FAILED ***", error_ctr);

    $finish;
  end

  // Timeout watchdog
  initial begin
    #(200 * BIT_PERIOD);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
