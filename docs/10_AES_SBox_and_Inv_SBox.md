# Chapter 10: AES S-Box and Inverse S-Box (`aes_sbox.v` / `aes_inv_sbox.v`)

> **Previous:** [Chapter 9 -- AES Algorithm Explained](09_AES_Algorithm_Explained.md)
> **Next:** [Chapter 11 -- AES Key Memory](11_AES_Key_Memory_aes_key_mem.md)

---

## 1. What This Chapter Covers

In this chapter you will learn:

- What the S-Box (Substitution Box) is and why AES needs it.
- How the Verilog module `aes_sbox.v` implements the S-Box as a 256-byte ROM with four parallel lookups.
- How the inverse S-Box (`aes_inv_sbox.v`) undoes the substitution for decryption.
- A complete numerical example tracing a 32-bit word through both modules.
- Why a single `aes_sbox` instance is shared between the encipher block and the key memory, while the decipher block gets its own inverse S-Box.

---

## 2. What the S-Box Does and Why It Matters

### 2.1 The Purpose: Non-Linearity

AES processes data in 16-byte (128-bit) blocks. During encryption, every single byte of the block is replaced by a different byte according to a fixed lookup table called the **S-Box** (short for "Substitution Box").

Why not just XOR the data with a key and call it a day? Because XOR is a *linear* operation. If an attacker knows that your cipher is purely linear, they can set up a system of equations and solve for the key with basic algebra. The S-Box introduces **non-linearity** -- it makes the relationship between input and output so complex that algebraic attacks become computationally infeasible.

```
Without S-Box (linear only):      With S-Box (non-linear):
  Input byte: 0x19                   Input byte: 0x19
  XOR key:    0x2b                   S-Box lookup: 0xd4      <-- no simple formula!
  Result:     0x32                   Then XOR key, shift, mix...
  (Attacker can solve equations)     (Attacker cannot solve equations)
```

### 2.2 The Lookup Table Concept

Think of the S-Box as a dictionary with exactly 256 entries (one for every possible byte value, 0x00 through 0xFF). You feed in a byte, and out comes a completely different byte:

```
  Input byte -----> [ S-Box: 256-entry table ] -----> Output byte

  Example entries:
    0x00 -> 0x63
    0x01 -> 0x7c
    0x19 -> 0xd4
    0xa0 -> 0xe0
    0xff -> 0x16
```

The values in this table are NOT random. They are derived from computing the multiplicative inverse in the Galois Field GF(2^8), followed by an affine transformation. But from a hardware perspective, you do not need to compute that math on the fly -- you just store all 256 results in a ROM.

---

## 3. How `aes_sbox.v` Works -- Line by Line

Let us walk through the entire source file.

### 3.1 Module Declaration

```verilog
module aes_sbox(
                input wire [31 : 0]  sboxw,
                output wire [31 : 0] new_sboxw
               );
```

**What this means:**

| Port        | Direction | Width   | Purpose                                    |
|-------------|-----------|---------|---------------------------------------------|
| `sboxw`     | input     | 32 bits | The 32-bit word whose bytes will be substituted |
| `new_sboxw` | output    | 32 bits | The 32-bit word after S-Box substitution    |

Notice: the module takes a **32-bit word** (4 bytes), not a single byte. This is because AES operates on columns of 4 bytes at a time. Processing 4 bytes per call makes the design efficient.

### 3.2 The ROM Array Declaration

```verilog
wire [7 : 0] sbox [0 : 255];
```

This line declares an array of 256 wires, each 8 bits wide. In Verilog:

- `wire [7 : 0]` means each element is an 8-bit value (one byte).
- `sbox [0 : 255]` means there are 256 elements, indexed 0 through 255.

This is the storage for our lookup table. Since it is declared as `wire` (not `reg`), and each entry is assigned with a continuous `assign` statement, the synthesis tool will implement this as combinational logic (essentially a large multiplexer network) or a ROM.

```
  sbox array in memory:
  +--------+--------+--------+--------+-----+--------+
  | sbox[0]| sbox[1]| sbox[2]| sbox[3]| ... |sbox[255]|
  | = 0x63 | = 0x7c | = 0x77 | = 0x7b | ... | = 0x16 |
  +--------+--------+--------+--------+-----+--------+
     ^                                          ^
   index 0x00                               index 0xFF
```

### 3.3 The Four Parallel Multiplexers

This is the heart of the module:

```verilog
assign new_sboxw[31 : 24] = sbox[sboxw[31 : 24]];
assign new_sboxw[23 : 16] = sbox[sboxw[23 : 16]];
assign new_sboxw[15 : 08] = sbox[sboxw[15 : 08]];
assign new_sboxw[07 : 00] = sbox[sboxw[07 : 00]];
```

Each line does the same thing for a different byte of the 32-bit input word. Let us break down the first line in detail:

```
assign new_sboxw[31 : 24] = sbox[sboxw[31 : 24]];
       ^^^^^^^^^^^^^^^^       ^^^^ ^^^^^^^^^^^^^^^
       Output bits 31-24      Look up the ROM entry
       (the top byte of       whose index is the top byte
        the output word)      of the input word
```

Here is an ASCII diagram of all four parallel lookups:

```
  Input word sboxw (32 bits):
  +----------+----------+----------+----------+
  | Byte 3   | Byte 2   | Byte 1   | Byte 0   |
  |[31 : 24] |[23 : 16] |[15 : 08] |[07 : 00] |
  +----+-----+----+-----+----+-----+----+-----+
       |          |          |          |
       v          v          v          v
  +--------+ +--------+ +--------+ +--------+
  |sbox[B3]| |sbox[B2]| |sbox[B1]| |sbox[B0]|
  | lookup | | lookup | | lookup | | lookup |
  +---+----+ +---+----+ +---+----+ +---+----+
      |          |          |          |
      v          v          v          v
  +----------+----------+----------+----------+
  | S(Byte3) | S(Byte2) | S(Byte1) | S(Byte0) |
  |[31 : 24] |[23 : 16] |[15 : 08] |[07 : 00] |
  +----------+----------+----------+----------+
  Output word new_sboxw (32 bits)
```

All four lookups happen **in parallel** and **combinationally** (no clock needed). The moment the input changes, the output changes after a small propagation delay through the mux logic.

### 3.4 The 256 ROM Entries

The rest of the file contains 256 lines like these:

```verilog
assign sbox[8'h00] = 8'h63;
assign sbox[8'h01] = 8'h7c;
assign sbox[8'h02] = 8'h77;
// ... (252 more lines) ...
assign sbox[8'hfe] = 8'hbb;
assign sbox[8'hff] = 8'h16;
```

Each line says: "When the index is `X`, the output byte is `Y`." For example:

- `assign sbox[8'h00] = 8'h63;` means S-Box(0x00) = 0x63.
- `assign sbox[8'h19] = 8'hd4;` means S-Box(0x19) = 0xd4.
- `assign sbox[8'hff] = 8'h16;` means S-Box(0xFF) = 0x16.

These 256 values are the standard AES S-Box values defined in the FIPS-197 specification. Every AES implementation on the planet uses exactly these same 256 values.

---

## 4. Numerical Example: Tracing `0x19a09ae9` Through the S-Box

Let us trace a concrete input word through the S-Box module step by step. We will use the input `sboxw = 32'h19a09ae9`, which is a well-known test vector from the AES specification.

### Step 1: Split the 32-bit word into four bytes

```
sboxw = 0x19a09ae9

  Bit positions:     [31:24]  [23:16]  [15:08]  [07:00]
  Hex values:          0x19     0xa0     0x9a     0xe9
```

### Step 2: Look up each byte independently

```
  Byte 3:  sboxw[31:24] = 0x19  -->  sbox[0x19] = 0xd4
  Byte 2:  sboxw[23:16] = 0xa0  -->  sbox[0xa0] = 0xe0
  Byte 1:  sboxw[15:08] = 0x9a  -->  sbox[0x9a] = 0xb8
  Byte 0:  sboxw[07:00] = 0xe9  -->  sbox[0xe9] = 0x1e
```

You can verify these by finding the corresponding lines in the source:

```verilog
assign sbox[8'h19] = 8'hd4;    // Line 91 in aes_sbox.v
assign sbox[8'ha0] = 8'he0;    // Line 226
assign sbox[8'h9a] = 8'hb8;    // Line 220
assign sbox[8'he9] = 8'h1e;    // Line 299
```

### Step 3: Assemble the output word

```
new_sboxw = { sbox[0x19], sbox[0xa0], sbox[0x9a], sbox[0xe9] }
          = {    0xd4,       0xe0,       0xb8,       0x1e     }
          = 0xd4e0b81e
```

### Complete picture:

```
  INPUT:   0x19  0xa0  0x9a  0xe9
            |     |     |     |
            v     v     v     v
          +-----+-----+-----+-----+
          |S-Box|S-Box|S-Box|S-Box|
          +-----+-----+-----+-----+
            |     |     |     |
            v     v     v     v
  OUTPUT:  0xd4  0xe0  0xb8  0x1e

  Input word:  0x19a09ae9
  Output word: 0xd4e0b81e
```

---

## 5. How `aes_inv_sbox.v` Mirrors the S-Box

The inverse S-Box module is structurally **identical** to the forward S-Box. The only difference is the lookup table values.

### 5.1 Module Declaration

```verilog
module aes_inv_sbox(
                    input wire  [31 : 0] sboxw,
                    output wire [31 : 0] new_sboxw
                   );
```

Same ports, same widths, same names. The interface is interchangeable.

### 5.2 The Inverse ROM Array

```verilog
wire [7 : 0] inv_sbox [0 : 255];
```

Same structure: 256 entries, each 8 bits. But the values are the *inverse* of the forward S-Box.

### 5.3 The Four Parallel Multiplexers

```verilog
assign new_sboxw[31 : 24] = inv_sbox[sboxw[31 : 24]];
assign new_sboxw[23 : 16] = inv_sbox[sboxw[23 : 16]];
assign new_sboxw[15 : 08] = inv_sbox[sboxw[15 : 08]];
assign new_sboxw[07 : 00] = inv_sbox[sboxw[07 : 00]];
```

Exactly the same parallel lookup structure, just referencing `inv_sbox` instead of `sbox`.

### 5.4 Inverse ROM Values

```verilog
assign inv_sbox[8'h00] = 8'h52;
assign inv_sbox[8'h01] = 8'h09;
// ...
assign inv_sbox[8'hd4] = 8'h19;    // This is the inverse of sbox[0x19] = 0xd4
// ...
assign inv_sbox[8'hff] = 8'h7d;
```

The relationship between the two tables is: if `sbox[A] = B`, then `inv_sbox[B] = A`.

---

## 6. Roundtrip Verification: Proving S-Box and Inv-S-Box Are Inverses

This is the critical property: applying the S-Box followed by the inverse S-Box must return the original byte. Let us verify this with our example bytes.

### Byte 0x19:

```
Forward:  sbox[0x19]     = 0xd4       (from aes_sbox.v, line 91)
Inverse:  inv_sbox[0xd4] = 0x19       (from aes_inv_sbox.v, line 276)
Roundtrip: 0x19 --> 0xd4 --> 0x19     PASS
```

### Byte 0xa0:

```
Forward:  sbox[0xa0]     = 0xe0       (from aes_sbox.v, line 226)
Inverse:  inv_sbox[0xe0] = 0xa0       (from aes_inv_sbox.v, line 288)
Roundtrip: 0xa0 --> 0xe0 --> 0xa0     PASS
```

### Byte 0x9a:

```
Forward:  sbox[0x9a]     = 0xb8       (from aes_sbox.v, line 220)
Inverse:  inv_sbox[0xb8] = 0x9a       (from aes_inv_sbox.v, line 248)
Roundtrip: 0x9a --> 0xb8 --> 0x9a     PASS
```

### Byte 0xe9:

```
Forward:  sbox[0xe9]     = 0x1e       (from aes_sbox.v, line 299)
Inverse:  inv_sbox[0x1e] = 0xe9       (from aes_inv_sbox.v, line 94)
Roundtrip: 0xe9 --> 0x1e --> 0xe9     PASS
```

### Full 32-bit word roundtrip:

```
  Original word:           0x19a09ae9
  After S-Box:             0xd4e0b81e
  After Inverse S-Box:     0x19a09ae9    (matches original!)
```

This roundtrip property is what makes decryption possible. During encryption, the encipher block applies the forward S-Box. During decryption, the decipher block applies the inverse S-Box to undo it.

---

## 7. Why the S-Box Is Shared (Resource Saving)

This is an important architectural decision in this AES core. Look at this diagram:

```
                     +-------------+
                     |  aes_core   |
                     |             |
   +-----------+     |   +------+  |     +----------------+
   | aes_sbox  |<----|---| MUX  |<-|-----| aes_key_mem    |
   | (shared)  |---->|---|      |--|---->| (key expansion) |
   +-----------+     |   +------+  |     +----------------+
                     |      ^      |
                     |      |      |     +------------------+
                     |      +------|-----| aes_encipher_block|
                     |             |     | (encryption)      |
                     |             |     +------------------+
                     |             |
                     |             |     +------------------+
                     |             |     | aes_decipher_block|
                     |             |     | (decryption)      |
                     |             |     |  +-----------+   |
                     |             |     |  |aes_inv_sbox|  |
                     |             |     |  | (private)  |  |
                     |             |     |  +-----------+   |
                     |             |     +------------------+
                     +-------------+
```

### Why share the forward S-Box?

Both the key expansion module (`aes_key_mem`) and the encipher block need the **forward** S-Box:

- **Key expansion** uses it for the SubWord step when generating round keys.
- **Encipher** uses it for the SubBytes step in each encryption round.

An S-Box is a significant piece of hardware (256 x 8-bit ROM + mux logic). Instantiating two copies would waste FPGA resources. Instead, this design instantiates **one** S-Box in `aes_core.v` and uses a multiplexer to share it:

```verilog
// From aes_core.v -- the single shared S-Box instance:
aes_sbox sbox_inst(.sboxw(muxed_sboxw), .new_sboxw(new_sboxw));

// The mux that decides who gets to use the S-Box:
always @*
  begin : sbox_mux
    if (init_state)
      muxed_sboxw = keymem_sboxw;    // Key memory gets the S-Box
    else
      muxed_sboxw = enc_sboxw;       // Encipher block gets the S-Box
  end
```

This works because key expansion and encryption **never happen at the same time**. Key expansion runs first (during `init`), and encryption runs after (during `next`). The `init_state` signal tells the mux who is currently active.

### Why does the decipher block get its own inverse S-Box?

The decipher block needs the **inverse** S-Box, which has completely different table values. It cannot share the forward S-Box at all. So it instantiates its own:

```verilog
// From aes_decipher_block.v:
aes_inv_sbox inv_sbox_inst(.sboxw(tmp_sboxw), .new_sboxw(new_sboxw));
```

This is acceptable because in a given design, you are usually doing either encryption or decryption (selected by the `encdec` signal in `aes_core`), so the inverse S-Box sits idle during encryption and vice versa.

---

## 8. Hardware Implementation: What the Synthesizer Actually Builds

When you synthesize `aes_sbox.v` for an FPGA, the tool does not literally create 256 flip-flops. Since every entry is a constant (hardwired with `assign`), the tool will implement it as one of:

1. **A lookup table (LUT) tree:** The FPGA's configurable logic blocks are used to build a large multiplexer. The 8-bit input byte selects one of 256 constant outputs.

2. **Block RAM (BROM):** If the FPGA has dedicated block RAM, the synthesizer might place the table there for efficiency.

Either way, the result is purely **combinational** -- no clock needed. The output appears after a fixed propagation delay whenever the input changes.

```
  Timing diagram (combinational, no clock needed):

  sboxw:       |  0x19a09ae9  |  0x00000001  |  0xFFFFFFFF  |
               |              |              |              |
  new_sboxw:   |  0xd4e0b81e  |  0x637c7c7c  |  0x16161616  |
               |              |              |              |
               ^              ^              ^
               |-- ~2-5 ns -->|-- ~2-5 ns -->|
               (propagation delay through LUT/mux network)
```

---

## 9. Summary Table

| Aspect                | `aes_sbox`                    | `aes_inv_sbox`                |
|-----------------------|-------------------------------|-------------------------------|
| Purpose               | SubBytes (encryption + key expansion) | InvSubBytes (decryption)   |
| Table variable        | `sbox [0:255]`                | `inv_sbox [0:255]`           |
| Parallel lookups      | 4 (one per byte of 32-bit word) | 4 (one per byte of 32-bit word) |
| Instantiated in       | `aes_core.v` (shared)         | `aes_decipher_block.v` (private) |
| Clock needed?         | No (combinational)            | No (combinational)            |
| Key relationship      | If `sbox[A] = B` ...          | ... then `inv_sbox[B] = A`   |

---

## 10. Key Takeaways

1. **The S-Box is a fixed 256-byte lookup table** that provides the crucial non-linearity AES needs for security. Without it, the cipher would be vulnerable to algebraic attacks.

2. **The module processes 4 bytes in parallel** using four independent mux lookups on the same clock-less combinational path. This matches AES's column-oriented processing.

3. **The inverse S-Box is a separate table** with the mathematical inverse of each entry, used exclusively during decryption.

4. **Resource sharing is a key design technique:** one S-Box instance serves both the key expansion and the encipher block via a time-division mux, saving FPGA resources.

5. **Roundtrip correctness** is guaranteed: `InvSBox(SBox(x)) = x` for every possible byte value, which is what makes AES decryption possible.

---

> **Next:** [Chapter 11 -- AES Key Memory (`aes_key_mem.v`)](11_AES_Key_Memory_aes_key_mem.md) -- How one 128-bit key is expanded into 11 round keys.
