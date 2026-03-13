# Document 09: AES Algorithm Explained

> **Goal**: By the end of this document, you will fully understand the AES-128 encryption algorithm —
> the state matrix, SubBytes, ShiftRows, MixColumns, AddRoundKey, and Key Expansion — with
> complete numerical examples you can verify by hand.

---

## Table of Contents
1. [AES Overview and History](#1-aes-overview-and-history)
2. [The AES State Matrix — 4×4 Grid of Bytes](#2-the-aes-state-matrix--44-grid-of-bytes)
3. [AES-128 Encryption: The 10-Round Process](#3-aes-128-encryption-the-10-round-process)
4. [Step 1: AddRoundKey — XOR with the Key](#4-step-1-addroundkey--xor-with-the-key)
5. [Step 2: SubBytes — S-Box Substitution](#5-step-2-subbytes--s-box-substitution)
6. [Step 3: ShiftRows — Rotating the Rows](#6-step-3-shiftrows--rotating-the-rows)
7. [Step 4: MixColumns — Galois Field Magic](#7-step-4-mixcolumns--galois-field-magic)
8. [Key Expansion — Generating Round Keys](#8-key-expansion--generating-round-keys)
9. [Complete AES-128 Encryption Example (NIST)](#9-complete-aes-128-encryption-example-nist)
10. [AES Decryption — Reversing Everything](#10-aes-decryption--reversing-everything)
11. [Key Takeaways](#11-key-takeaways)

---

## 1. AES Overview and History

### What is AES?

**AES (Advanced Encryption Standard)** is a symmetric block cipher that:
- Takes a **128-bit plaintext** block (16 bytes)
- Uses a **secret key** (128, 192, or 256 bits)
- Produces a **128-bit ciphertext** block
- The same key is used for both encryption and decryption

### Brief History

- **1997**: U.S. NIST announces a competition to replace the aging DES (Data Encryption Standard)
- **1998-2000**: 15 algorithms from around the world compete
- **2000**: **Rijndael** (by Belgian cryptographers Vincent Rijmen and Joan Daemen) wins
- **2001**: Rijndael is standardized as AES (FIPS-197)
- **Today**: AES is the most widely used encryption algorithm in the world

### AES Variants

| Variant | Key Size | Rounds | Security Level |
|---------|----------|--------|----------------|
| AES-128 | 128 bits (16 bytes) | 10 | Very strong |
| AES-192 | 192 bits (24 bytes) | 12 | Stronger |
| AES-256 | 256 bits (32 bytes) | 14 | Strongest |

**Our project uses AES-128** — 128-bit key with 10 rounds.

---

## 2. The AES State Matrix — 4×4 Grid of Bytes

AES operates on a **4×4 matrix of bytes** called the **state**. The 16 input bytes are arranged **column-by-column** (not row-by-row!):

### How the State is Filled

Given 16 input bytes: `b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15`

```
                Column 0   Column 1   Column 2   Column 3
         ┌─────────────────────────────────────────────────┐
Row 0    │   b0     │   b4     │   b8     │   b12    │
Row 1    │   b1     │   b5     │   b9     │   b13    │
Row 2    │   b2     │   b6     │   b10    │   b14    │
Row 3    │   b3     │   b7     │   b11    │   b15    │
         └─────────────────────────────────────────────────┘
```

**Notice**: Bytes fill **columns first**, then move to the next column. This is called **column-major order**.

### Numerical Example with NIST Test Vector

Our project uses the NIST test key and plaintext:
```
Plaintext: 32 43 f6 a8 88 5a 30 8d 31 31 98 a2 e0 37 07 34

State matrix:
     Col 0    Col 1    Col 2    Col 3
  ┌────────┬────────┬────────┬────────┐
  │  32    │  88    │  31    │  e0    │  ← Row 0
  │  43    │  5a    │  31    │  37    │  ← Row 1
  │  f6    │  30    │  98    │  07    │  ← Row 2
  │  a8    │  8d    │  a2    │  34    │  ← Row 3
  └────────┴────────┴────────┴────────┘
```

The key is arranged the same way:
```
Key: 2b 7e 15 16 28 ae d2 a6 ab f7 15 88 09 cf 4f 3c

Key matrix:
     Col 0    Col 1    Col 2    Col 3
  ┌────────┬────────┬────────┬────────┐
  │  2b    │  28    │  ab    │  09    │
  │  7e    │  ae    │  f7    │  cf    │
  │  15    │  d2    │  15    │  4f    │
  │  16    │  a6    │  88    │  3c    │
  └────────┴────────┴────────┴────────┘
```

---

## 3. AES-128 Encryption: The 10-Round Process

```
          Input (128-bit plaintext)
               │
               ▼
      ┌─────────────────┐
      │  AddRoundKey     │  ← Initial round key (Round 0)
      │  (XOR with key)  │
      └────────┬────────┘
               │
     ┌─────────▼─────────┐
     │   ROUND 1-9       │  ← Repeat 9 times
     │   (Full rounds)    │
     │                    │
     │  ┌──────────────┐ │
     │  │ 1. SubBytes  │ │  ← Substitute each byte using S-box
     │  │ 2. ShiftRows │ │  ← Shift rows of the state
     │  │ 3. MixColumns│ │  ← Mix column data mathematically
     │  │ 4. AddRoundKey│ │  ← XOR with round key
     │  └──────────────┘ │
     │                    │
     └─────────┬─────────┘
               │
     ┌─────────▼─────────┐
     │   ROUND 10        │  ← Final round (NO MixColumns!)
     │   (Final round)   │
     │                    │
     │  ┌──────────────┐ │
     │  │ 1. SubBytes  │ │
     │  │ 2. ShiftRows │ │
     │  │ 3. AddRoundKey│ │  ← No MixColumns in the last round!
     │  └──────────────┘ │
     │                    │
     └─────────┬─────────┘
               │
               ▼
       Output (128-bit ciphertext)
```

**Key points:**
- There are **11 round keys** total (one initial + one per round)
- The **final round** skips MixColumns — this is by design and important for the math to work out in decryption
- Each operation is **invertible** — there's a reverse operation for decryption

---

## 4. Step 1: AddRoundKey — XOR with the Key

**AddRoundKey** is the simplest step: XOR the state matrix with the round key, byte by byte.

### How XOR Works (Refresher)

```
XOR (⊕): Same bits → 0, Different bits → 1

  0 ⊕ 0 = 0
  0 ⊕ 1 = 1
  1 ⊕ 0 = 1
  1 ⊕ 1 = 0
```

### Why XOR for Encryption?

XOR has a magical property: **it's its own inverse!**

```
Data ⊕ Key = Ciphertext
Ciphertext ⊕ Key = Data     (back to original!)

Example: 0xA3 ⊕ 0x5F = 0xFC
                 0xFC ⊕ 0x5F = 0xA3  ← Original recovered!
```

This is why XOR is perfect for encryption — use the same operation to encrypt and decrypt.

### Numerical Example: Initial AddRoundKey

```
State (plaintext):         Round Key 0 (original key):
  32  88  31  e0             2b  28  ab  09
  43  5a  31  37             7e  ae  f7  cf
  f6  30  98  07             15  d2  15  4f
  a8  8d  a2  34             16  a6  88  3c

XOR each byte:
  32⊕2b  88⊕28  31⊕ab  e0⊕09     19  a0  9a  e9
  43⊕7e  5a⊕ae  31⊕f7  37⊕cf  =  3d  f4  c6  f8
  f6⊕15  30⊕d2  98⊕15  07⊕4f     e3  e2  8d  48
  a8⊕16  8d⊕a6  a2⊕88  34⊕3c     be  2b  2a  08

Let's verify one byte: 32 ⊕ 2b = ?
  32 = 0011 0010
  2b = 0010 1011
  ──────────────
  XOR= 0001 1001 = 19 ✓
```

---

## 5. Step 2: SubBytes — S-Box Substitution

**SubBytes** replaces each byte in the state with another byte using a fixed lookup table called the **S-box** (Substitution Box).

### What is the S-Box?

The S-box is a 256-entry table that maps each possible byte value (0x00 to 0xFF) to another byte value. It's based on the mathematical inverse in GF(2^8) (Galois Field) followed by an affine transformation.

**You don't need to understand the math** — just know that it's a carefully designed lookup table with important cryptographic properties:
- No byte maps to itself (S[x] ≠ x for all x)
- No byte maps to its bitwise complement
- The mapping is highly non-linear (makes cryptanalysis difficult)

### Partial S-Box Table

```
        │ 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
    ────┼────────────────────────────────────────────────────
    0x  │ 63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab 76
    1x  │ ca 82 c9 7d fa 59 47 f0 ad d4 a2 af 9c a4 72 c0
    2x  │ b7 fd 93 26 36 3f f7 cc 34 a5 e5 f1 71 d8 31 15
    3x  │ 04 c7 23 c3 18 96 05 9a 07 12 80 e2 eb 27 b2 75
    4x  │ 09 83 2c 1a 1b 6e 5a a0 52 3b d6 b3 29 e3 2f 84
    5x  │ 53 d1 00 ed 20 fc b1 5b 6a cb be 39 4a 4c 58 cf
    ...
    9x  │ b8 01 10 c4 19 de b6 69 f3 3e 2e 1f 0d b0 54 bb
    Ax  │ 16 63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab
    ...
```

### How to Use the S-Box

To look up a byte, split it into two hex digits (nibbles):
- **Upper nibble** = row
- **Lower nibble** = column

**Example: SubBytes(0x19)**
- Row = 1, Column = 9
- S-box[1][9] = **d4**

**Example: SubBytes(0x53)**
- Row = 5, Column = 3
- S-box[5][3] = **ed**

### Numerical Example: SubBytes on the State After AddRoundKey

```
State before SubBytes:       State after SubBytes:
  19  a0  9a  e9               d4  e0  b8  1e
  3d  f4  c6  f8       →      27  bf  b4  41
  e3  e2  8d  48               11  98  5d  52
  be  2b  2a  08               ae  f1  e5  30

Let's verify: SubBytes(0x19) → looking up row=1, col=9 in S-box → 0xd4 ✓
              SubBytes(0xbe) → looking up row=B, col=E in S-box → 0xae ✓
```

---

## 6. Step 3: ShiftRows — Rotating the Rows

**ShiftRows** cyclically shifts each row of the state to the left by different amounts:

```
Row 0: No shift         (0 positions)
Row 1: Shift left by 1  (1 position)
Row 2: Shift left by 2  (2 positions)
Row 3: Shift left by 3  (3 positions)
```

### Visual Diagram

```
Before ShiftRows:                  After ShiftRows:
  d4  e0  b8  1e                     d4  e0  b8  1e   ← Row 0: no shift
  27  bf  b4  41          →          bf  b4  41  27   ← Row 1: shift left 1
  11  98  5d  52                     5d  52  11  98   ← Row 2: shift left 2
  ae  f1  e5  30                     30  ae  f1  e5   ← Row 3: shift left 3
```

### What Does "Shift Left by 1" Mean?

```
Original Row 1:  [27] [bf] [b4] [41]
                  ↓
        Move first element to the end:
Shifted Row 1:   [bf] [b4] [41] [27]
```

### What Does "Shift Left by 2" Mean?

```
Original Row 2:  [11] [98] [5d] [52]
                  ↓
        Move first TWO elements to the end:
Shifted Row 2:   [5d] [52] [11] [98]
```

### What Does "Shift Left by 3" Mean?

```
Original Row 3:  [ae] [f1] [e5] [30]
                  ↓
        Move first THREE elements to the end (same as shifting RIGHT by 1):
Shifted Row 3:   [30] [ae] [f1] [e5]
```

### Why ShiftRows?

ShiftRows provides **diffusion** — it spreads bytes from one column into different columns. Without ShiftRows, each column would be processed independently, and an attacker could break the cipher one column at a time. ShiftRows ensures that after a few rounds, every output byte depends on every input byte.

---

## 7. Step 4: MixColumns — Galois Field Magic

**MixColumns** is the most mathematically complex step. It mixes the four bytes in each column using multiplication in a special number system called **GF(2^8)** (Galois Field with 256 elements).

### The Core Idea

Each column of 4 bytes is treated as a polynomial and multiplied by a fixed polynomial. Don't worry about the full math — here's the practical formula:

**For each column [a₀, a₁, a₂, a₃], compute:**

```
b₀ = (2·a₀) ⊕ (3·a₁) ⊕ (1·a₂) ⊕ (1·a₃)
b₁ = (1·a₀) ⊕ (2·a₁) ⊕ (3·a₂) ⊕ (1·a₃)
b₂ = (1·a₀) ⊕ (1·a₁) ⊕ (2·a₂) ⊕ (3·a₃)
b₃ = (1·a₀) ⊕ (1·a₁) ⊕ (1·a₂) ⊕ (2·a₃)
```

Where:
- `⊕` means XOR
- `1·x` means just x (no change)
- `2·x` means **xtime(x)** — a specific GF(2^8) operation
- `3·x` means `2·x ⊕ x`

### What is xtime (Multiply by 2 in GF(2^8))?

Multiplying by 2 in GF(2^8) is simple:

1. **Shift the byte left by 1 bit** (like normal multiply-by-2)
2. **If the original MSB was 1**, XOR the result with **0x1B**

```
xtime(byte):
  result = byte << 1        // shift left
  if (byte & 0x80):         // if MSB was 1
    result = result ^ 0x1B  // XOR with 0x1B (the "reducing polynomial")
  return result & 0xFF      // keep only 8 bits
```

### Numerical Example: xtime

```
xtime(0xd4):
  0xd4 = 1101_0100
  Shift left: 1_1010_1000 → take lower 8 bits → 1010_1000 = 0xA8
  MSB was 1? Yes (0xd4 starts with 1)
  0xA8 ⊕ 0x1B = 1010_1000 ⊕ 0001_1011 = 1011_0011 = 0xB3

  So xtime(0xd4) = 0xB3

xtime(0xbf):
  0xbf = 1011_1111
  Shift left: 1_0111_1110 → 0111_1110 = 0x7E
  MSB was 1? Yes
  0x7E ⊕ 0x1B = 0111_1110 ⊕ 0001_1011 = 0110_0101 = 0x65

  So xtime(0xbf) = 0x65
```

### Multiply by 3 in GF(2^8)

```
gm3(x) = gm2(x) ⊕ x = xtime(x) ⊕ x
```

### Numerical Example: MixColumns on Column 0

After ShiftRows, column 0 is: [d4, bf, 5d, 30]

```
a₀ = 0xd4, a₁ = 0xbf, a₂ = 0x5d, a₃ = 0x30

Step 1: Calculate gm2 (xtime) for each:
  gm2(0xd4) = 0xB3  (calculated above)
  gm2(0xbf) = 0x65  (calculated above)
  gm2(0x5d) = 0xBA  (0x5d = 0101_1101, shift → 1011_1010, MSB=0, so just 0xBA)
  gm2(0x30) = 0x60  (0x30 = 0011_0000, shift → 0110_0000, MSB=0, so just 0x60)

Step 2: Calculate gm3 = gm2 ⊕ original:
  gm3(0xd4) = 0xB3 ⊕ 0xd4 = 0x67
  gm3(0xbf) = 0x65 ⊕ 0xbf = 0xDA
  gm3(0x5d) = 0xBA ⊕ 0x5d = 0xE7
  gm3(0x30) = 0x60 ⊕ 0x30 = 0x50

Step 3: Compute output:
  b₀ = gm2(d4) ⊕ gm3(bf) ⊕ 5d ⊕ 30
     = 0xB3    ⊕ 0xDA    ⊕ 0x5d ⊕ 0x30
     = B3⊕DA⊕5d⊕30

  Let's compute step by step:
  0xB3 ⊕ 0xDA = 0x69
  0x69 ⊕ 0x5d = 0x34
  0x34 ⊕ 0x30 = 0x04

  So b₀ = 0x04
```

This process is repeated for b₁, b₂, b₃, and then for all 4 columns.

### In the Verilog Code

In `aes_encipher_block.v`, the Galois field multiplications are implemented as Verilog functions:

```verilog
function [7:0] gm2(input [7:0] op);
    gm2 = {op[6:0], 1'b0} ^ (8'h1b & {8{op[7]}});
endfunction

function [7:0] gm3(input [7:0] op);
    gm3 = gm2(op) ^ op;
endfunction
```

`{op[6:0], 1'b0}` shifts left by 1. `{8{op[7]}}` creates 8 copies of the MSB — if MSB=1, this becomes 0xFF; if MSB=0, this becomes 0x00. AND-ing with 0x1B gives either 0x1B or 0x00, achieving the conditional XOR.

---

## 8. Key Expansion — Generating Round Keys

AES-128 needs **11 round keys** (one initial + one per round), but we start with only **one 128-bit key**. The **Key Expansion** (also called Key Schedule) generates all 11 round keys from the original key.

### Overview

```
Original Key (128 bits = 4 words of 32 bits)
  │
  ├── Round Key 0  (= original key itself)
  ├── Round Key 1  (derived from RK0)
  ├── Round Key 2  (derived from RK1)
  ├── ...
  └── Round Key 10 (derived from RK9)
```

Each round key is 128 bits (4 words × 32 bits per word).

### The Algorithm

AES represents the key as an array of **32-bit words** called `W[i]`.

For AES-128: W[0] to W[3] = the original key, and W[4] to W[43] = expanded key.

**Generation rules:**

```
For i = 4 to 43:
    If (i mod 4 == 0):
        W[i] = W[i-4] ⊕ SubWord(RotWord(W[i-1])) ⊕ Rcon[i/4]
    Else:
        W[i] = W[i-4] ⊕ W[i-1]
```

Where:
- **RotWord**: Rotate the 4 bytes left by 1: [a,b,c,d] → [b,c,d,a]
- **SubWord**: Apply the S-box to each of the 4 bytes
- **Rcon**: Round constant — a fixed value that changes each round

### Rcon Table

```
Rcon[1]  = 01 00 00 00
Rcon[2]  = 02 00 00 00
Rcon[3]  = 04 00 00 00
Rcon[4]  = 08 00 00 00
Rcon[5]  = 10 00 00 00
Rcon[6]  = 20 00 00 00
Rcon[7]  = 40 00 00 00
Rcon[8]  = 80 00 00 00
Rcon[9]  = 1B 00 00 00
Rcon[10] = 36 00 00 00
```

Each Rcon value is the previous one multiplied by 2 in GF(2^8) — the same xtime operation we saw in MixColumns!

### Complete Numerical Example: Expanding the NIST Key

Original key: `2b7e1516 28aed2a6 abf71588 09cf4f3c`

```
W[0] = 2b7e1516
W[1] = 28aed2a6
W[2] = abf71588
W[3] = 09cf4f3c
```

**Generating W[4] (i=4, i mod 4 == 0):**

```
Step 1: RotWord(W[3])
  W[3] = 09 cf 4f 3c
  RotWord → cf 4f 3c 09

Step 2: SubWord(cf 4f 3c 09)
  S-box(cf) = 8a
  S-box(4f) = 84
  S-box(3c) = eb
  S-box(09) = 01
  SubWord → 8a 84 eb 01

Step 3: XOR with Rcon[1] = 01 00 00 00
  8a84eb01 ⊕ 01000000 = 8b84eb01

Step 4: XOR with W[i-4] = W[0]
  W[4] = W[0] ⊕ 8b84eb01
       = 2b7e1516 ⊕ 8b84eb01
       = a0fafe17
```

**Generating W[5] (i=5, i mod 4 ≠ 0):**
```
W[5] = W[1] ⊕ W[4]
     = 28aed2a6 ⊕ a0fafe17
     = 88542cb1
```

**Generating W[6]:**
```
W[6] = W[2] ⊕ W[5]
     = abf71588 ⊕ 88542cb1
     = 23a33939
```

**Generating W[7]:**
```
W[7] = W[3] ⊕ W[6]
     = 09cf4f3c ⊕ 23a33939
     = 2a6c7605
```

**Round Key 1:** `W[4] | W[5] | W[6] | W[7]` = `a0fafe17 88542cb1 23a33939 2a6c7605`

### All 11 Round Keys for the NIST Key

```
Round Key  0: 2b7e1516 28aed2a6 abf71588 09cf4f3c  (original key)
Round Key  1: a0fafe17 88542cb1 23a33939 2a6c7605
Round Key  2: f2c295f2 7a96b943 5935807a 7359f67f
Round Key  3: 3d80477d 4716fe3e 1e237e44 6d7a883b
Round Key  4: ef44a541 a8525b7f b671253b db0bad00
Round Key  5: d4d1c6f8 7c839d87 caf2b8bc 11f915bc
Round Key  6: 6d88a37a 110b3efd dbf98641 ca0093fd
Round Key  7: 4e54f70e 5f5fc9f3 84a64fb2 4ea6dc4f
Round Key  8: ead27321 b58dbad2 312bf560 7f8d292f
Round Key  9: ac7766f3 19fadc21 28d12941 575c006e
Round Key 10: d014f9a8 c9ee2589 e13f0cc8 b6630ca6
```

---

## 9. Complete AES-128 Encryption Example (NIST)

Let's trace the NIST test vector used in our project:

```
Plaintext: 3243f6a8 885a308d 313198a2 e0370734
Key:       2b7e1516 28aed2a6 abf71588 09cf4f3c
```

### Initial AddRoundKey (XOR with Round Key 0)

```
State = Plaintext ⊕ Key
      = 3243f6a8 ⊕ 2b7e1516 | 885a308d ⊕ 28aed2a6 | ...

State after initial AddRoundKey:
  19  a0  9a  e9
  3d  f4  c6  f8
  e3  e2  8d  48
  be  2b  2a  08
```

### Round 1

**After SubBytes:**
```
  d4  e0  b8  1e
  27  bf  b4  41
  11  98  5d  52
  ae  f1  e5  30
```

**After ShiftRows:**
```
  d4  e0  b8  1e      (row 0: no shift)
  bf  b4  41  27      (row 1: shift left 1)
  5d  52  11  98      (row 2: shift left 2)
  30  ae  f1  e5      (row 3: shift left 3)
```

**After MixColumns:**
```
  04  e0  48  28
  66  cb  f8  06
  81  19  d3  26
  e5  9a  7a  4c
```

**After AddRoundKey (Round Key 1 = a0fafe17 88542cb1 23a33939 2a6c7605):**
```
  a4  68  6b  02
  9c  9f  5b  6a
  7f  35  ea  50
  f2  2b  43  49
```

### Rounds 2-9 (Continue similarly...)

Each round applies the same four operations with the corresponding round key.

### Round 10 (Final — NO MixColumns!)

After SubBytes → ShiftRows → AddRoundKey (with Round Key 10):

```
Final Ciphertext:
  39  02  dc  19
  25  dc  11  6a
  84  09  85  0b
  1d  fb  97  32

Arranged as bytes: 39 25 84 1d 02 dc 09 fb dc 11 85 97 19 6a 0b 32
```

**This matches the expected NIST ciphertext exactly!** This is the test vector used in `tb_aes_ctrl.v` to verify the hardware implementation.

---

## 10. AES Decryption — Reversing Everything

Decryption applies the **inverse** of each operation in **reverse order**:

```
          Input (128-bit ciphertext)
               │
               ▼
      ┌─────────────────┐
      │  AddRoundKey     │  ← Round Key 10 (last key)
      └────────┬────────┘
               │
     ┌─────────▼─────────┐
     │   ROUND 9-1       │  ← Repeat 9 times (reverse)
     │                    │
     │  1. InvShiftRows  │  ← Reverse row shifts
     │  2. InvSubBytes   │  ← Use inverse S-box
     │  3. AddRoundKey   │  ← XOR is its own inverse!
     │  4. InvMixColumns │  ← Reverse column mixing
     │                    │
     └─────────┬─────────┘
               │
     ┌─────────▼─────────┐
     │   ROUND 0         │  ← Final decryption round
     │                    │
     │  1. InvShiftRows  │
     │  2. InvSubBytes   │
     │  3. AddRoundKey   │  ← Round Key 0 (original key)
     │                    │
     └─────────┬─────────┘
               │
               ▼
       Output (128-bit plaintext)
```

### Inverse Operations

| Encryption | Decryption | How |
|-----------|------------|-----|
| SubBytes | InvSubBytes | Use the inverse S-box table (256-entry table, but different values) |
| ShiftRows | InvShiftRows | Shift rows **right** instead of left |
| MixColumns | InvMixColumns | Multiply by the inverse matrix (uses gm9, gm11, gm13, gm14) |
| AddRoundKey | AddRoundKey | **Same operation!** XOR is its own inverse |

### InvShiftRows

```
Row 0: No shift         (same as encryption)
Row 1: Shift RIGHT by 1 (opposite direction)
Row 2: Shift RIGHT by 2
Row 3: Shift RIGHT by 3
```

### InvMixColumns

Uses more complex GF(2^8) multiplications:

```
b₀ = (14·a₀) ⊕ (11·a₁) ⊕ (13·a₂) ⊕ (9·a₃)
b₁ = (9·a₀)  ⊕ (14·a₁) ⊕ (11·a₂) ⊕ (13·a₃)
b₂ = (13·a₀) ⊕ (9·a₁)  ⊕ (14·a₂) ⊕ (11·a₃)
b₃ = (11·a₀) ⊕ (13·a₁) ⊕ (9·a₂)  ⊕ (14·a₃)
```

These multiplications (by 9, 11, 13, 14) are built from repeated xtime operations:
```
gm2(x)  = xtime(x)
gm4(x)  = xtime(xtime(x))
gm8(x)  = xtime(xtime(xtime(x)))
gm9(x)  = gm8(x) ⊕ x
gm11(x) = gm8(x) ⊕ gm2(x) ⊕ x
gm13(x) = gm8(x) ⊕ gm4(x) ⊕ x
gm14(x) = gm8(x) ⊕ gm4(x) ⊕ gm2(x)
```

The Verilog code in `aes_decipher_block.v` implements all of these as functions.

---

## 11. Key Takeaways

1. **AES-128 uses a 4×4 byte state matrix**, filled column-by-column from the 16 input bytes.

2. **10 rounds** of transformations, each applying SubBytes → ShiftRows → MixColumns → AddRoundKey (except the last round skips MixColumns).

3. **SubBytes** is a non-linear byte substitution using a fixed 256-entry lookup table (S-box). This provides "confusion" — makes the relationship between key and ciphertext complex.

4. **ShiftRows** rotates rows by 0, 1, 2, 3 positions. This provides "diffusion" — spreads data across columns.

5. **MixColumns** mixes bytes within each column using GF(2^8) arithmetic. This further provides diffusion within columns.

6. **AddRoundKey** XORs the state with a round key. XOR is its own inverse, making it elegant for both encryption and decryption.

7. **Key Expansion** generates 11 round keys from the original 128-bit key using RotWord, SubWord, and Rcon operations.

8. **Decryption** reverses everything: InvShiftRows, InvSubBytes, AddRoundKey, InvMixColumns, with round keys applied in reverse order.

---

> **Next**: [Document 10 — AES S-Box and Inverse S-Box](10_AES_SBox_and_Inv_SBox.md) — See how the S-box lookup tables are implemented in Verilog hardware.
