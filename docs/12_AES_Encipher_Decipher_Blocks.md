# Chapter 12: AES Encipher and Decipher Blocks (`aes_encipher_block.v`, `aes_decipher_block.v`, `aes_core.v`)

> **Previous:** [Chapter 11 -- AES Key Memory](11_AES_Key_Memory_aes_key_mem.md)

---

## 1. What This Chapter Covers

In this chapter you will learn:

- How the encipher block transforms 128 bits of plaintext into ciphertext.
- How the decipher block reverses the process.
- The Galois Field multiplication functions (`gm2`, `gm3`, `gm09`, `gm11`, `gm13`, `gm14`) with code and numerical examples.
- The critical design decision of **word-serial SubBytes** (4 clock cycles per SubBytes using the shared S-Box).
- The 4-state FSMs in both encipher and decipher blocks.
- The ShiftRows, MixColumns, InvShiftRows, and InvMixColumns functions in Verilog.
- How `aes_core.v` orchestrates everything: the enc/dec mux, shared S-Box muxing, and the top-level FSM.
- The ready/valid handshake protocol.
- Total clock cycle count for one full encryption.

---

## 2. Overview: What the Encipher and Decipher Blocks Do

### Encipher Block (Encryption)

The encipher block takes a 128-bit plaintext block and applies AES encryption rounds:

```
  Plaintext (128 bits)
       |
       v
  +-- Initial Round --+    AddRoundKey with round_key[0]
  |                    |
  +-- Round 1 ---------+    SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
  +-- Round 2 ---------+    SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
  ...
  +-- Round 9 ---------+    SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
  +-- Round 10 (final)-+    SubBytes -> ShiftRows -> AddRoundKey  (NO MixColumns!)
  |                    |
       v
  Ciphertext (128 bits)
```

### Decipher Block (Decryption)

The decipher block reverses the process, applying inverse operations in reverse order:

```
  Ciphertext (128 bits)
       |
       v
  +-- Initial Round --+    AddRoundKey with round_key[10] -> InvShiftRows
  |                    |
  +-- Round 9 ---------+    InvSubBytes -> AddRoundKey -> InvMixColumns -> InvShiftRows
  +-- Round 8 ---------+    InvSubBytes -> AddRoundKey -> InvMixColumns -> InvShiftRows
  ...
  +-- Round 1 ---------+    InvSubBytes -> AddRoundKey -> InvMixColumns -> InvShiftRows
  +-- Round 0 (final)--+    InvSubBytes -> AddRoundKey  (NO InvMixColumns!)
  |                    |
       v
  Plaintext (128 bits)
```

---

## 3. Module Interfaces

### 3.1 Encipher Block Interface

```verilog
module aes_encipher_block(
                          input wire            clk,
                          input wire            reset_n,

                          input wire            next,

                          input wire            keylen,
                          output wire [3 : 0]   round,
                          input wire [127 : 0]  round_key,

                          output wire [31 : 0]  sboxw,
                          input wire  [31 : 0]  new_sboxw,

                          input wire [127 : 0]  block,
                          output wire [127 : 0] new_block,
                          output wire           ready
                         );
```

| Port        | Dir    | Width   | Purpose                                               |
|-------------|--------|---------|--------------------------------------------------------|
| `clk`       | input  | 1 bit   | System clock                                           |
| `reset_n`   | input  | 1 bit   | Active-low asynchronous reset                          |
| `next`      | input  | 1 bit   | Pulse high to start encrypting the block               |
| `keylen`    | input  | 1 bit   | 0 = AES-128, 1 = AES-256                              |
| `round`     | output | 4 bits  | Current round number (sent to key_mem for key lookup)  |
| `round_key` | input  | 128 bits| The round key for the current round                    |
| `sboxw`     | output | 32 bits | 32-bit word sent to the shared S-Box                   |
| `new_sboxw` | input  | 32 bits | S-Box result coming back                               |
| `block`     | input  | 128 bits| The plaintext block to encrypt                         |
| `new_block` | output | 128 bits| The encrypted ciphertext result                        |
| `ready`     | output | 1 bit   | High when encryption is complete                       |

### 3.2 Decipher Block Interface

```verilog
module aes_decipher_block(
                          input wire            clk,
                          input wire            reset_n,

                          input wire            next,

                          input wire            keylen,
                          output wire [3 : 0]   round,
                          input wire [127 : 0]  round_key,

                          input wire [127 : 0]  block,
                          output wire [127 : 0] new_block,
                          output wire           ready
                         );
```

Notice the decipher block has **no `sboxw`/`new_sboxw` ports**. This is because it instantiates its own private inverse S-Box internally:

```verilog
// Inside aes_decipher_block.v:
aes_inv_sbox inv_sbox_inst(.sboxw(tmp_sboxw), .new_sboxw(new_sboxw));
```

---

## 4. Galois Field Multiplication Functions

AES MixColumns and InvMixColumns require multiplying bytes in the Galois Field GF(2^8). This is NOT normal integer multiplication -- it is polynomial multiplication modulo an irreducible polynomial.

### 4.1 The `gm2` Function -- Multiply by 2 in GF(2^8)

This function appears in both the encipher and decipher blocks:

```verilog
function automatic [7 : 0] gm2(input [7 : 0] op);
  begin
    gm2 = {op[6 : 0], 1'b0} ^ (8'h1b & {8{op[7]}});
  end
endfunction
```

**How it works step by step:**

1. `{op[6 : 0], 1'b0}` -- Shift the byte left by 1 bit (the MSB falls off, a 0 enters at the right).
2. `{8{op[7]}}` -- Replicate bit 7 (the MSB) eight times. If MSB was 1, this is `0xFF`; if 0, this is `0x00`.
3. `8'h1b & {8{op[7]}}` -- AND with 0x1b. Result: 0x1b if MSB was 1, 0x00 if MSB was 0.
4. XOR the shifted value with the conditional 0x1b. This is the "reduction" step from the AES polynomial.

**Numerical Example: gm2(0xd4)**

```
op = 0xd4 = 1101_0100

Step 1: Shift left:    {op[6:0], 1'b0} = {101_0100, 0} = 1010_1000 = 0xa8
Step 2: MSB check:     op[7] = 1, so {8{1}} = 0xFF
Step 3: AND with 0x1b: 0x1b & 0xFF = 0x1b
Step 4: XOR:           0xa8 ^ 0x1b = 0xb3

gm2(0xd4) = 0xb3
```

**Numerical Example: gm2(0xe0)**

```
op = 0xe0 = 1110_0000

Step 1: Shift left:    {110_0000, 0} = 1100_0000 = 0xc0
Step 2: MSB check:     op[7] = 1, so mask = 0x1b
Step 3: XOR:           0xc0 ^ 0x1b = 0xdb

gm2(0xe0) = 0xdb
```

### 4.2 The `gm3` Function -- Multiply by 3 in GF(2^8)

```verilog
function automatic [7 : 0] gm3(input [7 : 0] op);
  begin
    gm3 = gm2(op) ^ op;
  end
endfunction
```

Multiply by 3 = multiply by 2, then XOR with the original (because 3 = 2 + 1 in GF(2^8), and "addition" is XOR).

**Numerical Example: gm3(0xd4)**

```
gm2(0xd4) = 0xb3 (computed above)
gm3(0xd4) = 0xb3 ^ 0xd4 = 0x67
```

### 4.3 Decipher-Only Functions: `gm4`, `gm8`, `gm09`, `gm11`, `gm13`, `gm14`

The inverse MixColumns needs multiplication by 9, 11, 13, and 14. These are built from `gm2`:

```verilog
function automatic [7 : 0] gm4(input [7 : 0] op);
  begin
    gm4 = gm2(gm2(op));       // 4 = 2 * 2
  end
endfunction

function automatic [7 : 0] gm8(input [7 : 0] op);
  begin
    gm8 = gm2(gm4(op));       // 8 = 2 * 4
  end
endfunction

function automatic [7 : 0] gm09(input [7 : 0] op);
  begin
    gm09 = gm8(op) ^ op;      // 9 = 8 + 1
  end
endfunction

function automatic [7 : 0] gm11(input [7 : 0] op);
  begin
    gm11 = gm8(op) ^ gm2(op) ^ op;    // 11 = 8 + 2 + 1
  end
endfunction

function automatic [7 : 0] gm13(input [7 : 0] op);
  begin
    gm13 = gm8(op) ^ gm4(op) ^ op;    // 13 = 8 + 4 + 1
  end
endfunction

function automatic [7 : 0] gm14(input [7 : 0] op);
  begin
    gm14 = gm8(op) ^ gm4(op) ^ gm2(op);   // 14 = 8 + 4 + 2
  end
endfunction
```

The pattern is clear: each number is decomposed into powers of 2, and the corresponding `gm` functions are XORed together. This works because in GF(2^8), addition is XOR.

```
  Decomposition into powers of 2:
   9 = 8 + 1         -->  gm8 ^ op
  11 = 8 + 2 + 1     -->  gm8 ^ gm2 ^ op
  13 = 8 + 4 + 1     -->  gm8 ^ gm4 ^ op
  14 = 8 + 4 + 2     -->  gm8 ^ gm4 ^ gm2
```

**Numerical Example: gm09(0xd4)**

```
gm2(0xd4) = 0xb3
gm4(0xd4) = gm2(0xb3)
  0xb3 = 1011_0011, MSB=1
  shift: 0110_0110 = 0x66
  XOR 0x1b: 0x66 ^ 0x1b = 0x7d
  gm4(0xd4) = 0x7d

gm8(0xd4) = gm2(0x7d)
  0x7d = 0111_1101, MSB=0
  shift: 1111_1010 = 0xfa
  no XOR needed (MSB was 0)
  gm8(0xd4) = 0xfa

gm09(0xd4) = gm8(0xd4) ^ 0xd4 = 0xfa ^ 0xd4 = 0x2e
```

---

## 5. ShiftRows and InvShiftRows

### 5.1 ShiftRows (Encryption)

ShiftRows cyclically shifts bytes in each row of the AES state matrix. The state is arranged as a 4x4 matrix of bytes:

```
  AES state as a 4x4 matrix (column-major order):
  +----+----+----+----+
  | s0 | s4 | s8 | s12|   Row 0: no shift
  | s1 | s5 | s9 | s13|   Row 1: shift left by 1
  | s2 | s6 | s10| s14|   Row 2: shift left by 2
  | s3 | s7 | s11| s15|   Row 3: shift left by 3
  +----+----+----+----+
```

In this Verilog implementation, the 128-bit block is stored as four 32-bit **column** words:

```verilog
function automatic [127 : 0] shiftrows(input [127 : 0] data);
  reg [31 : 0] w0, w1, w2, w3;
  reg [31 : 0] ws0, ws1, ws2, ws3;
  begin
    w0 = data[127 : 096];    // Column 0
    w1 = data[095 : 064];    // Column 1
    w2 = data[063 : 032];    // Column 2
    w3 = data[031 : 000];    // Column 3

    ws0 = {w0[31 : 24], w1[23 : 16], w2[15 : 08], w3[07 : 00]};
    ws1 = {w1[31 : 24], w2[23 : 16], w3[15 : 08], w0[07 : 00]};
    ws2 = {w2[31 : 24], w3[23 : 16], w0[15 : 08], w1[07 : 00]};
    ws3 = {w3[31 : 24], w0[23 : 16], w1[15 : 08], w2[07 : 00]};

    shiftrows = {ws0, ws1, ws2, ws3};
  end
endfunction
```

**How to read the byte selection:**

Each column word has 4 bytes at positions [31:24], [23:16], [15:08], [07:00], corresponding to rows 0, 1, 2, 3. The ShiftRows operation rearranges which column each row's byte comes from:

```
  Before ShiftRows:                    After ShiftRows:
  Col:    w0      w1      w2      w3   Col:    ws0     ws1     ws2     ws3

  Row 0: w0[31:24] w1[31:24] ...      Row 0: w0[31:24] w1[31:24] w2[31:24] w3[31:24]
         (no shift -- row 0 bytes stay in their original columns)

  Row 1: w0[23:16] w1[23:16] ...      Row 1: w1[23:16] w2[23:16] w3[23:16] w0[23:16]
         (shifted left by 1 -- each byte moves one column left)

  Row 2: w0[15:08] w1[15:08] ...      Row 2: w2[15:08] w3[15:08] w0[15:08] w1[15:08]
         (shifted left by 2)

  Row 3: w0[07:00] w1[07:00] ...      Row 3: w3[07:00] w0[07:00] w1[07:00] w2[07:00]
         (shifted left by 3)
```

This is purely a **rewiring** operation -- no computation, no gates, just connecting different bytes to different positions. In hardware, this costs essentially nothing (just wires).

### 5.2 InvShiftRows (Decryption)

```verilog
function automatic [127 : 0] inv_shiftrows(input [127 : 0] data);
  reg [31 : 0] w0, w1, w2, w3;
  reg [31 : 0] ws0, ws1, ws2, ws3;
  begin
    w0 = data[127 : 096];
    w1 = data[095 : 064];
    w2 = data[063 : 032];
    w3 = data[031 : 000];

    ws0 = {w0[31 : 24], w3[23 : 16], w2[15 : 08], w1[07 : 00]};
    ws1 = {w1[31 : 24], w0[23 : 16], w3[15 : 08], w2[07 : 00]};
    ws2 = {w2[31 : 24], w1[23 : 16], w0[15 : 08], w3[07 : 00]};
    ws3 = {w3[31 : 24], w2[23 : 16], w1[15 : 08], w0[07 : 00]};

    inv_shiftrows = {ws0, ws1, ws2, ws3};
  end
endfunction
```

This shifts rows to the **right** instead of the left, undoing the forward ShiftRows:

```
  Row 0: no shift     (same as forward)
  Row 1: shift RIGHT by 1  (undo left-by-1)
  Row 2: shift RIGHT by 2  (undo left-by-2)
  Row 3: shift RIGHT by 3  (undo left-by-3)
```

---

## 6. MixColumns and InvMixColumns

### 6.1 MixColumns (Encryption)

MixColumns treats each column of 4 bytes as a polynomial and multiplies it by a fixed polynomial. The `mixw` function processes one 32-bit column:

```verilog
function automatic [31 : 0] mixw(input [31 : 0] w);
  reg [7 : 0] b0, b1, b2, b3;
  reg [7 : 0] mb0, mb1, mb2, mb3;
  begin
    b0 = w[31 : 24];
    b1 = w[23 : 16];
    b2 = w[15 : 08];
    b3 = w[07 : 00];

    mb0 = gm2(b0) ^ gm3(b1) ^ b2      ^ b3;
    mb1 = b0      ^ gm2(b1) ^ gm3(b2) ^ b3;
    mb2 = b0      ^ b1      ^ gm2(b2) ^ gm3(b3);
    mb3 = gm3(b0) ^ b1      ^ b2      ^ gm2(b3);

    mixw = {mb0, mb1, mb2, mb3};
  end
endfunction
```

This implements the matrix multiplication in GF(2^8):

```
  | mb0 |   | 2  3  1  1 |   | b0 |
  | mb1 | = | 1  2  3  1 | * | b1 |
  | mb2 |   | 1  1  2  3 |   | b2 |
  | mb3 |   | 3  1  1  2 |   | b3 |
```

Where multiplication is `gm2`/`gm3` and addition is XOR.

The `mixcolumns` function applies `mixw` to all four columns:

```verilog
function automatic [127 : 0] mixcolumns(input [127 : 0] data);
  reg [31 : 0] w0, w1, w2, w3;
  reg [31 : 0] ws0, ws1, ws2, ws3;
  begin
    w0 = data[127 : 096];
    w1 = data[095 : 064];
    w2 = data[063 : 032];
    w3 = data[031 : 000];

    ws0 = mixw(w0);
    ws1 = mixw(w1);
    ws2 = mixw(w2);
    ws3 = mixw(w3);

    mixcolumns = {ws0, ws1, ws2, ws3};
  end
endfunction
```

### 6.2 InvMixColumns (Decryption)

The inverse uses the larger multiplication factors (9, 11, 13, 14):

```verilog
function automatic [31 : 0] inv_mixw(input [31 : 0] w);
  reg [7 : 0] b0, b1, b2, b3;
  reg [7 : 0] mb0, mb1, mb2, mb3;
  begin
    b0 = w[31 : 24];
    b1 = w[23 : 16];
    b2 = w[15 : 08];
    b3 = w[07 : 00];

    mb0 = gm14(b0) ^ gm11(b1) ^ gm13(b2) ^ gm09(b3);
    mb1 = gm09(b0) ^ gm14(b1) ^ gm11(b2) ^ gm13(b3);
    mb2 = gm13(b0) ^ gm09(b1) ^ gm14(b2) ^ gm11(b3);
    mb3 = gm11(b0) ^ gm13(b1) ^ gm09(b2) ^ gm14(b3);

    inv_mixw = {mb0, mb1, mb2, mb3};
  end
endfunction
```

This implements the inverse matrix:

```
  | mb0 |   | 14  11  13   9 |   | b0 |
  | mb1 | = |  9  14  11  13 | * | b1 |
  | mb2 |   | 13   9  14  11 |   | b2 |
  | mb3 |   | 11  13   9  14 |   | b3 |
```

The inverse matrix is more complex because it must undo the forward MixColumns. This is why InvMixColumns requires `gm09`, `gm11`, `gm13`, and `gm14` -- four multiplication functions instead of just two.

---

## 7. Word-Serial SubBytes -- A Critical Design Decision

### 7.1 The Problem

SubBytes needs to pass every byte of the 128-bit block through the S-Box. That is 16 bytes. The S-Box module processes 4 bytes (one 32-bit word) per call. So a full SubBytes requires **4 calls** to the S-Box.

But there is only **one shared S-Box** (in `aes_core`). The encipher block cannot use it 4 times simultaneously -- it must use it sequentially, one word at a time.

### 7.2 The Solution: `sword_ctr` (S-Box Word Counter)

The encipher block has a 2-bit counter called `sword_ctr_reg` that cycles through the four 32-bit words of the block:

```
  128-bit block stored as four 32-bit word registers:
  +-------------+-------------+-------------+-------------+
  | block_w0_reg| block_w1_reg| block_w2_reg| block_w3_reg|
  +------+------+------+------+------+------+------+------+
         |             |             |             |
  sword_ctr = 0   sword_ctr = 1   sword_ctr = 2   sword_ctr = 3
```

Each clock cycle during the SBOX state, one word is sent to the S-Box and the result is written back:

```verilog
SBOX_UPDATE:
  begin
    block_new = {new_sboxw, new_sboxw, new_sboxw, new_sboxw};

    case (sword_ctr_reg)
      2'h0:
        begin
          muxed_sboxw = block_w0_reg;   // Send word 0 to S-Box
          block_w0_we = 1'b1;           // Write S-Box result to word 0
        end

      2'h1:
        begin
          muxed_sboxw = block_w1_reg;   // Send word 1 to S-Box
          block_w1_we = 1'b1;           // Write S-Box result to word 1
        end

      2'h2:
        begin
          muxed_sboxw = block_w2_reg;   // Send word 2 to S-Box
          block_w2_we = 1'b1;           // Write S-Box result to word 2
        end

      2'h3:
        begin
          muxed_sboxw = block_w3_reg;   // Send word 3 to S-Box
          block_w3_we = 1'b1;           // Write S-Box result to word 3
        end
    endcase
  end
```

**Why `block_new = {new_sboxw, new_sboxw, new_sboxw, new_sboxw}`?**

The S-Box output (`new_sboxw`) is replicated to all four positions of `block_new`, but only **one** word's write-enable is active. The other three words are not affected because their `block_wX_we` signals are 0. This is a common Verilog trick -- broadcast the data everywhere but only enable the write where you want it.

### 7.3 Timing Diagram for One SubBytes Operation

```
  Clock cycle:     |  C0  |  C1  |  C2  |  C3  |  C4  |
  sword_ctr:       |   0  |   1  |   2  |   3  |   0  |
  S-Box input:     | w0   | w1   | w2   | w3   |  --  |
  S-Box output:    |S(w0) |S(w1) |S(w2) |S(w3) |  --  |
  Write:           |w0_we |w1_we |w2_we |w3_we |  --  |
  State:           | SBOX | SBOX | SBOX | SBOX | MAIN |
```

SubBytes takes **4 clock cycles** (one per word). This is slower than having 4 parallel S-Boxes, but it saves significant FPGA area by reusing one S-Box.

The decipher block uses the exact same approach, but with its private `aes_inv_sbox` instance instead of the shared forward S-Box.

---

## 8. The Encipher FSM: CTRL_IDLE -> CTRL_INIT -> CTRL_SBOX -> CTRL_MAIN

### 8.1 State Definitions

```verilog
localparam CTRL_IDLE  = 2'h0;
localparam CTRL_INIT  = 2'h1;
localparam CTRL_SBOX  = 2'h2;
localparam CTRL_MAIN  = 2'h3;
```

### 8.2 State Diagram

```
                        next=1
            +------+-----------+------+
            |      |           |      |
            | CTRL_IDLE       v      |
            | (waiting)   CTRL_INIT  |
            |      ^      (AddRoundKey|
            |      |       with key 0)|
            |      |           |      |
            |  CTRL_MAIN       v      |
            |  (ShiftRows  CTRL_SBOX  |<--+
            |   MixColumns (SubBytes  |   |
            |   AddRoundKey  1 word   |   |
            |   -or-         per clk) |   |
            |   Final round)     |    |   |
            |      ^             |    |   |
            |      +----<--------+    |   |
            |     sword_ctr==3        |   |
            |      |                  |   |
            |      +-------->---------+   |
            |     round < num_rounds      |
            +-----------------------------+
```

### 8.3 State-by-State Walkthrough

**CTRL_IDLE:**
```verilog
CTRL_IDLE:
  begin
    if (next)
      begin
        round_ctr_rst = 1'b1;     // Reset round counter to 0
        ready_new     = 1'b0;     // Not ready (encryption starting)
        ready_we      = 1'b1;
        enc_ctrl_new  = CTRL_INIT;
        enc_ctrl_we   = 1'b1;
      end
  end
```
- Waits for the `next` signal.
- Resets the round counter and transitions to CTRL_INIT.

**CTRL_INIT:**
```verilog
CTRL_INIT:
  begin
    round_ctr_inc = 1'b1;         // Increment round counter (0 -> 1)
    sword_ctr_rst = 1'b1;         // Reset SubBytes word counter
    update_type   = INIT_UPDATE;  // Perform: block XOR round_key[0]
    enc_ctrl_new  = CTRL_SBOX;
    enc_ctrl_we   = 1'b1;
  end
```
- Performs the initial AddRoundKey: `block_new = block ^ round_key` (with round counter at 0, so round_key[0]).
- Increments round counter to 1.
- Transitions to CTRL_SBOX.

**CTRL_SBOX:**
```verilog
CTRL_SBOX:
  begin
    sword_ctr_inc = 1'b1;         // Increment word counter
    update_type   = SBOX_UPDATE;  // SubBytes one word
    if (sword_ctr_reg == 2'h3)
      begin
        enc_ctrl_new  = CTRL_MAIN;   // All 4 words done
        enc_ctrl_we   = 1'b1;
      end
  end
```
- Each cycle: sends one word to the S-Box and writes back the result.
- After 4 cycles (sword_ctr goes 0,1,2,3), transitions to CTRL_MAIN.

**CTRL_MAIN:**
```verilog
CTRL_MAIN:
  begin
    sword_ctr_rst = 1'b1;         // Reset word counter for next SubBytes
    round_ctr_inc = 1'b1;         // Increment round counter
    if (round_ctr_reg < num_rounds)
      begin
        update_type   = MAIN_UPDATE;   // ShiftRows + MixColumns + AddRoundKey
        enc_ctrl_new  = CTRL_SBOX;     // Go back for next round's SubBytes
        enc_ctrl_we   = 1'b1;
      end
    else
      begin
        update_type  = FINAL_UPDATE;   // ShiftRows + AddRoundKey (no MixColumns)
        ready_new    = 1'b1;           // Done!
        ready_we     = 1'b1;
        enc_ctrl_new = CTRL_IDLE;
        enc_ctrl_we  = 1'b1;
      end
  end
```
- If more rounds remain: applies ShiftRows + MixColumns + AddRoundKey (MAIN_UPDATE), then goes back to CTRL_SBOX.
- If this is the last round: applies ShiftRows + AddRoundKey only (FINAL_UPDATE, no MixColumns), signals ready, and returns to IDLE.

### 8.4 The Round Logic -- Update Types

The `round_logic` combinational block produces different outputs depending on `update_type`:

```verilog
// Precomputed values (always available):
old_block          = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
shiftrows_block    = shiftrows(old_block);
mixcolumns_block   = mixcolumns(shiftrows_block);
addkey_init_block  = addroundkey(block, round_key);
addkey_main_block  = addroundkey(mixcolumns_block, round_key);
addkey_final_block = addroundkey(shiftrows_block, round_key);
```

| Update Type    | Operation                                              | Used When           |
|----------------|--------------------------------------------------------|---------------------|
| `INIT_UPDATE`  | `block XOR round_key[0]`                               | Initial round       |
| `SBOX_UPDATE`  | One word through S-Box                                 | SubBytes (4 cycles) |
| `MAIN_UPDATE`  | `ShiftRows -> MixColumns -> AddRoundKey`               | Rounds 1 to N-1     |
| `FINAL_UPDATE` | `ShiftRows -> AddRoundKey` (no MixColumns)             | Last round          |

---

## 9. The Decipher FSM

The decipher block has the same 4-state structure but with key differences:

### 9.1 Round Counter Counts DOWN

Unlike the encipher block (which counts 0, 1, 2, ..., 10), the decipher block **starts at the maximum** and counts down:

```verilog
// Round counter initialization (in CTRL_IDLE):
if (next)
  begin
    round_ctr_set = 1'b1;    // Set to num_rounds (10 for AES-128)
    ...
  end

// Round counter decrement (in round_ctr logic):
if (round_ctr_set)
  begin
    if (keylen == AES_256_BIT_KEY)
      round_ctr_new = AES256_ROUNDS;    // 14
    else
      round_ctr_new = AES128_ROUNDS;    // 10
    round_ctr_we  = 1'b1;
  end
else if (round_ctr_dec)
  begin
    round_ctr_new = round_ctr_reg - 1'b1;   // Decrement
    round_ctr_we  = 1'b1;
  end
```

This is because decryption uses round keys in **reverse order**: key[10] first, then key[9], key[8], ..., key[0].

### 9.2 Different Operation Order

The decipher's round logic applies operations in the inverse order:

```verilog
// INIT_UPDATE (decryption):
old_block           = block;
addkey_block        = addroundkey(old_block, round_key);     // AddRoundKey first
inv_shiftrows_block = inv_shiftrows(addkey_block);           // Then InvShiftRows
block_new           = inv_shiftrows_block;

// MAIN_UPDATE (decryption):
addkey_block         = addroundkey(old_block, round_key);    // AddRoundKey
inv_mixcolumns_block = inv_mixcolumns(addkey_block);         // InvMixColumns
inv_shiftrows_block  = inv_shiftrows(inv_mixcolumns_block);  // InvShiftRows
block_new            = inv_shiftrows_block;

// FINAL_UPDATE (decryption):
block_new = addroundkey(old_block, round_key);               // Just AddRoundKey
```

### 9.3 Exit Condition

The decipher FSM exits when `round_ctr_reg > 0` becomes false (counter reaches 0):

```verilog
CTRL_MAIN:
  begin
    sword_ctr_rst = 1'b1;
    if (round_ctr_reg > 0)
      begin
        update_type   = MAIN_UPDATE;
        dec_ctrl_new  = CTRL_SBOX;     // More rounds to go
        dec_ctrl_we   = 1'b1;
      end
    else
      begin
        update_type  = FINAL_UPDATE;    // Last round
        ready_new    = 1'b1;
        ready_we     = 1'b1;
        dec_ctrl_new = CTRL_IDLE;
        dec_ctrl_we  = 1'b1;
      end
  end
```

---

## 10. `aes_core.v` -- The Orchestrator

The `aes_core` module ties everything together. It instantiates and connects all submodules.

### 10.1 Module Instantiations

```verilog
// Encipher datapath
aes_encipher_block enc_block(
    .clk(clk), .reset_n(reset_n),
    .next(enc_next),
    .keylen(keylen), .round(enc_round_nr), .round_key(round_key),
    .sboxw(enc_sboxw), .new_sboxw(new_sboxw),
    .block(block), .new_block(enc_new_block), .ready(enc_ready)
);

// Decipher datapath
aes_decipher_block dec_block(
    .clk(clk), .reset_n(reset_n),
    .next(dec_next),
    .keylen(keylen), .round(dec_round_nr), .round_key(round_key),
    .block(block), .new_block(dec_new_block), .ready(dec_ready)
);

// Key memory (shared)
aes_key_mem keymem(
    .clk(clk), .reset_n(reset_n),
    .key(key), .keylen(keylen), .init(init),
    .round(muxed_round_nr), .round_key(round_key), .ready(key_ready),
    .sboxw(keymem_sboxw), .new_sboxw(new_sboxw)
);

// Shared S-Box (single instance for the entire core)
aes_sbox sbox_inst(.sboxw(muxed_sboxw), .new_sboxw(new_sboxw));
```

### 10.2 System Block Diagram

```
  +====================================================================+
  |                          aes_core                                   |
  |                                                                     |
  |   +-------------------+                                             |
  |   |   aes_key_mem     |----sboxw---->+                              |
  |   |   (key expansion) |<--new_sboxw--+                              |
  |   +--------+----------+             |                              |
  |            |                   +----v----+                          |
  |       round_key               |  S-Box   |                          |
  |            |                   |   MUX    |----->+----------+       |
  |            v                   +----^----+      | aes_sbox |       |
  |   +-----------------+              |           | (shared) |       |
  |   |  Round Nr MUX   |         +----+           +----+-----+       |
  |   |  (enc or dec    |         |                     |              |
  |   |   round number) |   enc_sboxw              new_sboxw          |
  |   +--------+--------+         |                     |              |
  |            |             +----+-----+               |              |
  |            v             |aes_enc   |<--------------+              |
  |       round_key-------->|ipher_blk |                               |
  |                          +-+--------+                               |
  |                            |enc_new_block                           |
  |   +--encdec MUX-----------+--+                                     |
  |   |                           |                                     |
  |   |  +---+---------+         |                                     |
  |   +->|aes_decipher |         |                                     |
  |      |_block       |         |                                     |
  |      | (has own    |         |                                     |
  |      |  inv_sbox)  |         |                                     |
  |      +---+---------+         |                                     |
  |          |dec_new_block      |                                     |
  |          |                   |                                     |
  |   +------v-------------------v------+                               |
  |   |       Result MUX                |                               |
  |   |  (select enc or dec output)     |                               |
  |   +-----------------+---------------+                               |
  |                     |                                               |
  |                     v                                               |
  |                   result (128 bits)                                 |
  +=====================================================================+
```

### 10.3 The Enc/Dec Multiplexer

The `encdec` signal (1 = encrypt, 0 = decrypt) controls which datapath is active:

```verilog
always @*
  begin : encdec_mux
    enc_next = 1'b0;
    dec_next = 1'b0;

    if (encdec)
      begin
        // Encipher operations
        enc_next        = next;             // Route 'next' to encipher
        muxed_round_nr  = enc_round_nr;     // Route encipher's round# to key_mem
        muxed_new_block = enc_new_block;    // Route encipher's output to result
        muxed_ready     = enc_ready;        // Route encipher's ready to core
      end
    else
      begin
        // Decipher operations
        dec_next        = next;             // Route 'next' to decipher
        muxed_round_nr  = dec_round_nr;     // Route decipher's round# to key_mem
        muxed_new_block = dec_new_block;    // Route decipher's output to result
        muxed_ready     = dec_ready;        // Route decipher's ready to core
      end
  end
```

Only one datapath receives the `next` signal at a time. The other sits idle.

### 10.4 The S-Box Multiplexer

```verilog
always @*
  begin : sbox_mux
    if (init_state)
      muxed_sboxw = keymem_sboxw;    // During key expansion
    else
      muxed_sboxw = enc_sboxw;       // During encryption
  end
```

- During key initialization (`init_state` = 1): the key memory drives the S-Box.
- During block encryption (`init_state` = 0): the encipher block drives the S-Box.

The decipher block never needs the shared S-Box because it has its own `aes_inv_sbox`.

---

## 11. The `aes_core` FSM: CTRL_IDLE -> CTRL_INIT -> CTRL_NEXT

### 11.1 State Definitions

```verilog
localparam CTRL_IDLE  = 2'h0;
localparam CTRL_INIT  = 2'h1;
localparam CTRL_NEXT  = 2'h2;
```

### 11.2 State Diagram

```
                init=1              next=1
  +-------+----------+-------+----------+-------+
  |       |          |       |          |       |
  | CTRL_IDLE -----> CTRL_INIT   CTRL_IDLE ----> CTRL_NEXT
  | (ready=1)       (init_state=1)    (ready=1)  (init_state=0)
  |       ^          |       ^          |       |
  |       |    key_ready=1   |          | muxed_ready=1
  |       +----------+       +----------+-------+
  +---------------------------------------------+
```

### 11.3 State-by-State Walkthrough

**CTRL_IDLE:**
```verilog
CTRL_IDLE:
  begin
    if (init)
      begin
        init_state        = 1'b1;        // S-Box goes to key_mem
        ready_new         = 1'b0;        // Core is busy
        ready_we          = 1'b1;
        result_valid_new  = 1'b0;        // No valid result yet
        result_valid_we   = 1'b1;
        aes_core_ctrl_new = CTRL_INIT;   // Go to key init
        aes_core_ctrl_we  = 1'b1;
      end
    else if (next)
      begin
        init_state        = 1'b0;        // S-Box goes to encipher
        ready_new         = 1'b0;        // Core is busy
        ready_we          = 1'b1;
        result_valid_new  = 1'b0;        // No valid result yet
        result_valid_we   = 1'b1;
        aes_core_ctrl_new = CTRL_NEXT;   // Go to enc/dec
        aes_core_ctrl_we  = 1'b1;
      end
  end
```

Two possible transitions from IDLE:
- `init` = 1: Begin key expansion (CTRL_INIT).
- `next` = 1: Begin encrypting/decrypting a block (CTRL_NEXT).

**CTRL_INIT:**
```verilog
CTRL_INIT:
  begin
    init_state = 1'b1;                   // Keep S-Box routed to key_mem

    if (key_ready)
      begin
        ready_new         = 1'b1;        // Key expansion done
        ready_we          = 1'b1;
        aes_core_ctrl_new = CTRL_IDLE;   // Return to idle
        aes_core_ctrl_we  = 1'b1;
      end
  end
```

Waits for the key memory to finish generating all round keys. The `init_state` flag keeps the S-Box routed to the key memory during this entire phase.

**CTRL_NEXT:**
```verilog
CTRL_NEXT:
  begin
    init_state = 1'b0;                   // S-Box goes to encipher

    if (muxed_ready)
      begin
        ready_new         = 1'b1;        // Enc/dec done
        ready_we          = 1'b1;
        result_valid_new  = 1'b1;        // Result is valid
        result_valid_we   = 1'b1;
        aes_core_ctrl_new = CTRL_IDLE;   // Return to idle
        aes_core_ctrl_we  = 1'b1;
      end
  end
```

Waits for the selected datapath (encipher or decipher) to finish. When `muxed_ready` goes high, the result is valid and the core returns to IDLE.

---

## 12. The Ready Signal Handshake

The system that uses `aes_core` follows a simple protocol:

### 12.1 Key Initialization Handshake

```
  Signal:   | clk  | clk  | clk  | ... | clk  | clk  |
  init:     |__^^^^|______|______|     |______|______|
  ready:    |^^^^^^|______|______|     |______| ^^^^^|
  key_ready:|______|______|______|     |__^^^^|______|

  Step 1: User checks ready=1, then pulses init=1 for one clock.
  Step 2: Core sets ready=0 (busy with key expansion).
  Step 3: After ~13 clocks (AES-128), key_ready goes high.
  Step 4: Core sets ready=1 (key expansion complete).
```

### 12.2 Block Encryption Handshake

```
  Signal:       | clk  | clk  | ... | clk  | clk  |
  next:         |__^^^^|______|     |______|______|
  ready:        |^^^^^^|______|     |______| ^^^^^|
  result_valid: |______|______|     |______| ^^^^^|

  Step 1: User checks ready=1, places plaintext on 'block', pulses next=1.
  Step 2: Core sets ready=0 (busy encrypting).
  Step 3: After ~55 clocks (AES-128), encryption completes.
  Step 4: Core sets ready=1, result_valid=1, result = ciphertext.
  Step 5: User reads 'result' while result_valid=1.
```

### 12.3 Full Sequence for Encrypting One Block

```
  Phase 1: Key Init            Phase 2: Encrypt Block
  +------------------------+   +---------------------------+
  | Set key on 'key' port  |   | Set plaintext on 'block'  |
  | Pulse init=1           |   | Set encdec=1 (encrypt)    |
  | Wait for ready=1       |   | Pulse next=1              |
  |                        |   | Wait for ready=1          |
  | (~13 clocks for        |   | Read result               |
  |  AES-128)              |   |                           |
  +------------------------+   | (~55 clocks for AES-128)  |
                                +---------------------------+
```

---

## 13. Timing: How Many Clock Cycles for One Encryption?

### 13.1 Key Expansion (AES-128)

| Phase          | Cycles | Description                              |
|----------------|--------|------------------------------------------|
| CTRL_IDLE      | 1      | Detect `init`, transition                |
| CTRL_INIT      | 1      | Reset round counter                      |
| CTRL_GENERATE  | 11     | Generate round keys 0-10                 |
| CTRL_DONE      | 1      | Signal ready                             |
| **Total**      | **~14**| **Key expansion complete**               |

### 13.2 Block Encryption (AES-128)

Each AES round in the encipher block consists of:
- CTRL_INIT: 1 cycle (initial AddRoundKey, only for round 0)
- CTRL_SBOX: 4 cycles (SubBytes, one word per cycle)
- CTRL_MAIN: 1 cycle (ShiftRows + MixColumns + AddRoundKey)

For AES-128 (10 rounds):

| Phase                           | Cycles | Description                      |
|---------------------------------|--------|----------------------------------|
| CTRL_IDLE                       | 1      | Detect `next`, transition        |
| CTRL_INIT (initial AddRoundKey) | 1      | `block XOR round_key[0]`        |
| Rounds 1-9 (9 rounds):         |        |                                  |
| -- CTRL_SBOX per round          | 4 x 9 = 36 | SubBytes (4 words each)    |
| -- CTRL_MAIN per round          | 1 x 9 = 9  | ShiftRows+MixColumns+AddRK |
| Round 10 (final round):        |        |                                  |
| -- CTRL_SBOX                    | 4      | SubBytes                         |
| -- CTRL_MAIN (final)           | 1      | ShiftRows+AddRoundKey            |
| **Total**                       | **~52**| **One block encrypted**          |

### 13.3 Overall Total for Key Init + One Block

```
  Total = Key expansion + Block encryption
        = ~14 + ~52
        = ~66 clock cycles

  At 100 MHz clock: ~66 * 10 ns = ~660 ns per block (first block with key init)
  Subsequent blocks (no key init needed): ~52 * 10 ns = ~520 ns per block
```

For encrypting an image pixel by pixel (where each pixel block is 128 bits), only the first block pays the key init cost. All subsequent blocks reuse the stored round keys.

### 13.4 Decryption Timing

Decryption has the same structure: 4 cycles for InvSubBytes per round, 1 cycle for InvShiftRows + InvMixColumns + AddRoundKey per round. The total is approximately the same as encryption: **~52 cycles per block** for AES-128.

---

## 14. The Data Block Registers

Both encipher and decipher blocks store the intermediate state as four 32-bit word registers:

```verilog
reg [31 : 0]  block_w0_reg;    // Bits [127:96] of the block
reg [31 : 0]  block_w1_reg;    // Bits [95:64]
reg [31 : 0]  block_w2_reg;    // Bits [63:32]
reg [31 : 0]  block_w3_reg;    // Bits [31:0]
```

The output is the concatenation of all four:

```verilog
assign new_block = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
```

Each word has its own write-enable, allowing the SubBytes step to update one word at a time while leaving the others unchanged.

---

## 15. AddRoundKey -- The Simplest Operation

Both encipher and decipher blocks include this function:

```verilog
function automatic [127 : 0] addroundkey(input [127 : 0] data, input [127 : 0] rkey);
  begin
    addroundkey = data ^ rkey;
  end
endfunction
```

This is just a 128-bit XOR. In hardware, this is 128 parallel XOR gates -- the simplest and cheapest operation in the entire AES pipeline. Despite its simplicity, it is the operation that actually mixes the secret key into the data.

---

## 16. Comparing Encipher vs. Decipher: Side by Side

| Aspect              | Encipher Block                       | Decipher Block                         |
|---------------------|--------------------------------------|----------------------------------------|
| S-Box               | Uses shared `aes_sbox` (in core)     | Has private `aes_inv_sbox` (internal)  |
| S-Box ports         | `sboxw`/`new_sboxw` (external)       | `tmp_sboxw`/`new_sboxw` (internal)    |
| Round counter       | Counts UP (0 to num_rounds)          | Counts DOWN (num_rounds to 0)          |
| SubBytes            | Forward S-Box, 4 cycles              | Inverse S-Box, 4 cycles               |
| ShiftRows           | Left shifts (rows 1,2,3)             | Right shifts (rows 1,2,3)             |
| MixColumns          | Uses gm2, gm3                        | Uses gm09, gm11, gm13, gm14          |
| Round order         | Init -> Sub -> (Shift+Mix+AddKey) x9 -> Sub -> (Shift+AddKey) | Init -> (AddKey+InvShift) -> InvSub -> (AddKey+InvMix+InvShift) x9 -> InvSub -> AddKey |
| FSM states          | IDLE, INIT, SBOX, MAIN               | IDLE, INIT, SBOX, MAIN                |
| GF multiply funcs   | gm2, gm3                             | gm2, gm3, gm4, gm8, gm09, gm11, gm13, gm14 |

---

## 17. Key Takeaways

1. **The encipher block applies SubBytes, ShiftRows, MixColumns, and AddRoundKey** in sequence for each round. The final round skips MixColumns. The decipher block applies the inverse of each operation in reverse order.

2. **Word-serial SubBytes is the key area/speed tradeoff.** By processing one 32-bit word per clock cycle through the shared S-Box, the design uses far less FPGA area than four parallel S-Boxes would require. The cost is 4 clock cycles per SubBytes instead of 1.

3. **Galois Field multiplication is built from `gm2` (xtime).** All higher multiplications (gm3, gm4, gm8, gm09, gm11, gm13, gm14) are compositions of `gm2` and XOR. The core building block is a left-shift plus conditional XOR with 0x1b.

4. **ShiftRows is free in hardware** -- it is purely a rewiring of bytes, requiring no logic gates.

5. **`aes_core.v` is the orchestrator** with a simple 3-state FSM (IDLE, INIT, NEXT). It multiplexes the shared S-Box between key expansion and encryption, and multiplexes the enc/dec datapaths to the output.

6. **The ready/result_valid handshake** is straightforward: wait for `ready=1`, pulse `init` or `next`, wait for `ready=1` again, then read the result.

7. **Total encryption time for AES-128 is approximately 66 clock cycles** for the first block (including key expansion) and approximately 52 cycles for each subsequent block. At 100 MHz, this translates to roughly 520 ns per block, or about 246 Mbps throughput.

---

> **You have completed the AES hardware deep-dive!** You now understand every major module in the AES core: the S-Box substitution tables, the key expansion engine, the encipher and decipher datapaths, and the top-level orchestrator. With this knowledge, you can trace the flow of any byte from plaintext input to ciphertext output and back again.
