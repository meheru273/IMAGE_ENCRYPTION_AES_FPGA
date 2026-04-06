# Document 07: Pixel Buffer (pixel_buffer.v)

> **Goal**: By the end of this document, you will understand how the pixel buffer collects
> 16 individual bytes from the UART receiver and packs them into a single 128-bit AES block,
> using a shift register design pattern.

---

## Table of Contents
1. [What Does the Pixel Buffer Do?](#1-what-does-the-pixel-buffer-do)
2. [Why Do We Need It?](#2-why-do-we-need-it)
3. [Module Interface](#3-module-interface)
4. [The Shift Register Concept](#4-the-shift-register-concept)
5. [Complete Code Walkthrough](#5-complete-code-walkthrough)
6. [Numerical Example: Packing 16 Bytes](#6-numerical-example-packing-16-bytes)
7. [The block_valid Pulse](#7-the-block_valid-pulse)
8. [How top.v Uses the Pixel Buffer](#8-how-topv-uses-the-pixel-buffer)
9. [Key Takeaways](#9-key-takeaways)

---

## 1. What Does the Pixel Buffer Do?

The pixel buffer is a **byte-to-block converter**. It:
1. Receives bytes one at a time (from the UART receiver)
2. Accumulates them in a shift register
3. After exactly 16 bytes, outputs a complete 128-bit block for AES encryption

### Analogy: Loading a Shipping Container

Imagine you're loading boxes onto a truck:
- Boxes arrive one at a time on a conveyor belt (UART bytes)
- You stack them into a shipping container that holds exactly 16 boxes (shift register)
- When the container is full, you seal it and ship it off (output the 128-bit block)
- Then you start filling the next container

---

## 2. Why Do We Need It?

**The mismatch problem:**
- UART gives us **1 byte (8 bits)** at a time
- AES needs **16 bytes (128 bits)** at a time

Without the pixel buffer, we'd have no way to feed AES:

```
UART RX output:   [B0] [B1] [B2] ... [B15]  (one byte at a time)
                    ↓    ↓    ↓         ↓
Pixel Buffer:    [B0|B1|B2|B3|B4|B5|...|B15]  (accumulates 16 bytes)
                               ↓
AES input:       [128-bit block]               (needs all 16 at once)
```

---

## 3. Module Interface

```verilog
module pixel_buffer(
    input  wire         clk,          // 100 MHz system clock
    input  wire         rst,          // Active-high reset
    input  wire [7:0]   pixel_in,     // Incoming byte (from UART RX)
    input  wire         pixel_valid,  // HIGH for 1 cycle when pixel_in is valid
    output reg  [127:0] block_out,    // 128-bit output block (16 bytes packed)
    output reg          block_valid   // HIGH for 1 cycle when block_out is ready
);
```

### Port Descriptions

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 bit | System clock (100 MHz) |
| `rst` | Input | 1 bit | Reset — clears the buffer and counter |
| `pixel_in` | Input | 8 bits | The incoming byte to buffer |
| `pixel_valid` | Input | 1 bit | Pulse HIGH for 1 clock cycle when `pixel_in` is valid |
| `block_out` | Output | 128 bits | The assembled 128-bit block (16 bytes) |
| `block_valid` | Output | 1 bit | Pulse HIGH for 1 clock cycle when `block_out` is ready |

---

## 4. The Shift Register Concept

A **shift register** is one of the most common patterns in digital design. It shifts existing data over and inserts new data at one end.

### Visual Explanation

Think of it like a tube that can hold 16 balls. You push a new ball in from the right side, and all existing balls slide left by one position:

```
Before: [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]
Push 0xAB:
After:  [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [AB]

Push 0xCD:
After:  [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ] [AB] [CD]

... (14 more pushes) ...

Push 0x99 (16th byte):
After:  [AB] [CD] [..] [..] [..] [..] [..] [..] [..] [..] [..] [..] [..] [..] [..] [99]
→ FULL! Output this as a 128-bit block!
```

### In Verilog

The shift operation is done in one line:

```verilog
shift_reg <= {shift_reg[119:0], pixel_in};
```

Let's break this down:
- `shift_reg[119:0]` = take the lower 120 bits (15 bytes) of the current register
- `pixel_in` = the new 8-bit byte
- `{..., ...}` = concatenate them: put the 120 bits on the left, new byte on the right
- The topmost byte (bits 127:120) is discarded — it "falls off" the left end

```
Before:  [Byte15] [Byte14] [Byte13] ... [Byte1] [Byte0]
         [127:120] [119:112]              [15:8]  [7:0]

Shift operation: {shift_reg[119:0], new_byte}

After:   [Byte14] [Byte13] [Byte12] ... [Byte0] [NewByte]
         [127:120] [119:112]              [15:8]  [7:0]
```

This means the **first byte received** ends up at the **most significant position** (bits 127:120), and the **last byte received** ends up at the **least significant position** (bits 7:0). This is called **MSB-first packing**.

---

## 5. Complete Code Walkthrough

### Internal Registers

```verilog
reg [3:0]   byte_cnt;     // Counts 0 to 15 — which byte are we on?
reg [127:0] shift_reg;    // The 128-bit shift register
```

- `byte_cnt` (4 bits): Counts from 0 to 15. When it reaches 15, we have 16 bytes (remember: 0-indexed, so 0 through 15 = 16 bytes total).
- `shift_reg` (128 bits): Holds the bytes as they accumulate.

### The Main Logic Block

```verilog
always @(posedge clk) begin
    if (rst) begin
        byte_cnt    <= 4'd0;       // Reset counter to 0
        shift_reg   <= 128'd0;     // Clear the shift register
        block_out   <= 128'd0;     // Clear the output
        block_valid <= 1'b0;       // No valid output
    end else begin
        block_valid <= 1'b0;       // DEFAULT: block_valid is LOW
                                    // (it only goes HIGH for 1 cycle)

        if (pixel_valid) begin     // A new byte has arrived!
            // Shift left by 8 bits and insert new byte at LSB
            shift_reg <= {shift_reg[119:0], pixel_in};

            if (byte_cnt == 4'd15) begin
                // This is byte #16 (index 15) — block is complete!
                block_out   <= {shift_reg[119:0], pixel_in};
                block_valid <= 1'b1;   // Signal: block is ready!
                byte_cnt    <= 4'd0;   // Reset counter for next block
            end else begin
                byte_cnt <= byte_cnt + 4'd1;  // Not full yet, keep counting
            end
        end
    end
end
```

### Line-by-Line Analysis

**Line: `block_valid <= 1'b0;`** (the default)
This is a clever pattern. By setting `block_valid` to 0 as the default at the start of every clock cycle, it automatically creates a **one-cycle pulse**. The only way `block_valid` becomes 1 is inside the `if (byte_cnt == 4'd15)` branch — and on the very next clock cycle, the default kicks in and it goes back to 0.

**Line: `shift_reg <= {shift_reg[119:0], pixel_in};`**
Every time a valid byte arrives, we shift and insert. This happens even on the 16th byte.

**Line: `block_out <= {shift_reg[119:0], pixel_in};`**
When the block is complete, we output the final result. Notice this is the same expression as the shift register update — it includes the latest byte (pixel_in) that's arriving this cycle.

**Why not just use `block_out <= shift_reg`?** Because `shift_reg` won't be updated until the next clock cycle (non-blocking assignment). At this moment, `shift_reg` still holds only 15 bytes. The 16th byte is in `pixel_in`, so we manually construct the full block by concatenating.

---

## 6. Numerical Example: Packing 16 Bytes

Let's trace through receiving the first row of image pixels. Suppose the first 16 pixels have values:
`0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F`

### Cycle-by-Cycle Trace

| Cycle | pixel_valid | pixel_in | byte_cnt | shift_reg (hex, last bytes shown) | block_valid |
|-------|-------------|----------|----------|-----------------------------------|-------------|
| 0 | 0 | xx | 0 | 00000000...00000000 | 0 |
| ... | 0 | xx | 0 | (waiting for UART) | 0 |
| 100 | 1 | 0x10 | 0→1 | ...00000000_00000010 | 0 |
| ... | 0 | xx | 1 | (waiting) | 0 |
| 200 | 1 | 0x11 | 1→2 | ...00000000_00001011 | 0 |
| 300 | 1 | 0x12 | 2→3 | ...00000000_00101112 | 0 |
| 400 | 1 | 0x13 | 3→4 | ...00000000_10111213 | 0 |
| ... | ... | ... | ... | ... | 0 |
| 1500 | 1 | 0x1F | 15→0 | 10111213...1C1D1E1F | **1** |

**Final output (when byte_cnt == 15):**
```
block_out = 128'h1011121314151617_18191A1B1C1D1E1F
block_valid = 1 (for exactly 1 clock cycle)
```

### Detailed Shift Register Evolution

```
After byte  0 (0x10): shift_reg = 000000000000000000000000000000_10
After byte  1 (0x11): shift_reg = 0000000000000000000000000000_1011
After byte  2 (0x12): shift_reg = 00000000000000000000000000_101112
After byte  3 (0x13): shift_reg = 000000000000000000000000_10111213
After byte  4 (0x14): shift_reg = 0000000000000000000000_1011121314
After byte  5 (0x15): shift_reg = 00000000000000000000_101112131415
After byte  6 (0x16): shift_reg = 000000000000000000_10111213141516
After byte  7 (0x17): shift_reg = 0000000000000000_1011121314151617
After byte  8 (0x18): shift_reg = 00000000000000_101112131415161718
After byte  9 (0x19): shift_reg = 000000000000_10111213141516171819
After byte 10 (0x1A): shift_reg = 0000000000_101112131415161718191A
After byte 11 (0x1B): shift_reg = 00000000_101112131415161718191A1B
After byte 12 (0x1C): shift_reg = 000000_101112131415161718191A1B1C
After byte 13 (0x1D): shift_reg = 0000_101112131415161718191A1B1C1D
After byte 14 (0x1E): shift_reg = 00_101112131415161718191A1B1C1D1E
After byte 15 (0x1F): block_out = 101112131415161718191A1B1C1D1E1F  ← OUTPUT!
                                  ↑                              ↑
                              First byte                    Last byte
                              (MSB position)                (LSB position)
```

**Key observation**: The first byte received (0x10) is at the **leftmost** position (bits 127:120). The last byte (0x1F) is at the **rightmost** position (bits 7:0). This is **MSB-first packing** — the convention used by AES.

---

## 7. The block_valid Pulse

`block_valid` is HIGH for exactly **one clock cycle** — a "pulse." This is a very common design pattern.

```
Clock:       __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|
pixel_valid: ___|‾‾|_____|‾‾|_________________________________
                 ↑ byte 14   ↑ byte 15 (16th byte)
block_valid: ________________|‾‾|_____________________________
                              ↑ ONE cycle pulse
block_out:   ================|VALID DATA|======================
```

**Why a pulse and not a sustained signal?** Because the top module needs to know exactly **when** a new block is ready. A pulse says "right now, this cycle, the block is fresh." The top module reacts to this pulse in one clock cycle.

---

## 8. How top.v Uses the Pixel Buffer

In `top.v`, the pixel buffer is instantiated like this:

```verilog
pixel_buffer u_pixel_buffer(
    .clk        (clk),
    .rst        (rst_btn),
    .pixel_in   (rx_data),                  // Byte from UART RX
    .pixel_valid(rx_valid & ~mode_sw),      // Only buffer during encrypt mode!
    .block_out  (pbuf_block),               // 128-bit output block
    .block_valid(pbuf_valid)                // "Block is ready" pulse
);
```

**Notice**: `.pixel_valid(rx_valid & ~mode_sw)` — the pixel buffer only accepts bytes when:
- `rx_valid` is HIGH (UART received a byte), AND
- `mode_sw` is LOW (we're in encrypt mode, not decrypt mode)

In the system FSM, when `pbuf_valid` goes HIGH:
```verilog
if (!mode_sw && pbuf_valid) begin
    aes_block_in <= pbuf_block;    // Feed the block to AES
    aes_mode     <= 1'b1;          // Set to encrypt
    aes_start    <= 1'b1;          // Tell AES to start
    sys_state    <= SYS_ENCRYPT_WAIT;
end
```

---

## 9. Key Takeaways

1. **Pixel buffer bridges the UART-AES gap**: UART gives 1 byte/cycle, AES needs 16 bytes at once. The pixel buffer accumulates 16 bytes using a shift register.

2. **Shift register pattern**: `{shift_reg[119:0], new_byte}` — shift left 8 bits, insert new byte at the right. This is a fundamental hardware pattern.

3. **MSB-first packing**: First byte received → MSB position (bits 127:120). Last byte → LSB position (bits 7:0). Matches AES convention.

4. **One-cycle valid pulse**: `block_valid` is HIGH for exactly 1 clock cycle when the block is complete, using the `default <= 1'b0` pattern.

5. **The module is purely passive** — it has no FSM. It just responds to valid bytes, counts, shifts, and signals when full.

---

> **Next**: [Document 08 — BRAM Controller (bram_ctrl.v)](08_BRAM_Controller_bram_ctrl.md) — Learn how the encrypted blocks are stored in the FPGA's internal memory.
