//======================================================================
//
// aes_ctrl.v
// ----------
// FSM controller for the secworks aes_core. Drives key expansion
// and block encryption/decryption with proper ready-handshake.
//
// Interface:
//   - start: pulse to begin processing block_in
//   - mode:  1 = encrypt, 0 = decrypt
//   - key_in[127:0]: AES-128 key (zero-padded to 256 bits internally)
//   - block_in[127:0]: plaintext (encrypt) or ciphertext (decrypt)
//   - block_out[127:0]: result
//   - done: one-cycle pulse when result is valid
//
// Key expansion runs only on the first block. Subsequent blocks
// reuse the expanded key (tracked by key_expanded flag).
//
//======================================================================

`default_nettype none
`timescale 1ns / 1ps

module aes_ctrl(
    input  wire          clk,
    input  wire          rst,
    input  wire [127:0]  key_in,
    input  wire [127:0]  block_in,
    input  wire          mode,       // 1=encrypt, 0=decrypt
    input  wire          start,
    output reg  [127:0]  block_out,
    output reg           done
);

  //----------------------------------------------------------------
  // FSM State Encoding
  //----------------------------------------------------------------
  localparam S_IDLE             = 4'd0;
  localparam S_KEY_INIT         = 4'd1;
  localparam S_WAIT_KEY_LOW     = 4'd2;
  localparam S_WAIT_KEY_HIGH    = 4'd3;
  localparam S_BLOCK_NEXT       = 4'd4;
  localparam S_WAIT_BLOCK_LOW   = 4'd5;
  localparam S_WAIT_BLOCK_HIGH  = 4'd6;
  localparam S_DONE             = 4'd7;

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  reg [3:0]   state;
  reg         key_expanded;    // flag: key expansion already done
  reg         core_init;
  reg         core_next;
  reg [127:0] block_reg;
  reg         mode_reg;

  //----------------------------------------------------------------
  // AES core instance — driven directly (not through aes.v wrapper)
  //----------------------------------------------------------------
  wire        core_ready;
  wire [127:0] core_result;
  wire        core_result_valid;

  aes_core aes_inst(
    .clk          (clk),
    .reset_n      (~rst),         // secworks uses active-low reset
    .encdec       (mode_reg),     // 1=encipher, 0=decipher
    .init         (core_init),
    .next         (core_next),
    .ready        (core_ready),
    .key          ({key_in, 128'd0}),  // AES-128: upper 128 bits, lower 128 zeroed
    .keylen       (1'b0),         // 0 = AES-128
    .block        (block_reg),
    .result       (core_result),
    .result_valid (core_result_valid)
  );

  //----------------------------------------------------------------
  // FSM
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      state        <= S_IDLE;
      key_expanded <= 1'b0;
      core_init    <= 1'b0;
      core_next    <= 1'b0;
      block_reg    <= 128'd0;
      block_out    <= 128'd0;
      mode_reg     <= 1'b1;
      done         <= 1'b0;
    end else begin
      // Defaults — pulses last one clock cycle
      core_init <= 1'b0;
      core_next <= 1'b0;
      done      <= 1'b0;

      case (state)
        //----------------------------------------------------------
        // IDLE: wait for start
        //----------------------------------------------------------
        S_IDLE: begin
          if (start) begin
            block_reg <= block_in;
            mode_reg  <= mode;
            if (!key_expanded)
              state <= S_KEY_INIT;
            else
              state <= S_BLOCK_NEXT;
          end
        end

        //----------------------------------------------------------
        // KEY_INIT: pulse init for one cycle
        //----------------------------------------------------------
        S_KEY_INIT: begin
          core_init <= 1'b1;
          state     <= S_WAIT_KEY_LOW;
        end

        //----------------------------------------------------------
        // WAIT_KEY_LOW: wait for ready to go low (key expansion started)
        //----------------------------------------------------------
        S_WAIT_KEY_LOW: begin
          if (!core_ready)
            state <= S_WAIT_KEY_HIGH;
        end

        //----------------------------------------------------------
        // WAIT_KEY_HIGH: wait for ready to go high (key expansion done)
        //----------------------------------------------------------
        S_WAIT_KEY_HIGH: begin
          if (core_ready) begin
            key_expanded <= 1'b1;
            state        <= S_BLOCK_NEXT;
          end
        end

        //----------------------------------------------------------
        // BLOCK_NEXT: pulse next for one cycle to start block processing
        //----------------------------------------------------------
        S_BLOCK_NEXT: begin
          core_next <= 1'b1;
          state     <= S_WAIT_BLOCK_LOW;
        end

        //----------------------------------------------------------
        // WAIT_BLOCK_LOW: wait for ready to go low (block processing started)
        //----------------------------------------------------------
        S_WAIT_BLOCK_LOW: begin
          if (!core_ready)
            state <= S_WAIT_BLOCK_HIGH;
        end

        //----------------------------------------------------------
        // WAIT_BLOCK_HIGH: wait for ready to go high (block done)
        //----------------------------------------------------------
        S_WAIT_BLOCK_HIGH: begin
          if (core_ready) begin
            block_out <= core_result;
            state     <= S_DONE;
          end
        end

        //----------------------------------------------------------
        // DONE: assert done for one cycle, return to IDLE
        //----------------------------------------------------------
        S_DONE: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule

//======================================================================
// EOF aes_ctrl.v
//======================================================================
