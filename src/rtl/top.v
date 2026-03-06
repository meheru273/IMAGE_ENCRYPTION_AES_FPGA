//======================================================================
//
// top.v
// -----
// Top-level module for AES-128 Transparent Memory Encryption on
// Basys 3 FPGA. Connects UART, pixel buffer, AES controller, and
// BRAM into a complete encrypt/decrypt pipeline.
//
// Operation:
//   SW0 = 0 (ENCRYPT): PC sends image bytes via UART -> encrypt -> BRAM
//   SW0 = 1 (DECRYPT): Press btnC to start -> BRAM -> decrypt -> UART -> PC
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module top(
    input  wire       clk,           // 100 MHz system clock
    input  wire       rst_btn,       // btnC — active-high reset
    input  wire       uart_rx_pin,   // USB-UART RX
    output wire       uart_tx_pin,   // USB-UART TX
    input  wire       mode_sw,       // SW0: 0=encrypt, 1=decrypt
    input  wire       btn_start,     // btnR — trigger decrypt readback
    output reg  [3:0] status_led     // LED[3:0] status indicators
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam TOTAL_BLOCKS = 10'd1024;  // 128x128 / 16 = 1024 blocks
  localparam BYTES_PER_BLOCK = 4'd16;

  // Hardcoded AES-128 key for demo (change for production)
  localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;

  //----------------------------------------------------------------
  // System FSM States
  //----------------------------------------------------------------
  localparam SYS_IDLE           = 4'd0;
  localparam SYS_ENCRYPT_WAIT   = 4'd1;   // waiting for AES block
  localparam SYS_ENCRYPT_STORE  = 4'd2;   // writing ciphertext to BRAM
  localparam SYS_DECRYPT_READ   = 4'd3;   // reading ciphertext from BRAM
  localparam SYS_DECRYPT_WAIT   = 4'd4;   // waiting for AES block
  localparam SYS_DECRYPT_TX     = 4'd5;   // transmitting decrypted bytes
  localparam SYS_DONE           = 4'd6;

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  reg [3:0]   sys_state;
  reg [9:0]   wr_addr;          // write address counter (encrypt)
  reg [9:0]   rd_addr;          // read address counter (decrypt)
  reg         aes_start;
  reg         aes_mode;         // 1=encrypt, 0=decrypt
  reg [127:0] aes_block_in;
  reg         bram_wr_en;
  reg         bram_rd_en;
  reg [9:0]   bram_addr;
  reg [127:0] bram_din;
  reg [3:0]   tx_byte_idx;      // 0..15 byte index for TX
  reg         tx_send;
  reg [7:0]   tx_data;
  reg [127:0] decrypt_result;   // latched decrypt result for byte-by-byte TX
  reg         btn_start_prev;   // edge detection for btnR
  reg         encrypt_done_flag;// all 1024 blocks encrypted
  reg         decrypt_started;  // flag: AES decrypt start pulse sent

  //----------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------
  wire [7:0]  rx_data;
  wire        rx_valid;
  wire [127:0] pbuf_block;
  wire        pbuf_valid;
  wire [127:0] aes_block_out;
  wire        aes_done;
  wire [127:0] bram_dout;
  wire        tx_ready;

  //----------------------------------------------------------------
  // UART RX
  //----------------------------------------------------------------
  uart_rx u_uart_rx(
    .clk       (clk),
    .rst       (rst_btn),
    .rx        (uart_rx_pin),
    .data_out  (rx_data),
    .data_valid(rx_valid)
  );

  //----------------------------------------------------------------
  // UART TX
  //----------------------------------------------------------------
  uart_tx u_uart_tx(
    .clk     (clk),
    .rst     (rst_btn),
    .data_in (tx_data),
    .send    (tx_send),
    .tx      (uart_tx_pin),
    .ready   (tx_ready)
  );

  //----------------------------------------------------------------
  // Pixel Buffer
  //----------------------------------------------------------------
  pixel_buffer u_pixel_buffer(
    .clk        (clk),
    .rst        (rst_btn),
    .pixel_in   (rx_data),
    .pixel_valid(rx_valid & ~mode_sw),  // only buffer during encrypt mode
    .block_out  (pbuf_block),
    .block_valid(pbuf_valid)
  );

  //----------------------------------------------------------------
  // AES Controller (drives aes_core internally)
  //----------------------------------------------------------------
  aes_ctrl u_aes_ctrl(
    .clk       (clk),
    .rst       (rst_btn),
    .key_in    (AES_KEY),
    .block_in  (aes_block_in),
    .mode      (aes_mode),
    .start     (aes_start),
    .block_out (aes_block_out),
    .done      (aes_done)
  );

  //----------------------------------------------------------------
  // BRAM Controller
  //----------------------------------------------------------------
  bram_ctrl u_bram_ctrl(
    .clk   (clk),
    .wr_en (bram_wr_en),
    .rd_en (bram_rd_en),
    .addr  (bram_addr),
    .din   (bram_din),
    .dout  (bram_dout)
  );

  //----------------------------------------------------------------
  // Byte extractor: pull byte tx_byte_idx from 128-bit decrypt result
  // Byte 0 = MSB [127:120], Byte 15 = LSB [7:0]
  //----------------------------------------------------------------
  wire [7:0] tx_byte_from_block;
  assign tx_byte_from_block = decrypt_result[(15 - tx_byte_idx) * 8 +: 8];

  //----------------------------------------------------------------
  // System FSM
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_btn) begin
      sys_state       <= SYS_IDLE;
      wr_addr         <= 10'd0;
      rd_addr         <= 10'd0;
      aes_start       <= 1'b0;
      aes_mode        <= 1'b1;
      aes_block_in    <= 128'd0;
      bram_wr_en      <= 1'b0;
      bram_rd_en      <= 1'b0;
      bram_addr       <= 10'd0;
      bram_din        <= 128'd0;
      tx_byte_idx     <= 4'd0;
      tx_send         <= 1'b0;
      tx_data         <= 8'd0;
      decrypt_result  <= 128'd0;
      btn_start_prev  <= 1'b0;
      encrypt_done_flag <= 1'b0;
      decrypt_started <= 1'b0;
      status_led      <= 4'b0000;
    end else begin
      // Default pulse signals
      aes_start  <= 1'b0;
      bram_wr_en <= 1'b0;
      bram_rd_en <= 1'b0;
      tx_send    <= 1'b0;

      // Edge detection for start button
      btn_start_prev <= btn_start;

      case (sys_state)
        //----------------------------------------------------------
        // IDLE
        //----------------------------------------------------------
        SYS_IDLE: begin
          status_led <= 4'b0000;

          // ENCRYPT path: pixel buffer assembled a full block
          if (!mode_sw && pbuf_valid) begin
            aes_block_in <= pbuf_block;
            aes_mode     <= 1'b1;        // encrypt
            aes_start    <= 1'b1;
            sys_state    <= SYS_ENCRYPT_WAIT;
            status_led   <= 4'b0001;     // LED0 = encrypting
          end

          // DECRYPT path: user pressed start button (rising edge)
          if (mode_sw && btn_start && !btn_start_prev && encrypt_done_flag) begin
            rd_addr   <= 10'd0;
            sys_state <= SYS_DECRYPT_READ;
            status_led <= 4'b0010;       // LED1 = decrypting
          end
        end

        //----------------------------------------------------------
        // ENCRYPT: wait for AES done
        //----------------------------------------------------------
        SYS_ENCRYPT_WAIT: begin
          status_led <= 4'b0001;
          if (aes_done) begin
            bram_din   <= aes_block_out;
            bram_addr  <= wr_addr;
            bram_wr_en <= 1'b1;
            sys_state  <= SYS_ENCRYPT_STORE;
          end
        end

        //----------------------------------------------------------
        // ENCRYPT: store to BRAM, advance address
        //----------------------------------------------------------
        SYS_ENCRYPT_STORE: begin
          wr_addr <= wr_addr + 10'd1;
          if (wr_addr + 10'd1 == TOTAL_BLOCKS) begin
            encrypt_done_flag <= 1'b1;
            status_led <= 4'b0100;       // LED2 = done
            sys_state  <= SYS_IDLE;
          end else begin
            sys_state <= SYS_IDLE;       // wait for next block from pixel_buffer
          end
        end

        //----------------------------------------------------------
        // DECRYPT: read ciphertext block from BRAM
        //----------------------------------------------------------
        SYS_DECRYPT_READ: begin
          status_led      <= 4'b0010;
          bram_addr       <= rd_addr;
          bram_rd_en      <= 1'b1;
          decrypt_started <= 1'b0;
          sys_state       <= SYS_DECRYPT_WAIT;
        end

        //----------------------------------------------------------
        // DECRYPT: start AES decryption on BRAM output, wait for done
        //----------------------------------------------------------
        SYS_DECRYPT_WAIT: begin
          // First cycle: BRAM data is valid, start AES decrypt
          if (!decrypt_started) begin
            aes_block_in    <= bram_dout;
            aes_mode        <= 1'b0;        // decrypt
            aes_start       <= 1'b1;
            decrypt_started <= 1'b1;
          end
          if (aes_done) begin
            decrypt_result <= aes_block_out;
            tx_byte_idx    <= 4'd0;
            sys_state      <= SYS_DECRYPT_TX;
          end
        end

        //----------------------------------------------------------
        // DECRYPT: transmit 16 decrypted bytes over UART
        //----------------------------------------------------------
        SYS_DECRYPT_TX: begin
          if (tx_ready && !tx_send) begin
            tx_data <= tx_byte_from_block;
            tx_send <= 1'b1;
            if (tx_byte_idx == 4'd15) begin
              // All 16 bytes sent, move to next block
              rd_addr <= rd_addr + 10'd1;
              if (rd_addr + 10'd1 == TOTAL_BLOCKS) begin
                status_led <= 4'b0100;   // LED2 = done
                sys_state  <= SYS_DONE;
              end else begin
                decrypt_result <= 128'd0;
                tx_byte_idx    <= 4'd0;
                sys_state      <= SYS_DECRYPT_READ;
              end
            end else begin
              tx_byte_idx <= tx_byte_idx + 4'd1;
            end
          end
        end

        //----------------------------------------------------------
        // DONE: system complete
        //----------------------------------------------------------
        SYS_DONE: begin
          status_led <= 4'b0100;  // LED2 = done
        end

        default: sys_state <= SYS_IDLE;
      endcase
    end
  end

endmodule

//======================================================================
// EOF top.v
//======================================================================
