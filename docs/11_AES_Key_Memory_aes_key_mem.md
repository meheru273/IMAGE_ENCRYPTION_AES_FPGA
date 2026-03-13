# Chapter 11: AES Key Memory (`aes_key_mem.v`)

> **Previous:** [Chapter 10 -- AES S-Box and Inverse S-Box](10_AES_SBox_and_Inv_SBox.md)
> **Next:** [Chapter 12 -- AES Encipher and Decipher Blocks](12_AES_Encipher_Decipher_Blocks.md)

---

## 1. What This Chapter Covers

In this chapter you will learn:

- What AES key expansion does and why one key is not enough.
- Every port of the `aes_key_mem` module and what it connects to.
- The internal `key_mem` array that stores all round keys.
- The 4-state FSM that controls the key generation process.
- How RotWord and SubWord are implemented using the shared S-Box.
- How the Rcon (round constant) is generated using GF(2^8) doubling.
- A complete numerical example expanding the NIST test key step by step.
- How round keys are accessed during encryption/decryption.
- How the S-Box is time-shared between key expansion and encryption.

---

## 2. Why Key Expansion? Why Not Use the Same Key Every Round?

AES-128 performs **10 rounds** of encryption. If every round used the same 128-bit key, an attacker could exploit patterns across rounds to recover the key more easily. Key expansion solves this by deriving **11 different 128-bit round keys** from the original key (one for the initial AddRoundKey before round 1, and one for each of the 10 rounds).

```
  Original Key (128 bits)
         |
         v
  +-------------------+
  | Key Expansion     |
  | (aes_key_mem)     |
  +-------------------+
         |
         v
  Round Key 0  (= original key, used before round 1)
  Round Key 1  (used in round 1)
  Round Key 2  (used in round 2)
  Round Key 3  (used in round 3)
  ...
  Round Key 9  (used in round 9)
  Round Key 10 (used in round 10, the final round)
```

Each round key is 128 bits (the same width as the data block). The key expansion algorithm is carefully designed so that:

- Changing even 1 bit of the original key changes **every** round key dramatically.
- You cannot easily reverse the process (derive the original key from a round key).
- Each round key looks "random" relative to the others.

---

## 3. Module Interface -- Every Port Explained

```verilog
module aes_key_mem(
                   input wire            clk,
                   input wire            reset_n,

                   input wire [255 : 0]  key,
                   input wire            keylen,
                   input wire            init,

                   input wire    [3 : 0] round,
                   output wire [127 : 0] round_key,
                   output wire           ready,

                   output wire [31 : 0]  sboxw,
                   input wire  [31 : 0]  new_sboxw
                  );
```

Here is what every port does:

| Port         | Dir    | Width   | Purpose                                                       |
|--------------|--------|---------|---------------------------------------------------------------|
| `clk`        | input  | 1 bit   | System clock. All registers update on the rising edge.        |
| `reset_n`    | input  | 1 bit   | Active-low asynchronous reset. When 0, all registers reset.   |
| `key`        | input  | 256 bits| The encryption key. For AES-128, only bits [255:128] are used. For AES-256, all 256 bits are used. |
| `keylen`     | input  | 1 bit   | Key length selector: 0 = AES-128, 1 = AES-256.               |
| `init`       | input  | 1 bit   | Pulse high for 1 clock to start key expansion.                |
| `round`      | input  | 4 bits  | Which round key to read (0-10 for AES-128, 0-14 for AES-256).|
| `round_key`  | output | 128 bits| The round key for the requested `round` number.               |
| `ready`      | output | 1 bit   | High when key expansion is complete and round keys are available.|
| `sboxw`      | output | 32 bits | The 32-bit word that needs S-Box substitution (sent to shared S-Box).|
| `new_sboxw`  | input  | 32 bits | The S-Box result coming back from the shared S-Box module.    |

### Port Connection Diagram

```
                    aes_core.v
  +--------------------------------------------------+
  |                                                    |
  |   key, keylen, init                                |
  |        |                                           |
  |        v                                           |
  |  +-------------+     sboxw      +-----------+     |
  |  | aes_key_mem |-------------->|           |     |
  |  |             |<--------------| aes_sbox  |     |
  |  |             |    new_sboxw  | (shared)  |     |
  |  +------+------+              +-----------+     |
  |         |                          ^             |
  |    round_key                       |             |
  |    ready                       enc_sboxw         |
  |         |                          |             |
  |         v                          |             |
  |  +----------------+     +-------------------+    |
  |  | Round key read |     | aes_encipher_block|    |
  |  | (via round     |     |                   |    |
  |  |  port)         |     +-------------------+    |
  |  +----------------+                              |
  +--------------------------------------------------+
```

---

## 4. The Key Memory Array

```verilog
reg [127 : 0] key_mem [0 : 14];
```

This declares an array of **15 registers**, each 128 bits wide:

```
  key_mem array:
  +--------+-------------------------------------------+
  | Index  | Content (128-bit round key)                |
  +--------+-------------------------------------------+
  |   0    | Round key 0 (= original key for AES-128)  |
  |   1    | Round key 1                                |
  |   2    | Round key 2                                |
  |  ...   | ...                                        |
  |  10    | Round key 10 (last for AES-128)            |
  |  11    | Round key 11 (used only for AES-256)       |
  |  ...   | ...                                        |
  |  14    | Round key 14 (last for AES-256)            |
  +--------+-------------------------------------------+
```

For AES-128, only indices 0-10 are used (11 round keys). For AES-256, all 15 are used (15 round keys). The array is sized for the worst case (AES-256).

### Reading Round Keys

The read port is completely combinational:

```verilog
always @*
  begin : key_mem_read
    tmp_round_key = key_mem[round];
  end
```

During encryption or decryption, the encipher/decipher block sets the `round` input to the current round number, and the corresponding 128-bit round key appears on `round_key` in the same clock cycle (no wait needed).

---

## 5. The FSM: Four States of Key Expansion

The key expansion process is controlled by a finite state machine (FSM) with four states:

```verilog
localparam CTRL_IDLE     = 3'h0;
localparam CTRL_INIT     = 3'h1;
localparam CTRL_GENERATE = 3'h2;
localparam CTRL_DONE     = 3'h3;
```

### State Diagram

```
                          init=1
              +-------+----------+-------+
              |       |          |       |
              |  CTRL_IDLE      v       |
              |  (waiting)   CTRL_INIT  |
              |       ^      (reset     |
              |       |       counter)  |
              |       |          |      |
              |  CTRL_DONE       v      |
              |  (signal    CTRL_GENERATE
              |   ready)    (compute    |
              |       ^      round key) |
              |       |          |      |
              |       +---<------+      |
              |    round_ctr             |
              |    == num_rounds         |
              +-------------------------+
```

### Detailed State Descriptions

**CTRL_IDLE (State 0):**
```verilog
CTRL_IDLE:
  begin
    if (init)
      begin
        ready_new        = 1'b0;       // Signal "not ready"
        ready_we         = 1'b1;
        key_mem_ctrl_new = CTRL_INIT;  // Move to INIT
        key_mem_ctrl_we  = 1'b1;
      end
  end
```
- The module waits here until `init` is pulsed.
- When `init` goes high, it de-asserts `ready` (because key expansion is starting) and transitions to CTRL_INIT.

**CTRL_INIT (State 1):**
```verilog
CTRL_INIT:
  begin
    round_ctr_rst    = 1'b1;          // Reset round counter to 0
    key_mem_ctrl_new = CTRL_GENERATE;  // Move to GENERATE
    key_mem_ctrl_we  = 1'b1;
  end
```
- Resets the round counter to 0.
- Immediately transitions to CTRL_GENERATE on the next clock.
- This state lasts exactly **1 clock cycle**.

**CTRL_GENERATE (State 2):**
```verilog
CTRL_GENERATE:
  begin
    round_ctr_inc    = 1'b1;          // Increment round counter
    round_key_update = 1'b1;          // Enable key generation logic
    if (round_ctr_reg == num_rounds)
      begin
        key_mem_ctrl_new = CTRL_DONE;  // All keys generated
        key_mem_ctrl_we  = 1'b1;
      end
  end
```
- Each clock cycle: generate one round key and increment the counter.
- For AES-128: stays here for 11 cycles (round 0 through round 10).
- When all round keys are generated, transitions to CTRL_DONE.

**CTRL_DONE (State 3):**
```verilog
CTRL_DONE:
  begin
    ready_new        = 1'b1;          // Signal "ready"
    ready_we         = 1'b1;
    key_mem_ctrl_new = CTRL_IDLE;     // Return to IDLE
    key_mem_ctrl_we  = 1'b1;
  end
```
- Asserts `ready` to tell `aes_core` that all round keys are available.
- Returns to CTRL_IDLE on the next clock.
- This state lasts exactly **1 clock cycle**.

### Timing for AES-128:

```
  Clock:  0    1    2    3    4   ...  12   13   14
  State: IDLE INIT GEN  GEN  GEN ...  GEN  DONE IDLE
  round:  -    0    0    1    2  ...   10    -    -
  ready:  1    0    0    0    0  ...    0    0    1
                                              ^
                                          ready goes high
```

Total key expansion time for AES-128: approximately **13 clock cycles** (1 IDLE + 1 INIT + 11 GENERATE + 1 DONE, with some overlap due to pipelining).

---

## 6. RotWord and SubWord -- Hardware Implementation

AES key expansion uses two helper operations on 32-bit words:

### 6.1 SubWord

SubWord applies the S-Box to each byte of a 32-bit word. The key memory does this by sending the word to the **shared S-Box** in `aes_core`:

```verilog
// In the round_key_gen combinational block:
tmp_sboxw = w7;                        // Send last word of previous key to S-Box
// ... (tmp_sboxw connects to the sboxw output port)
// ... (new_sboxw comes back with the substituted bytes)
```

The port connections make this work:
```
  aes_key_mem                    aes_sbox (in aes_core)
  +-----------+                  +----------+
  | tmp_sboxw |--- sboxw ------>| sboxw    |
  |           |                  |          |
  | new_sboxw |<-- new_sboxw ---| new_sboxw|
  +-----------+                  +----------+
```

### 6.2 RotWord

RotWord rotates a 32-bit word one byte to the left. In Verilog:

```verilog
rotstw = {new_sboxw[23 : 00], new_sboxw[31 : 24]};
```

This combines SubWord and RotWord into one step. The S-Box output (`new_sboxw`) is rotated by taking bits [23:0] (the lower 3 bytes) and placing them before bits [31:24] (the top byte):

```
  Before RotWord:   | B3 | B2 | B1 | B0 |     (new_sboxw)
                      [31:24] [23:16] [15:8] [7:0]

  After RotWord:    | B2 | B1 | B0 | B3 |     (rotstw)
                      [23:16] [15:8] [7:0] [31:24]
```

### 6.3 XOR with Rcon

After RotWord, the result is XORed with the round constant:

```verilog
rconw = {rcon_reg, 24'h0};       // Rcon in the top byte, zeros below
trw = rotstw ^ rconw;             // XOR with round constant
```

The Rcon value only affects the most significant byte:

```
  rotstw:       | B2       | B1 | B0 | B3 |
  rconw:        | rcon_reg | 00 | 00 | 00 |
                  XOR        XOR  XOR  XOR
  trw:          | B2^Rcon  | B1 | B0 | B3 |
```

---

## 7. Rcon Generation Using GF(2^8) Doubling

The round constant (Rcon) changes each round. It is generated using multiplication by 2 in the Galois Field GF(2^8):

```verilog
always @*
  begin : rcon_logic
    reg [7 : 0] tmp_rcon;
    rcon_new = 8'h00;
    rcon_we  = 1'b0;

    tmp_rcon = {rcon_reg[6 : 0], 1'b0} ^ (8'h1b & {8{rcon_reg[7]}});

    if (rcon_set)
      begin
        rcon_new = 8'h8d;     // Initial seed value
        rcon_we  = 1'b1;
      end

    if (rcon_next)
      begin
        rcon_new = tmp_rcon;   // Advance to next Rcon
        rcon_we  = 1'b1;
      end
  end
```

### Breaking Down the GF(2^8) Doubling Formula

```verilog
tmp_rcon = {rcon_reg[6 : 0], 1'b0} ^ (8'h1b & {8{rcon_reg[7]}});
```

This single line implements "multiply by 2 in GF(2^8) with the irreducible polynomial x^8 + x^4 + x^3 + x + 1 (= 0x11b)":

**Part 1:** `{rcon_reg[6 : 0], 1'b0}` -- Shift left by 1 bit (= multiply by 2 in binary).

```
  rcon_reg =    b7 b6 b5 b4 b3 b2 b1 b0
  Shift left:   b6 b5 b4 b3 b2 b1 b0  0
```

**Part 2:** `(8'h1b & {8{rcon_reg[7]}})` -- Conditional XOR with 0x1b.

- `{8{rcon_reg[7]}}` replicates bit 7 eight times. If bit 7 is 1, this produces 0xFF. If bit 7 is 0, this produces 0x00.
- `8'h1b & ...` masks with 0x1b. Result: 0x1b if bit 7 was 1, or 0x00 if bit 7 was 0.

**Part 3:** XOR the two parts. This is the standard "xtime" operation from the AES specification.

### Rcon Sequence for AES-128

The seed value is 0x8d. The sequence of `rcon_next` doublings produces:

```
  Seed:    0x8d
  After doubling: 0x8d -> 0x01 -> 0x02 -> 0x04 -> 0x08 -> 0x10 -> 0x20 -> 0x40 -> 0x80 -> 0x1b -> 0x36
  Used in round:    -      1      2      3      4      5      6      7      8      9     10
```

Let us verify the first step manually:
```
  rcon_reg = 0x8d = 1000_1101
  Bit 7 = 1, so XOR with 0x1b
  Shift left: 0001_1010 = 0x1a
  XOR 0x1b:   0001_1010 ^ 0001_1011 = 0000_0001 = 0x01
```

And the step from 0x80 to 0x1b:
```
  rcon_reg = 0x80 = 1000_0000
  Bit 7 = 1, so XOR with 0x1b
  Shift left: 0000_0000 = 0x00
  XOR 0x1b:   0000_0000 ^ 0001_1011 = 0001_1011 = 0x1b
```

---

## 8. The Key Generation Loop -- How W[i] Values Are Computed

### 8.1 AES-128 Key Expansion Logic

For AES-128, the code handles two cases in the `round_key_gen` block:

**Case 1: Round 0 (storing the original key)**

```verilog
if (round_ctr_reg == 0)
  begin
    key_mem_new   = key[255 : 128];     // Original key -> round key 0
    prev_key1_new = key[255 : 128];     // Also save as "previous key"
    prev_key1_we  = 1'b1;
    rcon_next     = 1'b1;               // Advance Rcon for next round
  end
```

For AES-128, the key occupies the top 128 bits of the 256-bit `key` input (bits [255:128]).

**Case 2: Rounds 1-10 (generating new round keys)**

```verilog
else
  begin
    k0 = w4 ^ trw;
    k1 = w5 ^ w4 ^ trw;
    k2 = w6 ^ w5 ^ w4 ^ trw;
    k3 = w7 ^ w6 ^ w5 ^ w4 ^ trw;

    key_mem_new   = {k0, k1, k2, k3};  // New round key
    prev_key1_new = {k0, k1, k2, k3};  // Save for next iteration
    prev_key1_we  = 1'b1;
    rcon_next     = 1'b1;               // Advance Rcon
  end
```

Where the w4-w7 values are the four 32-bit words of the **previous** round key:

```verilog
w4 = prev_key1_reg[127 : 096];    // Word 0 of previous round key
w5 = prev_key1_reg[095 : 064];    // Word 1
w6 = prev_key1_reg[063 : 032];    // Word 2
w7 = prev_key1_reg[031 : 000];    // Word 3
```

And `trw` is the transformed word (SubWord + RotWord + Rcon XOR):

```verilog
tmp_sboxw = w7;                                      // SubWord input
rotstw = {new_sboxw[23 : 00], new_sboxw[31 : 24]};  // RotWord
trw = rotstw ^ rconw;                                // XOR with Rcon
```

### 8.2 The Key Expansion Formula Visualized

```
  Previous round key:
  +------+------+------+------+
  |  w4  |  w5  |  w6  |  w7  |
  +------+------+------+------+
     |      |      |      |
     |      |      |      +--------> SubWord -> RotWord -> XOR Rcon = trw
     |      |      |                                          |
     v      v      v                                          v
   k0 = w4 ^ trw                                           (trw)
   k1 = w5 ^ k0           (equivalent to w5 ^ w4 ^ trw)
   k2 = w6 ^ k1           (equivalent to w6 ^ w5 ^ w4 ^ trw)
   k3 = w7 ^ k2           (equivalent to w7 ^ w6 ^ w5 ^ w4 ^ trw)
     |      |      |      |
     v      v      v      v
  +------+------+------+------+
  |  k0  |  k1  |  k2  |  k3  |
  +------+------+------+------+
  New round key
```

Notice the cascading XOR pattern: each new word depends on the one before it and the corresponding word from the previous round key. This creates an avalanche effect where a single bit change propagates through all subsequent words.

---

## 9. Numerical Example: Expanding the NIST Test Key

Let us trace the key expansion for the standard NIST AES-128 test key:

```
Original Key = 0x2b7e1516_28aed2a6_abf71588_09cf4f3c
```

### Round Key 0 (round_ctr_reg == 0)

The original key is stored directly:

```
key_mem[0] = 0x2b7e1516_28aed2a6_abf71588_09cf4f3c
```

The Rcon advances from the seed (0x8d) to 0x01 for the next round.

### Round Key 1 (round_ctr_reg == 1)

**Step 1: Extract words from previous key**
```
w4 = 0x2b7e1516
w5 = 0x28aed2a6
w6 = 0xabf71588
w7 = 0x09cf4f3c
```

**Step 2: SubWord on w7**
```
tmp_sboxw = w7 = 0x09cf4f3c

S-Box lookups:
  sbox[0x09] = 0x01
  sbox[0xcf] = 0x8a
  sbox[0x4f] = 0x84
  sbox[0x3c] = 0xeb

new_sboxw = 0x018a84eb
```

**Step 3: RotWord**
```
rotstw = {new_sboxw[23:0], new_sboxw[31:24]}
       = {0x8a84eb, 0x01}
       = 0x8a84eb01
```

**Step 4: XOR with Rcon**
```
rcon_reg = 0x01
rconw    = {0x01, 24'h000000} = 0x01000000

trw = rotstw ^ rconw
    = 0x8a84eb01 ^ 0x01000000
    = 0x8b84eb01
```

**Step 5: Compute new words**
```
k0 = w4 ^ trw
   = 0x2b7e1516 ^ 0x8b84eb01 = 0xa0fafe17

k1 = w5 ^ k0
   = 0x28aed2a6 ^ 0xa0fafe17 = 0x88542cb1

k2 = w6 ^ k1
   = 0xabf71588 ^ 0x88542cb1 = 0x23a33939

k3 = w7 ^ k2
   = 0x09cf4f3c ^ 0x23a33939 = 0x2a6c7605
```

**Round Key 1:**
```
key_mem[1] = 0xa0fafe17_88542cb1_23a33939_2a6c7605
```

### Round Key 2 (round_ctr_reg == 2)

**Step 1: Extract words from previous key (Round Key 1)**
```
w4 = 0xa0fafe17
w5 = 0x88542cb1
w6 = 0x23a33939
w7 = 0x2a6c7605
```

**Step 2: SubWord on w7**
```
tmp_sboxw = w7 = 0x2a6c7605

S-Box lookups:
  sbox[0x2a] = 0xe5
  sbox[0x6c] = 0x50
  sbox[0x76] = 0x38
  sbox[0x05] = 0x6b

new_sboxw = 0xe550386b
```

**Step 3: RotWord**
```
rotstw = {0x50386b, 0xe5} = 0x50386be5
```

**Step 4: XOR with Rcon**
```
rcon_reg = 0x02      (0x01 doubled in GF(2^8))
rconw    = 0x02000000

trw = 0x50386be5 ^ 0x02000000 = 0x52386be5
```

**Step 5: Compute new words**
```
k0 = 0xa0fafe17 ^ 0x52386be5 = 0xf2c295f2
k1 = 0x88542cb1 ^ 0xf2c295f2 = 0x7a96b943
k2 = 0x23a33939 ^ 0x7a96b943 = 0x5935807a
k3 = 0x2a6c7605 ^ 0x5935807a = 0x7359f67f
```

**Round Key 2:**
```
key_mem[2] = 0xf2c295f2_7a96b943_5935807a_7359f67f
```

### Summary of First 3 Round Keys

```
  +-------+--------------------------------------------+
  | Round | Round Key (128 bits in hex)                 |
  +-------+--------------------------------------------+
  |   0   | 2b7e1516  28aed2a6  abf71588  09cf4f3c     |
  |   1   | a0fafe17  88542cb1  23a33939  2a6c7605     |
  |   2   | f2c295f2  7a96b943  5935807a  7359f67f     |
  +-------+--------------------------------------------+
```

These values match the official NIST FIPS-197 specification Appendix A.1.

---

## 10. How Round Keys Are Accessed During Encryption

Once key expansion is complete (`ready` = 1), the encipher or decipher block reads round keys by setting the `round` input:

```verilog
always @*
  begin : key_mem_read
    tmp_round_key = key_mem[round];
  end
```

This is a **combinational read**: the moment `round` changes, the corresponding 128-bit key appears on `round_key` with no clock delay. This is possible because the `key_mem` array is implemented as registers (not block RAM), so any entry can be read at any time.

```
  Encipher block during round 3:

  round = 4'h3  --------->  key_mem[3]  -------->  round_key = (round key 3)

  Encipher block during round 7:

  round = 4'h7  --------->  key_mem[7]  -------->  round_key = (round key 7)
```

The `round` input comes from the encipher or decipher block's internal round counter, routed through `aes_core`'s `muxed_round_nr` multiplexer.

---

## 11. The Shared S-Box: How Key Memory and Encipher Take Turns

This is one of the most important architectural decisions in the design. There is only **one** `aes_sbox` instance in the entire core, and two modules need it:

1. **`aes_key_mem`** needs it for SubWord during key expansion.
2. **`aes_encipher_block`** needs it for SubBytes during encryption.

The solution is **time-division multiplexing** controlled by `aes_core`:

```verilog
// From aes_core.v:
always @*
  begin : sbox_mux
    if (init_state)
      muxed_sboxw = keymem_sboxw;    // During key init: key_mem uses S-Box
    else
      muxed_sboxw = enc_sboxw;       // During encryption: encipher uses S-Box
  end
```

This works because key expansion and encryption are **sequential phases** that never overlap:

```
  Time -->
  Phase:   |--- Key Init ---|--- Encryption ---|
  S-Box    |   key_mem uses  | encipher uses    |
  user:    |   the S-Box     | the S-Box        |
  init_state:    1                 0
```

When `init_state` = 1 (during the CTRL_INIT phase of `aes_core`), the S-Box input comes from `keymem_sboxw` (which connects to `aes_key_mem`'s `sboxw` port). When `init_state` = 0 (during the CTRL_NEXT phase), the S-Box input comes from `enc_sboxw` (which connects to `aes_encipher_block`'s `sboxw` port).

The S-Box **output** (`new_sboxw`) is broadcast to both modules simultaneously, but only the active module actually uses the result.

---

## 12. Register Update Logic

All registers use the standard pattern: positive-edge triggered with asynchronous active-low reset and write-enable:

```verilog
always @ (posedge clk or negedge reset_n)
  begin: reg_update
    integer i;

    if (!reset_n)
      begin
        for (i = 0 ; i <= AES_256_NUM_ROUNDS ; i = i + 1)
          key_mem [i] <= 128'h0;           // Clear all round keys

        ready_reg        <= 1'b1;          // Start as "ready" (no operation pending)
        rcon_reg         <= 8'h0;          // Clear Rcon
        round_ctr_reg    <= 4'h0;          // Clear round counter
        prev_key0_reg    <= 128'h0;        // Clear previous key registers
        prev_key1_reg    <= 128'h0;
        key_mem_ctrl_reg <= CTRL_IDLE;     // Start in IDLE state
      end
    else
      begin
        if (ready_we)
          ready_reg <= ready_new;

        if (rcon_we)
          rcon_reg <= rcon_new;

        if (round_ctr_we)
          round_ctr_reg <= round_ctr_new;

        if (key_mem_we)
          key_mem[round_ctr_reg] <= key_mem_new;   // Write new round key

        if (prev_key0_we)
          prev_key0_reg <= prev_key0_new;

        if (prev_key1_we)
          prev_key1_reg <= prev_key1_new;

        if (key_mem_ctrl_we)
          key_mem_ctrl_reg <= key_mem_ctrl_new;
      end
  end
```

Key points:

- **`key_mem[round_ctr_reg] <= key_mem_new;`** -- The round key is written to the array position indicated by the round counter. This means round key 0 goes to index 0, round key 1 to index 1, and so on.
- **`ready_reg <= 1'b1`** on reset -- The module starts as "ready" because no key expansion is pending yet.
- **Write-enable guards** -- Every register only updates when its corresponding `_we` signal is high, preventing accidental changes.

---

## 13. The `prev_key0` and `prev_key1` Registers

The key generation logic needs to remember previous round keys to compute the next one:

- **AES-128:** Only `prev_key1_reg` is used. It holds the most recent round key.
- **AES-256:** Both `prev_key0_reg` and `prev_key1_reg` are used. AES-256 has a more complex key schedule where you need the previous two 128-bit halves.

For AES-128:
```
  Round 0:  prev_key1 = original key
  Round 1:  prev_key1 = round key 1 (just generated)
  Round 2:  prev_key1 = round key 2 (just generated)
  ...and so on
```

The words w0-w3 come from `prev_key0_reg` and w4-w7 from `prev_key1_reg`:

```verilog
w0 = prev_key0_reg[127 : 096];
w1 = prev_key0_reg[095 : 064];
w2 = prev_key0_reg[063 : 032];
w3 = prev_key0_reg[031 : 000];

w4 = prev_key1_reg[127 : 096];
w5 = prev_key1_reg[095 : 064];
w6 = prev_key1_reg[063 : 032];
w7 = prev_key1_reg[031 : 000];
```

For AES-128, only w4-w7 are used in the key generation formulas.

---

## 14. Round Counter Logic

```verilog
always @*
  begin : round_ctr
    round_ctr_new = 4'h0;
    round_ctr_we  = 1'b0;

    if (round_ctr_rst)
      begin
        round_ctr_new = 4'h0;     // Reset to 0
        round_ctr_we  = 1'b1;
      end
    else if (round_ctr_inc)
      begin
        round_ctr_new = round_ctr_reg + 1'b1;   // Increment by 1
        round_ctr_we  = 1'b1;
      end
  end
```

This is a simple counter with two controls:
- `round_ctr_rst` resets it to 0 (used in CTRL_INIT).
- `round_ctr_inc` increments it by 1 (used in CTRL_GENERATE).

The counter runs from 0 to `num_rounds` (10 for AES-128, 14 for AES-256), then stops.

---

## 15. AES-256 Key Expansion (Brief Overview)

For AES-256, the key is 256 bits, stored as two 128-bit halves:

```
key[255:128] = first half  -> round key 0
key[127:0]   = second half -> round key 1
```

The expansion logic is more complex. Even-numbered rounds use `trw` (SubWord + RotWord + Rcon), while odd-numbered rounds use `tw` (SubWord only, no RotWord or Rcon):

```verilog
if (round_ctr_reg[0] == 0)
  begin
    k0 = w0 ^ trw;          // Even round: full transform
    k1 = w1 ^ w0 ^ trw;
    k2 = w2 ^ w1 ^ w0 ^ trw;
    k3 = w3 ^ w2 ^ w1 ^ w0 ^ trw;
  end
else
  begin
    k0 = w0 ^ tw;           // Odd round: SubWord only
    k1 = w1 ^ w0 ^ tw;
    k2 = w2 ^ w1 ^ w0 ^ tw;
    k3 = w3 ^ w2 ^ w1 ^ w0 ^ tw;
    rcon_next = 1'b1;        // Advance Rcon on odd rounds
  end
```

The two `prev_key` registers alternate: after generating a new key, `prev_key1` gets the new key and `prev_key0` gets the old `prev_key1`.

---

## 16. Key Takeaways

1. **Key expansion transforms one key into many.** AES-128 produces 11 round keys from 1 original key. Each round key is unique and unpredictable without knowing the original key.

2. **The FSM is simple and linear:** IDLE -> INIT -> GENERATE (repeat) -> DONE -> IDLE. No branching or complex control flow.

3. **RotWord, SubWord, and Rcon XOR** are the three transformations applied to create each new round key. SubWord reuses the shared S-Box from `aes_core`.

4. **Rcon generation uses GF(2^8) doubling** -- a single line of Verilog that shifts left and conditionally XORs with 0x1b. The sequence starts at a seed of 0x8d.

5. **Round keys are stored in registers and read combinationally.** Any round key is available instantly by setting the `round` index.

6. **The S-Box is time-shared** between key expansion and encryption. During `init`, the key memory uses it. During `next`, the encipher block uses it. They never conflict.

7. **Key expansion for AES-128 takes about 13 clock cycles.** This is a one-time cost per key. After that, multiple blocks can be encrypted using the stored round keys.

---

> **Next:** [Chapter 12 -- AES Encipher and Decipher Blocks](12_AES_Encipher_Decipher_Blocks.md) -- How plaintext becomes ciphertext (and back again).
