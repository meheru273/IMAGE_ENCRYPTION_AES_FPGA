# Document 03: Project Architecture Overview

> **Goal**: By the end of this document, you will understand what this entire project does,
> how data flows from your PC through the FPGA and back, how all modules connect together,
> and get a basic understanding of what AES encryption is.

---

## Table of Contents
1. [What Does This Project Do?](#1-what-does-this-project-do)
2. [The Big Picture — End-to-End Data Flow](#2-the-big-picture--end-to-end-data-flow)
3. [What is AES Encryption? (Simple Explanation)](#3-what-is-aes-encryption-simple-explanation)
4. [What is ECB Mode?](#4-what-is-ecb-mode)
5. [Module Hierarchy — How Everything Connects](#5-module-hierarchy--how-everything-connects)
6. [The Numbers — Image Size and Block Count](#6-the-numbers--image-size-and-block-count)
7. [Brief Description of Every File in the Project](#7-brief-description-of-every-file-in-the-project)
8. [Key Takeaways](#8-key-takeaways)

---

## 1. What Does This Project Do?

This project builds a **hardware image encryption system** on an FPGA. Here's the simple version:

1. You have a **128×128 grayscale image** on your PC
2. You send it to the **Basys 3 FPGA board** over a USB cable
3. The FPGA **encrypts** the image using the **AES-128 algorithm** (a military-grade encryption standard)
4. The encrypted image is stored in the FPGA's **internal memory** (BRAM)
5. You can then tell the FPGA to **decrypt** the image and send it back to your PC
6. The original image is perfectly recovered

### Real-World Analogy

Imagine you have a secret photograph:
1. You put the photo into a **shredder** (encryption) — the shredded pieces look like random garbage
2. You store the shredded pieces in a **locked box** (BRAM)
3. When you need the photo back, a **magic un-shredder** (decryption) perfectly reassembles it
4. Only someone with the **right key** can use the un-shredder

The "key" in our project is the 128-bit number: `2b7e151628aed2a6abf7158809cf4f3c`

---

## 2. The Big Picture — End-to-End Data Flow

### Encryption Path (SW0 = 0, switch down)

```
YOUR PC                          BASYS 3 FPGA BOARD
┌──────────┐                     ┌──────────────────────────────────────────┐
│          │    USB Cable        │                                          │
│  Python  │  (serial data)     │  ┌─────────┐   ┌──────────────┐         │
│  Script  │ ──────────────────►│  │ UART RX │──►│ Pixel Buffer │         │
│          │   1 byte at a time │  │(uart_rx) │   │(pixel_buffer)│         │
│ (sends   │   115200 baud     │  └─────────┘   └──────┬───────┘         │
│  16384   │                    │                       │                   │
│  bytes)  │                    │            16 bytes assembled into       │
│          │                    │            128-bit block                  │
└──────────┘                    │                       │                   │
                                │                       ▼                   │
                                │               ┌──────────────┐           │
                                │               │  AES Controller│          │
                                │               │  (aes_ctrl)   │          │
                                │               │  ┌──────────┐│           │
                                │               │  │ AES Core ││           │
                                │               │  │(encrypt) ││           │
                                │               │  └──────────┘│           │
                                │               └──────┬───────┘           │
                                │                      │                    │
                                │            128-bit ciphertext             │
                                │                      │                    │
                                │                      ▼                    │
                                │               ┌──────────────┐           │
                                │               │  BRAM        │           │
                                │               │  (bram_ctrl) │           │
                                │               │  1024 × 128b │           │
                                │               │  = 16 KB     │           │
                                │               └──────────────┘           │
                                │                                          │
                                │  LED0 ON = encrypting                    │
                                │  LED2 ON = all 1024 blocks done          │
                                └──────────────────────────────────────────┘
```

### Decryption Path (SW0 = 1, switch up, press btnR)

```
YOUR PC                          BASYS 3 FPGA BOARD
┌──────────┐                     ┌──────────────────────────────────────────┐
│          │    USB Cable        │                                          │
│  Python  │  (serial data)     │  ┌─────────┐   ◄── byte-by-byte        │
│  Script  │ ◄──────────────────│  │ UART TX │       extraction from      │
│          │   1 byte at a time │  │(uart_tx) │       128-bit block       │
│ (receives│   115200 baud     │  └─────────┘                            │
│  16384   │                    │       ▲                                   │
│  bytes,  │                    │       │                                   │
│  saves   │                    │  ┌──────────────┐                        │
│  image)  │                    │  │  AES Controller│                       │
└──────────┘                    │  │  (aes_ctrl)   │                       │
                                │  │  ┌──────────┐│                        │
                                │  │  │ AES Core ││                        │
                                │  │  │(decrypt) ││                        │
                                │  │  └──────────┘│                        │
                                │  └──────┬───────┘                        │
                                │         ▲                                 │
                                │         │                                 │
                                │  ┌──────────────┐                        │
                                │  │  BRAM        │                        │
                                │  │  (bram_ctrl) │                        │
                                │  │  reads back  │                        │
                                │  │  ciphertext  │                        │
                                │  └──────────────┘                        │
                                │                                          │
                                │  LED1 ON = decrypting                    │
                                │  LED2 ON = all 1024 blocks done          │
                                └──────────────────────────────────────────┘
```

### Step-by-Step: What Happens When You Encrypt an Image

1. **You run the Python script** on your PC — it loads a 128×128 grayscale image (16,384 bytes)
2. **The script sends bytes** over USB at 115,200 baud, one byte at a time
3. **UART RX module** (`uart_rx.v`) receives each byte from the serial line
4. **Pixel Buffer** (`pixel_buffer.v`) collects 16 bytes into a 128-bit block
5. **When 16 bytes are ready**, the pixel buffer signals `block_valid`
6. **Top module** (`top.v`) sees the valid block and sends it to the AES controller
7. **AES Controller** (`aes_ctrl.v`) feeds the block to the AES core for encryption
8. **AES Core** (`aes_core.v`) encrypts the 128-bit block using 10 rounds of transformations
9. **When encryption is done**, the ciphertext is written to BRAM
10. **Repeat** steps 3-9 for all 1024 blocks
11. **LED2 lights up** — encryption complete!

### Step-by-Step: What Happens When You Decrypt

1. **You flip SW0 UP** (decrypt mode) and **press btnR**
2. **Top module** starts reading BRAM from address 0
3. **Ciphertext block** from BRAM is sent to AES controller
4. **AES controller** decrypts the block (reverses the encryption)
5. **Decrypted 128-bit block** is broken into 16 individual bytes
6. **Each byte is sent** through UART TX to the PC, one at a time
7. **Repeat** for all 1024 blocks
8. **Python script** on PC receives 16,384 bytes and reconstructs the image
9. **LED2 lights up** — decryption complete!

---

## 3. What is AES Encryption? (Simple Explanation)

### AES = Advanced Encryption Standard

AES is the most widely used encryption algorithm in the world. It was standardized by the U.S. government (NIST) in 2001 and is used everywhere:
- Wi-Fi (WPA2/WPA3)
- HTTPS websites
- VPNs
- Hard disk encryption (BitLocker, FileVault)
- Banking transactions

### The Core Idea

AES takes two inputs:
1. **Plaintext** — the data you want to protect (128 bits = 16 bytes)
2. **Key** — a secret key that only you know (128, 192, or 256 bits)

And produces:
- **Ciphertext** — the scrambled data (also 128 bits)

```
┌──────────────────────────┐
│      AES Encryption      │
│                          │
│  Plaintext ──────┐      │
│  (128 bits)      │      │
│                  ▼      │
│             ┌────────┐  │
│  Key ──────►│  AES   │──┼──► Ciphertext
│  (128 bits) │ Engine │  │    (128 bits)
│             └────────┘  │
│                          │
└──────────────────────────┘
```

**Key properties:**
- **Same key encrypts and decrypts** — AES is a "symmetric" cipher
- **Without the key, you CANNOT recover the plaintext** — the ciphertext looks like random noise
- **With the key, decryption perfectly recovers the original data**
- **The transformation is deterministic** — same plaintext + same key = same ciphertext, always

### Simple Analogy: The Rubik's Cube

Think of AES encryption like scrambling a Rubik's Cube:
1. **Plaintext** = the solved cube (organized, readable)
2. **Key** = a specific sequence of moves (e.g., "R U R' F D2")
3. **Encryption** = applying those moves → cube looks random
4. **Ciphertext** = the scrambled cube
5. **Decryption** = applying the **reverse** moves → cube is solved again

Without knowing the exact sequence of moves (the key), you can't solve it.

### AES-128 Specifics

Our project uses **AES-128**, which means:
- Key length: **128 bits** (16 bytes)
- Block size: **128 bits** (16 bytes) — AES always processes 16 bytes at a time
- Number of rounds: **10** — the data is scrambled 10 times

Each "round" applies 4 transformations:
1. **SubBytes** — substitute each byte using a lookup table (S-box)
2. **ShiftRows** — shift rows of the data matrix
3. **MixColumns** — mix columns using mathematical operations
4. **AddRoundKey** — XOR with a round-specific key

(We'll explain each of these in detail in Documents 09-12)

### Numerical Example

Our project uses this key (a standard NIST test key):
```
Key = 2b 7e 15 16 28 ae d2 a6 ab f7 15 88 09 cf 4f 3c
```

If we encrypt this plaintext:
```
Plaintext = 32 43 f6 a8 88 5a 30 8d 31 31 98 a2 e0 37 07 34
```

AES-128 produces:
```
Ciphertext = 39 25 84 1d 02 dc 09 fb dc 11 85 97 19 6a 0b 32
```

The ciphertext looks completely random — no pattern visible. But with the same key, decryption recovers the exact plaintext.

---

## 4. What is ECB Mode?

AES processes exactly **16 bytes at a time** (one block). But our image is **16,384 bytes** (1024 blocks). How do we handle multiple blocks?

There are several "modes of operation" for block ciphers. Our project uses **ECB (Electronic Codebook)** mode — the simplest approach.

### How ECB Works

Each 16-byte block is encrypted **independently** with the same key:

```
Image data: [Block 0][Block 1][Block 2]...[Block 1023]
                │         │         │            │
                ▼         ▼         ▼            ▼
            ┌──────┐ ┌──────┐ ┌──────┐     ┌──────┐
  Key ──────┤ AES  │ │ AES  │ │ AES  │     │ AES  │
            └──┬───┘ └──┬───┘ └──┬───┘     └──┬───┘
               │         │         │            │
               ▼         ▼         ▼            ▼
Encrypted: [Cipher 0][Cipher 1][Cipher 2]...[Cipher 1023]
```

### ECB's Known Weakness (Important for Understanding)

ECB has a well-known weakness: **identical plaintext blocks produce identical ciphertext blocks**.

If your image has large uniform regions (like a white background), those regions will all encrypt to the same ciphertext block. An attacker can see the pattern, even without knowing the actual data:

```
Original Image         ECB Encrypted          What attacker sees
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│████████████████│    │▒▒▒▒▒▒▒▒▒▒▒▒▒▒│    │ I can see the  │
│██ ♠  HELLO ██│    │▓▓░░▒▒░░▓▓▒▒▓▓│    │ shape, even    │
│██          ██│    │▓▓░░░░░░▓▓░░▓▓│    │ though I can't │
│████████████████│    │▒▒▒▒▒▒▒▒▒▒▒▒▒▒│    │ read the text  │
└────────────────┘    └────────────────┘    └────────────────┘
The background encrypts to the same pattern → outline visible!
```

This is the famous "ECB Penguin" problem. We'll discuss this more in Document 16 (Drawbacks and Future Work) and how better modes like CBC or CTR fix this.

**For our project**, ECB is used because:
- It's the simplest to implement in hardware
- It demonstrates the AES algorithm clearly
- Each block can be processed independently (no dependencies)
- It's a great starting point for learning

---

## 5. Module Hierarchy — How Everything Connects

### Module Tree

```
top.v (Top-Level System Module)
 │
 ├── uart_rx.v (UART Receiver)
 │   Receives serial bytes from PC
 │
 ├── uart_tx.v (UART Transmitter)
 │   Sends serial bytes to PC
 │
 ├── pixel_buffer.v (Pixel Buffer)
 │   Collects 16 bytes → 128-bit block
 │
 ├── aes_ctrl.v (AES Controller)
 │   │  FSM that drives the AES core
 │   │
 │   └── aes_core.v (AES Core)
 │       │  The central AES engine
 │       │
 │       ├── aes_encipher_block.v (Encryption Datapath)
 │       │   Implements SubBytes, ShiftRows, MixColumns, AddRoundKey
 │       │
 │       ├── aes_decipher_block.v (Decryption Datapath)
 │       │   │  Implements InvSubBytes, InvShiftRows, InvMixColumns, AddRoundKey
 │       │   │
 │       │   └── aes_inv_sbox.v (Inverse S-Box)
 │       │       256-entry lookup table for inverse byte substitution
 │       │
 │       ├── aes_key_mem.v (Key Expansion / Schedule)
 │       │   Expands 128-bit key into 11 round keys
 │       │
 │       └── aes_sbox.v (Forward S-Box)
 │           256-entry lookup table for byte substitution
 │           (shared between encipher block and key memory)
 │
 └── bram_ctrl.v (BRAM Controller)
     1024 × 128-bit memory for storing encrypted blocks
```

### Signal Flow Diagram

```
                          top.v
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  uart_rx_pin ──►┌──────────┐ rx_data[7:0]                  │
│                 │ uart_rx  ├──────────┐ rx_valid            │
│                 └──────────┘          │                      │
│                                       ▼                      │
│                              ┌──────────────┐                │
│                              │ pixel_buffer │                │
│                              │              │                │
│                              │ 16 bytes →  │                │
│                              │ 128-bit block│                │
│                              └──────┬───────┘                │
│                                     │ pbuf_block[127:0]      │
│                                     │ pbuf_valid             │
│     AES_KEY ─────────────┐          │                        │
│     (constant 128-bit)   │          ▼                        │
│                          │  ┌──────────────┐                 │
│     aes_block_in ───────►│  │  aes_ctrl   │                 │
│     aes_mode (enc/dec) ─►│  │  (has aes_  │                 │
│     aes_start ──────────►│  │   core      │                 │
│                          │  │   inside)   │                 │
│                          │  └──────┬───────┘                 │
│                          │         │ aes_block_out[127:0]    │
│                          │         │ aes_done                │
│                          │         │                         │
│           ┌──────────────┼─────────┘                         │
│           │              │                                   │
│           ▼              │                                   │
│  ┌──────────────┐        │                                   │
│  │  bram_ctrl   │◄───────┘ (address, data, wr/rd enable)    │
│  │  1024×128-bit│                                            │
│  └──────┬───────┘                                            │
│         │ bram_dout[127:0]                                   │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐    tx_data[7:0]    ┌──────────┐           │
│  │ byte extract │───────────────────►│ uart_tx  ├──► uart_tx_pin
│  │ (15-idx)*8   │    tx_send         └──────────┘           │
│  └──────────────┘                                            │
│                                                              │
│  mode_sw ─── SW0 (encrypt/decrypt)                          │
│  rst_btn ─── center button (reset)                          │
│  btn_start ── right button (start decrypt)                  │
│  status_led[3:0] ── 4 LEDs                                  │
└─────────────────────────────────────────────────────────────┘
```

### Custom vs Third-Party Modules

| Module | Origin | Purpose |
|--------|--------|---------|
| `top.v` | **Custom** | System integration and FSM |
| `uart_rx.v` | **Custom** | Receives bytes from PC |
| `uart_tx.v` | **Custom** | Sends bytes to PC |
| `pixel_buffer.v` | **Custom** | 16-byte to 128-bit assembler |
| `aes_ctrl.v` | **Custom** | FSM controlling the AES core |
| `bram_ctrl.v` | **Custom** | BRAM memory wrapper |
| `aes_core.v` | **Secworks** (BSD license) | AES encryption/decryption engine |
| `aes_encipher_block.v` | **Secworks** | AES encryption datapath |
| `aes_decipher_block.v` | **Secworks** | AES decryption datapath |
| `aes_key_mem.v` | **Secworks** | Key expansion |
| `aes_sbox.v` | **Secworks** | Forward S-box lookup |
| `aes_inv_sbox.v` | **Secworks** | Inverse S-box lookup |
| `aes.v` | **Secworks** | Register-mapped wrapper (NOT used in our system) |

The custom modules (top, uart, pixel_buffer, aes_ctrl, bram_ctrl) are the "glue" that integrates the Secworks AES IP core into a complete system with UART communication and memory storage.

---

## 6. The Numbers — Image Size and Block Count

Understanding the numbers is critical. Let's do the math:

### Image Properties
```
Image width:  128 pixels
Image height: 128 pixels
Pixel depth:  8 bits (1 byte) per pixel (grayscale: 0=black, 255=white)

Total pixels: 128 × 128 = 16,384 pixels
Total bytes:  16,384 × 1 = 16,384 bytes = 16 KB
```

### AES Block Properties
```
AES block size: 128 bits = 16 bytes

Number of blocks: 16,384 bytes ÷ 16 bytes/block = 1024 blocks
```

### BRAM Storage
```
Each BRAM entry: 128 bits (one AES block)
Number of entries: 1024
Total storage: 1024 × 128 bits = 131,072 bits = 16,384 bytes = 16 KB

BRAM address width: log2(1024) = 10 bits (addresses 0 to 1023)
```

### UART Timing
```
Baud rate: 115,200 bits per second
Each byte: 1 start + 8 data + 1 stop = 10 bits
Bytes per second: 115,200 / 10 = 11,520 bytes/sec

Time to send entire image: 16,384 / 11,520 ≈ 1.42 seconds
```

### AES Processing Time (per block)
```
AES key expansion: ~54 clock cycles (once)
AES encrypt/decrypt: ~54 clock cycles per block
Clock frequency: 100 MHz = 10 ns per cycle

Time per block: ~54 × 10 ns = 540 ns = 0.54 μs

Total encryption time: 1024 × 540 ns ≈ 0.55 ms (half a millisecond!)
```

**Key insight**: The FPGA can encrypt the entire image in ~0.55 ms, but sending/receiving via UART takes ~1.42 seconds. **UART is the bottleneck**, not AES!

### Summary Table

```
┌────────────────────────────────────────────────────┐
│               Numerical Parameters                  │
├──────────────────────┬─────────────────────────────┤
│ Image Size           │ 128 × 128 pixels            │
│ Bytes per Pixel      │ 1 (8-bit grayscale)         │
│ Total Image Bytes    │ 16,384 (16 KB)              │
│ AES Block Size       │ 128 bits (16 bytes)         │
│ Total Blocks         │ 1,024                       │
│ AES Key Size         │ 128 bits (16 bytes)         │
│ AES Rounds           │ 10                          │
│ BRAM Entries         │ 1,024 × 128 bits            │
│ BRAM Address Width   │ 10 bits                     │
│ UART Baud Rate       │ 115,200 bps                 │
│ UART Transfer Time   │ ~1.42 seconds (full image)  │
│ AES Encrypt Time     │ ~0.55 ms (full image)       │
│ System Clock         │ 100 MHz (10 ns period)      │
└──────────────────────┴─────────────────────────────┘
```

---

## 7. Brief Description of Every File in the Project

### Root Directory Files

| File | Description |
|------|-------------|
| `README.md` | Project overview and usage instructions |
| `LICENSE` | BSD 2-Clause license (from Secworks) |
| `aes.core` | FuseSoC core description file (metadata for IP management) |
| `.gitignore` | Files ignored by Git (simulation outputs, vendor dirs) |
| `.gitattributes` | Tells GitHub to detect `.v` files as Verilog |

### `constraints/` Directory

| File | Description |
|------|-------------|
| `basys3.xdc` | Pin assignments and clock constraints for the Basys 3 board |

### `data/` Directory

| File | Description |
|------|-------------|
| `sky130.tcl` | Configuration for ASIC synthesis using SKY130 PDK (not used for FPGA) |

### `host/` Directory

| File | Description |
|------|-------------|
| `uart_host.py` | Python script to send/receive images over UART from PC |

### `src/rtl/` Directory (Hardware Source Code)

| File | Description | Used In System? |
|------|-------------|-----------------|
| `top.v` | Top-level integration — system FSM, connects everything | YES — top module |
| `uart_rx.v` | UART receiver — serial to parallel conversion | YES |
| `uart_tx.v` | UART transmitter — parallel to serial conversion | YES |
| `pixel_buffer.v` | Collects 16 bytes into one 128-bit AES block | YES |
| `aes_ctrl.v` | FSM that drives aes_core with proper handshaking | YES |
| `aes_core.v` | Central AES engine — muxes encrypt/decrypt paths | YES (inside aes_ctrl) |
| `aes_encipher_block.v` | AES encryption datapath (SubBytes, ShiftRows, etc.) | YES (inside aes_core) |
| `aes_decipher_block.v` | AES decryption datapath (inverse operations) | YES (inside aes_core) |
| `aes_key_mem.v` | Key expansion — generates 11 round keys from 1 key | YES (inside aes_core) |
| `aes_sbox.v` | Forward S-box lookup table (256 entries) | YES (inside aes_core) |
| `aes_inv_sbox.v` | Inverse S-box lookup table (256 entries) | YES (inside decipher block) |
| `aes.v` | Register-mapped AES wrapper from Secworks | NO — not used in our system |

### `src/tb/` Directory (Testbenches)

| File | Tests |
|------|-------|
| `tb_top.v` | Full system: send bytes via UART, encrypt, decrypt, verify roundtrip |
| `tb_aes_ctrl.v` | AES controller FSM with NIST test vectors |
| `tb_uart_rx.v` | UART receiver with 4 test bytes |
| `tb_uart_tx.v` | UART transmitter with 4 test bytes |
| `tb_pixel_buffer.v` | Pixel buffer with two test cases |
| `tb_bram_ctrl.v` | BRAM write/read at 3 addresses |
| `tb_aes.v` | Secworks AES wrapper with 20 NIST test vectors |
| `tb_aes_core.v` | Secworks AES core with 20 NIST test vectors |
| `tb_aes_encipher_block.v` | Encipher block with 8 test vectors |
| `tb_aes_decipher_block.v` | Decipher block with 8 test vectors |
| `tb_aes_key_mem.v` | Key expansion with 9 different keys |

### `src/model/python/` Directory (Reference Models)

| File | Description |
|------|-------------|
| `aes.py` | Complete Python AES implementation — use to verify hardware results |
| `aes_key_gen.py` | Python AES key expansion — verify round keys |
| `rcon.py` | Another key expansion variant with additional test vectors |

### `toolruns/` Directory

| File | Description |
|------|-------------|
| `Makefile` | Build targets for Icarus Verilog simulation and Verilator linting |

---

## 8. Key Takeaways

1. **This project encrypts a 128×128 grayscale image** using the AES-128 algorithm on an FPGA, communicating with a PC over UART.

2. **The data flow is**: PC → UART RX → Pixel Buffer → AES Encrypt → BRAM → AES Decrypt → UART TX → PC.

3. **AES-128 processes 16 bytes at a time**, using a 128-bit key and 10 rounds of transformations.

4. **The image is 16 KB = 1024 AES blocks**, all stored in FPGA BRAM.

5. **ECB mode** encrypts each block independently — simple but has a known pattern-leaking weakness.

6. **The FPGA can encrypt in ~0.5 ms**, but UART transfer takes ~1.4 seconds — **UART is the bottleneck**.

7. **The project has two origins**: custom modules (UART, buffer, controller, top) and Secworks open-source AES IP cores.

---

> **Next**: [Document 04 — UART Protocol Deep Dive](04_UART_Protocol_Deep_Dive.md) — Learn exactly how serial communication works before diving into the UART Verilog code.
