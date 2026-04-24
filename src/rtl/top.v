//======================================================================
//
// top.v
// -----
// Top-level module for AES-128 Transparent Memory Encryption on
// Basys 3 FPGA. Connects UART, pixel buffer, AES controller, and
// BRAM into a complete encrypt/decrypt pipeline.
//
// Modes (selected by {SW1, SW0} after btnR is pressed):
//   Mode 1 (00): Full encrypt — key + image in, encrypted image out
//   Mode 2 (01): Full decrypt — key + ciphertext in, plaintext out
//   Mode 3 (10): Key-only retrieve — key verification, then BRAM dump
//   Mode 4 (11): Key-only decrypt — decrypt stored BRAM with given key
//
// All modes receive a 16-byte key over UART first (triggered by btnR).
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
    input  wire       mode_sw1,      // SW1: 0=full image, 1=key-only
    input  wire       btn_start,     // btnR — trigger operation
    output reg  [3:0] status_led,    // LED[3:0] status indicators
    output reg  [6:0] seg,           // 7-segment cathodes (active-low)
    output reg  [3:0] an             // 7-segment anodes   (active-low)
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter TOTAL_BLOCKS = 10'd1024;  // 128x128 / 16 = 1024 blocks
  localparam BYTES_PER_BLOCK = 4'd16;

  //----------------------------------------------------------------
  // System FSM States
  //----------------------------------------------------------------
  localparam SYS_IDLE           = 4'd0;
  localparam SYS_KEY_RX         = 4'd1;   // receive 16 key bytes
  localparam SYS_DISPATCH       = 4'd2;   // branch on {SW1, SW0}
  localparam SYS_ENCRYPT_RX     = 4'd3;   // wait for pixel_buffer block [Mode 1]
  localparam SYS_ENCRYPT_WAIT   = 4'd4;   // wait for AES encrypt done   [Mode 1]
  localparam SYS_ENCRYPT_STORE  = 4'd5;   // write ciphertext to BRAM    [Mode 1]
  localparam SYS_BRAM_STREAM    = 4'd6;   // raw BRAM readout over UART  [Mode 1+3]
  localparam SYS_BRAM_STREAM_TX = 4'd7;   // TX bytes of current block   [Mode 1+3]
  localparam SYS_CIPHER_RX      = 4'd8;   // receive ciphertext to BRAM  [Mode 2]
  localparam SYS_DECRYPT_READ   = 4'd9;   // read ciphertext from BRAM   [Mode 2+4]
  localparam SYS_DECRYPT_WAIT   = 4'd10;  // AES decrypt, wait for done  [Mode 2+4]
  localparam SYS_DECRYPT_TX     = 4'd11;  // TX decrypted bytes          [Mode 2+4]
  localparam SYS_KEY_VERIFY     = 4'd12;  // compare keys                [Mode 3]
  localparam SYS_ERROR          = 4'd13;  // send 0xFF, return to idle   [Mode 3]
  localparam SYS_DONE           = 4'd14;  // LED2 on, return to idle

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  reg [3:0]   sys_state;
  reg [9:0]   wr_addr;          // write address counter (encrypt/cipher RX)
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
  reg         decrypt_started;  // flag: AES decrypt start pulse sent

  // Key reception registers
  reg [127:0] user_key_reg;     // key received from host this session
  reg [127:0] stored_key_reg;   // key saved during last Mode 1 encrypt
  reg [3:0]   key_byte_cnt;     // counts 0..15 during SYS_KEY_RX
  reg [127:0] key_shift_reg;    // accumulates incoming key bytes
  reg         key_reset_pulse;  // drives aes_ctrl key_reset

  // BRAM streaming registers (raw readout without AES)
  reg [9:0]   stream_addr;      // BRAM address for raw streaming
  reg [3:0]   stream_byte_idx;  // byte index within current block
  reg [127:0] stream_block;     // latched BRAM data for raw streaming
  reg         stream_rd_pending;// waiting for BRAM read latency

  // Mode latch — captured at SYS_KEY_RX entry
  reg [1:0]   mode_latch;

  // Pixel buffer soft reset
  reg         pbuf_soft_rst;

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

  // Pixel buffer is only fed data during SYS_ENCRYPT_RX and SYS_CIPHER_RX
  wire        pbuf_pixel_valid;
  assign pbuf_pixel_valid = rx_valid & (sys_state == SYS_ENCRYPT_RX || sys_state == SYS_CIPHER_RX);

  //----------------------------------------------------------------
  // Double-flop synchronizers for external inputs
  //----------------------------------------------------------------
  reg btn_start_s0, btn_start_s1;
  reg mode_sw_s0,   mode_sw_s1;
  reg mode_sw1_s0,  mode_sw1_s1;

  always @(posedge clk) begin
    if (rst_btn) begin
      btn_start_s0 <= 1'b0; btn_start_s1 <= 1'b0;
      mode_sw_s0   <= 1'b0; mode_sw_s1   <= 1'b0;
      mode_sw1_s0  <= 1'b0; mode_sw1_s1  <= 1'b0;
    end else begin
      btn_start_s0 <= btn_start;   btn_start_s1 <= btn_start_s0;
      mode_sw_s0   <= mode_sw;     mode_sw_s1   <= mode_sw_s0;
      mode_sw1_s0  <= mode_sw1;    mode_sw1_s1  <= mode_sw1_s0;
    end
  end

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
    .soft_rst   (pbuf_soft_rst),
    .pixel_in   (rx_data),
    .pixel_valid(pbuf_pixel_valid),
    .block_out  (pbuf_block),
    .block_valid(pbuf_valid)
  );

  //----------------------------------------------------------------
  // AES Controller (drives aes_core internally)
  //----------------------------------------------------------------
  aes_ctrl u_aes_ctrl(
    .clk       (clk),
    .rst       (rst_btn),
    .key_reset (key_reset_pulse),
    .key_in    (user_key_reg),
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
  // Byte extractors
  //----------------------------------------------------------------
  // Decrypt path: pull byte tx_byte_idx from 128-bit decrypt result
  wire [7:0] tx_byte_from_block;
  assign tx_byte_from_block = decrypt_result[(15 - tx_byte_idx) * 8 +: 8];

  // Stream path: pull byte stream_byte_idx from 128-bit raw BRAM block
  wire [7:0] stream_byte_from_block;
  assign stream_byte_from_block = stream_block[(15 - stream_byte_idx) * 8 +: 8];

  //----------------------------------------------------------------
  // System FSM
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_btn) begin
      sys_state        <= SYS_IDLE;
      wr_addr          <= 10'd0;
      rd_addr          <= 10'd0;
      aes_start        <= 1'b0;
      aes_mode         <= 1'b1;
      aes_block_in     <= 128'd0;
      bram_wr_en       <= 1'b0;
      bram_rd_en       <= 1'b0;
      bram_addr        <= 10'd0;
      bram_din         <= 128'd0;
      tx_byte_idx      <= 4'd0;
      tx_send          <= 1'b0;
      tx_data          <= 8'd0;
      decrypt_result   <= 128'd0;
      btn_start_prev   <= 1'b0;
      decrypt_started  <= 1'b0;
      status_led       <= 4'b0000;
      user_key_reg     <= 128'd0;
      stored_key_reg   <= 128'd0;
      key_byte_cnt     <= 4'd0;
      key_shift_reg    <= 128'd0;
      key_reset_pulse  <= 1'b0;
      stream_addr      <= 10'd0;
      stream_byte_idx  <= 4'd0;
      stream_block     <= 128'd0;
      stream_rd_pending <= 1'b0;
      mode_latch       <= 2'b00;
      pbuf_soft_rst    <= 1'b0;
    end else begin
      // Default pulse signals
      aes_start       <= 1'b0;
      bram_wr_en      <= 1'b0;
      bram_rd_en      <= 1'b0;
      tx_send         <= 1'b0;
      key_reset_pulse <= 1'b0;
      pbuf_soft_rst   <= 1'b0;

      // Edge detection for start button
      btn_start_prev <= btn_start_s1;

      case (sys_state)
        //----------------------------------------------------------
        // IDLE — wait for btnR rising edge
        //----------------------------------------------------------
        SYS_IDLE: begin
          status_led <= 4'b0000;
          if (btn_start_s1 && !btn_start_prev) begin
            // Latch mode switches and start key reception
            mode_latch    <= {mode_sw1_s1, mode_sw_s1};
            key_byte_cnt  <= 4'd0;
            key_shift_reg <= 128'd0;
            sys_state     <= SYS_KEY_RX;
          end
        end

        //----------------------------------------------------------
        // KEY_RX — receive 16 key bytes from UART
        //----------------------------------------------------------
        SYS_KEY_RX: begin
          status_led <= 4'b0000;
          if (rx_valid) begin
            key_shift_reg <= {key_shift_reg[119:0], rx_data};
            if (key_byte_cnt == 4'd15) begin
              // All 16 bytes received — load user_key_reg
              user_key_reg    <= {key_shift_reg[119:0], rx_data};
              key_reset_pulse <= 1'b1;  // force AES key re-expansion
              sys_state       <= SYS_DISPATCH;
            end else begin
              key_byte_cnt <= key_byte_cnt + 4'd1;
            end
          end
        end

        //----------------------------------------------------------
        // DISPATCH — branch on latched {SW1, SW0}
        //----------------------------------------------------------
        SYS_DISPATCH: begin
          pbuf_soft_rst <= 1'b1;  // reset pixel buffer for fresh data

          case (mode_latch)
            2'b00: begin  // Mode 1 — Full encrypt
              wr_addr    <= 10'd0;
              status_led <= 4'b0001;  // LED0 = encrypting
              sys_state  <= SYS_ENCRYPT_RX;
            end

            2'b01: begin  // Mode 2 — Full decrypt
              wr_addr    <= 10'd0;
              status_led <= 4'b0010;  // LED1 = decrypting
              sys_state  <= SYS_CIPHER_RX;
            end

            2'b10: begin  // Mode 3 — Key-only retrieve
              sys_state <= SYS_KEY_VERIFY;
            end

            2'b11: begin  // Mode 4 — Key-only decrypt stored
              rd_addr    <= 10'd0;
              status_led <= 4'b0010;  // LED1 = decrypting
              sys_state  <= SYS_DECRYPT_READ;
            end
          endcase
        end

        //----------------------------------------------------------
        // MODE 1: ENCRYPT_RX — wait for pixel buffer to assemble block
        //----------------------------------------------------------
        SYS_ENCRYPT_RX: begin
          status_led <= 4'b0001;
          if (pbuf_valid) begin
            aes_block_in <= pbuf_block;
            aes_mode     <= 1'b1;     // encrypt
            aes_start    <= 1'b1;
            sys_state    <= SYS_ENCRYPT_WAIT;
          end
        end

        //----------------------------------------------------------
        // MODE 1: ENCRYPT_WAIT — wait for AES done
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
        // MODE 1: ENCRYPT_STORE — write to BRAM, advance address
        //----------------------------------------------------------
        SYS_ENCRYPT_STORE: begin
          wr_addr <= wr_addr + 10'd1;
          if (wr_addr + 10'd1 == TOTAL_BLOCKS) begin
            // All 1024 blocks encrypted — save key & stream back
            stored_key_reg   <= user_key_reg;
            stream_addr      <= 10'd0;
            stream_byte_idx  <= 4'd0;
            stream_rd_pending <= 1'b0;
            sys_state        <= SYS_BRAM_STREAM;
          end else begin
            sys_state <= SYS_ENCRYPT_RX;  // wait for next block
          end
        end

        //----------------------------------------------------------
        // BRAM_STREAM — read BRAM and stream raw contents over UART
        // Used by Mode 1 (after encrypt) and Mode 3 (key verified)
        //----------------------------------------------------------
        SYS_BRAM_STREAM: begin
          status_led <= 4'b0100;  // LED2
          if (!stream_rd_pending) begin
            // Issue BRAM read
            bram_addr        <= stream_addr;
            bram_rd_en       <= 1'b1;
            stream_rd_pending <= 1'b1;
          end else begin
            // BRAM data available after 1-cycle latency
            stream_block     <= bram_dout;
            stream_byte_idx  <= 4'd0;
            stream_rd_pending <= 1'b0;
            sys_state        <= SYS_BRAM_STREAM_TX;
          end
        end

        //----------------------------------------------------------
        // BRAM_STREAM_TX — transmit 16 bytes of current raw block
        //----------------------------------------------------------
        SYS_BRAM_STREAM_TX: begin
          if (tx_ready && !tx_send) begin
            tx_data <= stream_byte_from_block;
            tx_send <= 1'b1;
            if (stream_byte_idx == 4'd15) begin
              // All 16 bytes of this block sent
              stream_addr <= stream_addr + 10'd1;
              if (stream_addr + 10'd1 == TOTAL_BLOCKS) begin
                sys_state <= SYS_DONE;
              end else begin
                stream_rd_pending <= 1'b0;
                sys_state         <= SYS_BRAM_STREAM;
              end
            end else begin
              stream_byte_idx <= stream_byte_idx + 4'd1;
            end
          end
        end

        //----------------------------------------------------------
        // MODE 2: CIPHER_RX — receive ciphertext bytes into BRAM
        // Uses pixel_buffer for 16-byte assembly, writes raw to BRAM
        //----------------------------------------------------------
        SYS_CIPHER_RX: begin
          status_led <= 4'b0010;
          if (pbuf_valid) begin
            // Write raw ciphertext block directly to BRAM (no AES)
            bram_din   <= pbuf_block;
            bram_addr  <= wr_addr;
            bram_wr_en <= 1'b1;
            wr_addr    <= wr_addr + 10'd1;
            if (wr_addr + 10'd1 == TOTAL_BLOCKS) begin
              // All ciphertext received — start decryption
              rd_addr   <= 10'd0;
              sys_state <= SYS_DECRYPT_READ;
            end
            // else stay in SYS_CIPHER_RX for next block
          end
        end

        //----------------------------------------------------------
        // DECRYPT_READ — read ciphertext block from BRAM
        // Used by Mode 2 (after cipher RX) and Mode 4
        //----------------------------------------------------------
        SYS_DECRYPT_READ: begin
          status_led      <= 4'b0010;
          bram_addr       <= rd_addr;
          bram_rd_en      <= 1'b1;
          decrypt_started <= 1'b0;
          sys_state       <= SYS_DECRYPT_WAIT;
        end

        //----------------------------------------------------------
        // DECRYPT_WAIT — start AES decryption, wait for done
        //----------------------------------------------------------
        SYS_DECRYPT_WAIT: begin
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
        // DECRYPT_TX — transmit 16 decrypted bytes over UART
        //----------------------------------------------------------
        SYS_DECRYPT_TX: begin
          if (tx_ready && !tx_send) begin
            tx_data <= tx_byte_from_block;
            tx_send <= 1'b1;
            if (tx_byte_idx == 4'd15) begin
              // All 16 bytes sent, move to next block
              rd_addr <= rd_addr + 10'd1;
              if (rd_addr + 10'd1 == TOTAL_BLOCKS) begin
                sys_state <= SYS_DONE;
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
        // MODE 3: KEY_VERIFY — compare user_key_reg with stored_key_reg
        //----------------------------------------------------------
        SYS_KEY_VERIFY: begin
          if (user_key_reg == stored_key_reg) begin
            // Key matches — stream raw BRAM
            stream_addr      <= 10'd0;
            stream_byte_idx  <= 4'd0;
            stream_rd_pending <= 1'b0;
            status_led       <= 4'b0100;  // LED2 = success
            sys_state        <= SYS_BRAM_STREAM;
          end else begin
            // Key mismatch — send error byte
            status_led <= 4'b1000;  // LED3 = error
            sys_state  <= SYS_ERROR;
          end
        end

        //----------------------------------------------------------
        // MODE 3: ERROR — send single 0xFF byte, return to idle
        //----------------------------------------------------------
        SYS_ERROR: begin
          if (tx_ready && !tx_send) begin
            tx_data   <= 8'hFF;
            tx_send   <= 1'b1;
            sys_state <= SYS_DONE;
          end
        end

        //----------------------------------------------------------
        // DONE — assert LED2, return to IDLE
        //----------------------------------------------------------
        SYS_DONE: begin
          status_led <= 4'b0100;  // LED2 = done
          sys_state  <= SYS_IDLE;
        end

        default: sys_state <= SYS_IDLE;
      endcase
    end
  end

  //----------------------------------------------------------------
  // Seven-Segment Display — show mode number (1–4)
  // Active-low cathodes, active-low anodes (Basys 3)
  //   seg = {CA, CB, CC, CD, CE, CF, CG}
  //   0 = segment ON, 1 = segment OFF
  //----------------------------------------------------------------
  always @(*) begin
    an = 4'b1110;  // only rightmost digit (AN0) active

    case (sys_state)
      SYS_IDLE:
        seg = 7'b1111110;  // dash: only middle segment (G) ON
      default: begin
        case (mode_latch)
          2'b00: seg = 7'b1001111;  // "1" — segments B,C ON
          2'b01: seg = 7'b0010010;  // "2" — segments A,B,D,E,G ON
          2'b10: seg = 7'b0000110;  // "3" — segments A,B,C,D,G ON
          2'b11: seg = 7'b1001100;  // "4" — segments B,C,F,G ON
          default: seg = 7'b1111111;  // all OFF
        endcase
      end
    endcase
  end

endmodule

//======================================================================
// EOF top.v
//======================================================================
