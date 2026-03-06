//======================================================================
// tb_uart_rx.v — Testbench for UART Receiver
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_uart_rx();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_PERIOD  = 10;         // 100 MHz -> 10 ns
  parameter BIT_PERIOD  = 8680;       // 115200 baud -> 8680 ns per bit

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  reg        clk;
  reg        rst;
  reg        rx;
  wire [7:0] data_out;
  wire       data_valid;

  integer    error_ctr;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  uart_rx dut(
    .clk       (clk),
    .rst       (rst),
    .rx        (rx),
    .data_out  (data_out),
    .data_valid(data_valid)
  );

  //----------------------------------------------------------------
  // Clock generation
  //----------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  //----------------------------------------------------------------
  // Task: send one UART byte (LSB first)
  //----------------------------------------------------------------
  task send_byte(input [7:0] byte_val);
    integer i;
    begin
      // Start bit
      rx = 1'b0;
      #(BIT_PERIOD);

      // 8 data bits, LSB first
      for (i = 0; i < 8; i = i + 1) begin
        rx = byte_val[i];
        #(BIT_PERIOD);
      end

      // Stop bit
      rx = 1'b1;
      #(BIT_PERIOD);
    end
  endtask

  //----------------------------------------------------------------
  // Task: check received byte
  //----------------------------------------------------------------
  task check_byte(input [7:0] expected);
    begin
      // Wait for data_valid
      @(posedge data_valid);
      #1;
      if (data_out !== expected) begin
        $display("ERROR: Expected 0x%02h, got 0x%02h", expected, data_out);
        error_ctr = error_ctr + 1;
      end else begin
        $display("OK: Received 0x%02h", data_out);
      end
    end
  endtask

  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  initial begin
    $display("=== UART RX Testbench ===");
    $dumpfile("tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    clk       = 0;
    rst       = 1;
    rx        = 1;   // idle high
    error_ctr = 0;

    #(20 * CLK_PERIOD);
    rst = 0;
    #(10 * CLK_PERIOD);

    // Test 1: Send 0x55 (alternating bits: 01010101)
    $display("Test 1: Sending 0x55");
    send_byte(8'h55);
    check_byte(8'h55);
    #(5 * BIT_PERIOD);

    // Test 2: Send 0xA3
    $display("Test 2: Sending 0xA3");
    send_byte(8'hA3);
    check_byte(8'hA3);
    #(5 * BIT_PERIOD);

    // Test 3: Send 0xFF
    $display("Test 3: Sending 0xFF");
    send_byte(8'hFF);
    check_byte(8'hFF);
    #(5 * BIT_PERIOD);

    // Test 4: Send 0x00
    $display("Test 4: Sending 0x00");
    send_byte(8'h00);
    check_byte(8'h00);
    #(5 * BIT_PERIOD);

    // Results
    if (error_ctr == 0)
      $display("*** ALL UART RX TESTS PASSED ***");
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
