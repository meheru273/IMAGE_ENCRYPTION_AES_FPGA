# Document 08: BRAM Controller (bram_ctrl.v)

> **Goal**: By the end of this document, you will understand what Block RAM (BRAM) is inside an FPGA,
> how the bram_ctrl module provides a simple memory interface, and how Vivado infers BRAM from
> Verilog code.

---

## Table of Contents
1. [What is Block RAM (BRAM)?](#1-what-is-block-ram-bram)
2. [Why Not Use Flip-Flops for Memory?](#2-why-not-use-flip-flops-for-memory)
3. [Module Interface](#3-module-interface)
4. [Complete Code Walkthrough](#4-complete-code-walkthrough)
5. [BRAM Inference — How Vivado Recognizes Memory](#5-bram-inference--how-vivado-recognizes-memory)
6. [Numerical Example: Writing and Reading Encrypted Blocks](#6-numerical-example-writing-and-reading-encrypted-blocks)
7. [Synchronous Read — The One-Cycle Delay](#7-synchronous-read--the-one-cycle-delay)
8. [BRAM Resource Usage on the Artix-7](#8-bram-resource-usage-on-the-artix-7)
9. [How top.v Uses the BRAM Controller](#9-how-topv-uses-the-bram-controller)
10. [Key Takeaways](#10-key-takeaways)

---

## 1. What is Block RAM (BRAM)?

**Block RAM (BRAM)** is dedicated memory embedded directly inside the FPGA chip. It's physically different from the logic gates (LUTs and flip-flops) — it's purpose-built memory silicon.

### Analogy: Built-in Shelving vs. Stacking Books on the Floor

Imagine you need to store 1024 books:
- **Flip-flops** = stacking books on the floor. Each book needs its own spot on the floor (one flip-flop per bit). Very wasteful of floor space.
- **BRAM** = built-in bookshelves designed specifically for storage. Much more efficient — the shelves were built into the house specifically for this purpose.

### BRAM in the Artix-7 (XC7A35T)

| Feature | Value |
|---------|-------|
| Total BRAM blocks | 50 |
| Each block capacity | 36 Kbit (= 4,608 bytes or 4.5 KB) |
| Total BRAM capacity | 1,800 Kbit (= 225 KB) |
| Supported widths | 1, 2, 4, 9, 18, 36 bits per entry |
| Max depth at 36-bit width | 1024 entries per block |
| Read latency | 1 clock cycle (synchronous) |

---

## 2. Why Not Use Flip-Flops for Memory?

Let's do the math for our project's memory needs:

```
Memory needed: 1024 entries × 128 bits = 131,072 bits

Option A: Using flip-flops
  Each flip-flop stores 1 bit
  Need: 131,072 flip-flops
  Available: 41,600 flip-flops
  → NOT POSSIBLE! We'd need 3.15× more flip-flops than available!

Option B: Using BRAM
  Each BRAM block: 36 Kbit = 36,864 bits
  Need: 131,072 / 36,864 ≈ 3.56 → 4 BRAM blocks
  Available: 50 BRAM blocks
  Used: 4 / 50 = 8%
  → Easy! Barely uses any BRAM resources.
```

**BRAM is the only option** for storing 16 KB of data on this FPGA.

---

## 3. Module Interface

```verilog
module bram_ctrl(
    input  wire          clk,        // System clock
    input  wire          wr_en,      // Write enable — HIGH to write
    input  wire          rd_en,      // Read enable — HIGH to read
    input  wire  [9:0]   addr,       // Address: 0 to 1023 (10 bits)
    input  wire  [127:0] din,        // Data input (128 bits to write)
    output reg   [127:0] dout        // Data output (128 bits read)
);
```

### Port Descriptions

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 bit | System clock — all reads and writes happen on rising edge |
| `wr_en` | Input | 1 bit | Write Enable — when HIGH, writes `din` to `mem[addr]` |
| `rd_en` | Input | 1 bit | Read Enable — when HIGH, reads `mem[addr]` to `dout` |
| `addr` | Input | 10 bits | Memory address (0 to 1023 = 2^10 locations) |
| `din` | Input | 128 bits | Data to write into memory |
| `dout` | Output | 128 bits | Data read from memory |

### Why 10-bit Address?

```
Address must cover 1024 locations
2^10 = 1024
Therefore: 10-bit address (values 0 through 1023)

Address 0    = 10'b00_0000_0000 → first encrypted block
Address 1    = 10'b00_0000_0001 → second encrypted block
...
Address 1023 = 10'b11_1111_1111 → last encrypted block (1024th)
```

---

## 4. Complete Code Walkthrough

This is one of the simplest modules in the entire project:

```verilog
// Memory array declaration
reg [127:0] mem [0:1023];
```

This line declares a **2D array**:
- 1024 entries (indexed 0 to 1023)
- Each entry is 128 bits wide
- Total: 1024 × 128 = 131,072 bits = 16,384 bytes = 16 KB

**Syntax breakdown:**
```
reg [127:0]    →  Each element is 128 bits wide (bits 127 down to 0)
mem            →  The array is called "mem"
[0:1023]       →  It has 1024 elements (index 0 through 1023)
```

### Read/Write Logic

```verilog
always @(posedge clk) begin
    if (wr_en)
        mem[addr] <= din;        // Write: store din at address
    if (rd_en)
        dout <= mem[addr];       // Read: output data from address
end
```

**Line: `if (wr_en) mem[addr] <= din;`**
- On the rising edge of the clock, if `wr_en` is HIGH, store the 128-bit `din` value into memory location `addr`.
- Only writes when told to — data is preserved otherwise.

**Line: `if (rd_en) dout <= mem[addr];`**
- On the rising edge of the clock, if `rd_en` is HIGH, read the 128-bit value from memory location `addr` and put it on `dout`.
- The read result appears on `dout` **one clock cycle later** (this is synchronous read).

**Important**: Both `if` statements use `if` (not `else if`), so theoretically you could read and write in the same clock cycle. However, if you read and write to the **same address** simultaneously, the behavior depends on the BRAM configuration (read-first, write-first, or no-change mode). Vivado handles this automatically.

---

## 5. BRAM Inference — How Vivado Recognizes Memory

When you write a memory array in Verilog, Vivado automatically decides whether to implement it using:
- **Distributed RAM** (using LUTs) — for small memories
- **Block RAM** (BRAM primitives) — for larger memories

### What Vivado Looks For

Vivado recognizes the BRAM inference pattern:

```verilog
// Pattern that Vivado infers as BRAM:
reg [WIDTH-1:0] mem [0:DEPTH-1];    // Array declaration

always @(posedge clk) begin          // Synchronous (clocked)
    if (write_enable)
        mem[address] <= data_in;      // Write
    if (read_enable)
        data_out <= mem[address];     // Synchronous read (registered output)
end
```

**Key requirements for BRAM inference:**
1. The memory must be large enough (typically > 1 Kbit)
2. Reads must be **synchronous** (inside `always @(posedge clk)`)
3. The output must be a **reg** (registered)

If the read were combinational (`assign dout = mem[addr];`), Vivado would use distributed RAM instead, which wastes LUTs.

### Verifying BRAM Inference in Vivado

After synthesis, you can check:
1. Open **Synthesized Design** → **Report Utilization**
2. Look for **"Block RAM Tile"** usage — should show ~4 BRAM36 blocks
3. Or check the **Synthesis Log** for messages like: `Inferred BRAM for signal 'mem'`

---

## 6. Numerical Example: Writing and Reading Encrypted Blocks

### Scenario: First Three Encrypted Blocks

Suppose the AES core encrypts three plaintext blocks:
```
Block 0: Plaintext → Ciphertext = 128'h39_25_84_1D_02_DC_09_FB_DC_11_85_97_19_6A_0B_32
Block 1: Plaintext → Ciphertext = 128'hAA_BB_CC_DD_EE_FF_00_11_22_33_44_55_66_77_88_99
Block 2: Plaintext → Ciphertext = 128'h11_22_33_44_55_66_77_88_99_AA_BB_CC_DD_EE_FF_00
```

### Writing (Encryption Path)

```
                    addr      wr_en    din (128-bit ciphertext)
Cycle 1000:        10'd0       1       128'h3925841D...196A0B32    ← Write block 0
Cycle 1001:        10'd0       0       (don't care)                ← wr_en back to 0
... (AES processes next block) ...
Cycle 2000:        10'd1       1       128'hAABBCCDD...66778899    ← Write block 1
Cycle 2001:        10'd1       0       (don't care)
... (AES processes next block) ...
Cycle 3000:        10'd2       1       128'h11223344...DDEEFF00    ← Write block 2
```

### Memory State After Writes

```
┌─────────┬────────────────────────────────────────┐
│ Address │ Content (128 bits)                      │
├─────────┼────────────────────────────────────────┤
│    0    │ 3925841D_02DC09FB_DC118597_196A0B32    │
│    1    │ AABBCCDD_EEFF0011_22334455_66778899    │
│    2    │ 11223344_55667788_99AABBCC_DDEEFF00    │
│    3    │ 00000000_00000000_00000000_00000000    │ ← not written yet
│   ...   │ 00000000_00000000_00000000_00000000    │
│  1023   │ 00000000_00000000_00000000_00000000    │
└─────────┴────────────────────────────────────────┘
```

### Reading (Decryption Path)

```
                    addr      rd_en    →  dout (appears NEXT cycle)
Cycle 5000:        10'd0       1       →  (dout updates at cycle 5001)
Cycle 5001:        10'd0       0       →  dout = 128'h3925841D...196A0B32 ← Block 0!
... (AES decrypts block 0) ...
Cycle 6000:        10'd1       1       →  (dout updates at cycle 6001)
Cycle 6001:        10'd1       0       →  dout = 128'hAABBCCDD...66778899 ← Block 1!
```

---

## 7. Synchronous Read — The One-Cycle Delay

This is crucial to understand: **the read result is NOT available immediately**. There's a **one-clock-cycle delay**.

```
Clock:    __|‾‾|__|‾‾|__|‾‾|__|‾‾|__
addr:     ==|  5  |==================
rd_en:    __|‾‾‾‾‾|_________________
dout:     =========|  mem[5]  |======
                    ↑
                 Data appears HERE
                 (1 cycle after rd_en)
```

**Why?** Because the read happens inside `always @(posedge clk)`. The `posedge clk` where `rd_en` is sampled is the same edge where `dout` is **scheduled** to update. Due to non-blocking assignment (`<=`), `dout` gets the new value at the **next** clock edge.

**How top.v handles this:** The system FSM accounts for this delay. When it issues a read in `SYS_DECRYPT_READ`, it transitions to `SYS_DECRYPT_WAIT` and uses the data on the next cycle.

---

## 8. BRAM Resource Usage on the Artix-7

### How Many BRAM Blocks Does Our Design Use?

```
Our memory: 1024 entries × 128 bits = 131,072 bits

BRAM36 block capacity: 36 Kbit = 36,864 bits
At 128-bit width: each BRAM36 can store 256 entries

BRAM blocks needed: 1024 / 256 = 4 BRAM36 blocks

Available on XC7A35T: 50 BRAM36 blocks
Usage: 4 / 50 = 8%
```

So our encrypted image storage uses only **8% of available BRAM**. The remaining 92% could be used for other purposes (e.g., larger images, multiple images, or other features).

### How Vivado Arranges the BRAM

Vivado automatically maps our `mem[0:1023]` × 128-bit array onto BRAM primitives. It may use:
- 4 BRAM36 blocks, each configured as 256×128-bit (most likely)
- Or 8 BRAM18 blocks (half-sized) in various configurations

You can see the actual BRAM placement in Vivado's **Device View** after implementation.

---

## 9. How top.v Uses the BRAM Controller

### Instantiation in top.v

```verilog
bram_ctrl u_bram_ctrl(
    .clk   (clk),
    .wr_en (bram_wr_en),
    .rd_en (bram_rd_en),
    .addr  (bram_addr),
    .din   (bram_din),
    .dout  (bram_dout)
);
```

### During Encryption (Writing)

After AES encrypts a block:
```verilog
// SYS_ENCRYPT_WAIT state — AES done
bram_din   <= aes_block_out;    // The encrypted 128-bit block
bram_addr  <= wr_addr;           // Current write address (0, 1, 2, ... 1023)
bram_wr_en <= 1'b1;             // Pulse write enable for 1 cycle

// SYS_ENCRYPT_STORE state — next cycle
wr_addr <= wr_addr + 10'd1;     // Increment address for next block
```

### During Decryption (Reading)

When reading back for decryption:
```verilog
// SYS_DECRYPT_READ state
bram_addr  <= rd_addr;           // Address to read (0, 1, 2, ... 1023)
bram_rd_en <= 1'b1;             // Pulse read enable

// SYS_DECRYPT_WAIT state — one cycle later, data is available
aes_block_in <= bram_dout;      // Feed ciphertext to AES for decryption
```

### Complete Encrypt-Decrypt Data Path Through BRAM

```
ENCRYPTION:
  Pixel Buffer → aes_block_out (128-bit ciphertext)
       │
       ▼
  bram_din = ciphertext
  bram_addr = 0, 1, 2, ..., 1023
  bram_wr_en = 1 (one pulse per block)
       │
       ▼
  ┌─────────────────────┐
  │ BRAM                │
  │ addr 0: ciphertext0 │
  │ addr 1: ciphertext1 │
  │ ...                  │
  │ addr 1023: cipher1023│
  └─────────────────────┘

DECRYPTION:
  ┌─────────────────────┐
  │ BRAM                │
  │ addr 0: ciphertext0 │──► bram_dout
  │ addr 1: ciphertext1 │        │
  │ ...                  │        ▼
  └─────────────────────┘   aes_block_in → AES decrypt → plaintext → UART TX
  bram_addr = 0, 1, 2, ..., 1023
  bram_rd_en = 1 (one pulse per block)
```

---

## 10. Key Takeaways

1. **BRAM is dedicated memory** inside the FPGA — much more efficient than using flip-flops for large storage.

2. **Our BRAM stores the entire encrypted image**: 1024 entries × 128 bits = 16 KB.

3. **The bram_ctrl module is simple**: just a memory array with synchronous read and write, all in ~10 lines of logic.

4. **Vivado infers BRAM automatically** when it sees the `reg [N:0] mem [0:M];` pattern with synchronous read.

5. **Reads have a 1-cycle latency**: data appears on `dout` one clock cycle after asserting `rd_en`. The system FSM accounts for this.

6. **Resource usage is minimal**: only 4 out of 50 available BRAM blocks (8%).

---

> **Next**: [Document 09 — AES Algorithm Explained](09_AES_Algorithm_Explained.md) — Now we dive into the heart of the project: the AES-128 encryption algorithm, explained step by step with numerical examples.
