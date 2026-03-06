# AES-128 Transparent Memory Encryption on FPGA

A hardware AES-128 image encryption system implemented on the **Digilent Basys 3** (Artix-7 XC7A35T) using Vivado 2023.1. A 128×128 grayscale image is streamed from a PC over UART, encrypted block-by-block using the [secworks AES core](https://github.com/secworks/aes), stored in on-chip BRAM, then decrypted on demand and streamed back.

---

## System Overview

```
PC (Python)  ──UART──►  uart_rx.v
                              │
                       pixel_buffer.v    (16 bytes → 128-bit block)
                              │
                       aes_ctrl.v FSM    (drives secworks aes_core)
                              │
               ┌──────────────┴──────────────┐
          [ENCRYPT]                      [DECRYPT]
               │                              │
          bram_ctrl.v                   bram_ctrl.v
          (write cipher)                (read cipher)
               │                              │
           BRAM (16 KB)             aes_ctrl.v → uart_tx.v
                                              │
                                       PC reconstructs image
```

---

## File Structure

```
aes-master/
├── src/
│   ├── rtl/
│   │   ├── aes.v                  # secworks — existing
│   │   ├── aes_core.v             # secworks — existing
│   │   ├── aes_encipher_block.v   # secworks — existing
│   │   ├── aes_decipher_block.v   # secworks — existing
│   │   ├── aes_key_mem.v          # secworks — existing
│   │   ├── aes_sbox.v             # secworks — existing
│   │   ├── aes_inv_sbox.v         # secworks — existing
│   │   ├── uart_rx.v              # NEW — UART receiver
│   │   ├── uart_tx.v              # NEW — UART transmitter
│   │   ├── pixel_buffer.v         # NEW — 16-byte → 128-bit assembler
│   │   ├── bram_ctrl.v            # NEW — 1024×128-bit BRAM wrapper
│   │   ├── aes_ctrl.v             # NEW — AES FSM controller
│   │   └── top.v                  # NEW — top-level integration
│   └── tb/
│       ├── tb_aes.v               # secworks — existing
│       ├── tb_uart_rx.v           # NEW
│       ├── tb_uart_tx.v           # NEW
│       ├── tb_pixel_buffer.v      # NEW
│       ├── tb_bram_ctrl.v         # NEW
│       ├── tb_aes_ctrl.v          # NEW
│       └── tb_top.v               # NEW — end-to-end simulation
├── constraints/
│   └── basys3.xdc                 # Basys 3 pin assignments
└── host/
    └── uart_host.py               # Python PC-side client
```

---

## Hardware Specifications

| Parameter         | Value                        |
|-------------------|------------------------------|
| Board             | Digilent Basys 3             |
| FPGA              | Artix-7 XC7A35T-1CPG236C     |
| Tool              | Vivado 2023.1                |
| Clock             | 100 MHz                      |
| UART baud rate    | 115200 (8N1)                 |
| AES key size      | 128-bit                      |
| Image size        | 128 × 128 pixels (grayscale) |
| Total data        | 16384 bytes (16 KB)          |
| AES blocks        | 1024 blocks × 128 bits       |
| BRAM usage        | 1 × BRAM36 tile              |

---

## Board Interface

| Signal   | Pin  | Description               |
|----------|------|---------------------------|
| `clk`    | W5   | 100 MHz system clock      |
| `uart_tx_pin` | A18 | UART TX to PC        |
| `uart_rx_pin` | B18 | UART RX from PC      |
| `rst_btn` | U18 | btnC — active-high reset  |
| `btn_start` | T17 | btnR — trigger decrypt  |
| `mode_sw` | V17 | SW0: 0=encrypt, 1=decrypt |
| `status_led[0]` | U16 | Encrypting      |
| `status_led[1]` | E19 | Decrypting      |
| `status_led[2]` | U19 | Done            |
| `status_led[3]` | V19 | Error           |

---

## Module Descriptions

### `uart_rx.v`
Deserialises UART serial data at 115200 baud into 8-bit bytes. Uses a double-flop synchroniser and samples at mid-bit for noise immunity. Outputs a one-cycle `data_valid` pulse per received byte.

### `uart_tx.v`
Serialises 8-bit bytes onto the UART TX line. Asserts `ready` when idle. Generates start bit, 8 data bits (LSB first), and stop bit.

### `pixel_buffer.v`
Accumulates 16 incoming bytes into a 128-bit shift register (MSB-first). Asserts `block_valid` for one cycle when 16 bytes have been received.

### `bram_ctrl.v`
A simple synchronous BRAM wrapper inferred by Vivado as BRAM36 primitives. 1024 entries × 128 bits (16 KB total). Separate write and read enable signals.

### `aes_ctrl.v`
The critical FSM that drives the secworks `aes_core` directly (not via the `aes.v` register wrapper). Implements the required handshake:
1. Assert `init` → wait for `ready` to go low then high (key expansion)
2. Assert `next` → wait for `ready` to go low then high (block processed)
3. Read `result` on `done` pulse

Key expansion runs **once** per session (tracked by `key_expanded` flag). Subsequent blocks skip directly to block processing.

### `top.v`
Top-level system FSM:
- **Encrypt mode** (`SW0=0`): receives UART bytes → pixel buffer → AES encrypt → BRAM write
- **Decrypt mode** (`SW0=1`): press `btnR` → BRAM read → AES decrypt → UART transmit

---

## AES Core Handshake (secworks)

```
     ┌──────┐   init   ┌────────┐  ready↓  ┌───────────────┐  ready↑
     │ IDLE ├─────────►│KEY_INIT├─────────►│WAIT_KEY_READY │─────────►
     └──────┘          └────────┘          └───────────────┘
                                                                  │
                ◄─────────────────────────────────────────────────┘
                  key_expanded=1, go to BLOCK_NEXT
     ┌───────────┐  next   ┌────────────┐  ready↓  ┌──────────────┐  ready↑
     │BLOCK_NEXT ├────────►│WAIT_BLK_LOW├─────────►│WAIT_BLK_HIGH │─────────►
     └───────────┘         └────────────┘          └──────────────┘
                                                                        │
                                                    latch result, assert done
```

---

## Simulation

Run testbenches individually with [Icarus Verilog](http://iverilog.icarus.com/) (free, available on Windows):

```bash
# 1. UART Receiver
iverilog -o sim.vvp src/tb/tb_uart_rx.v src/rtl/uart_rx.v
vvp sim.vvp

# 2. UART Transmitter
iverilog -o sim.vvp src/tb/tb_uart_tx.v src/rtl/uart_tx.v
vvp sim.vvp

# 3. Pixel Buffer
iverilog -o sim.vvp src/tb/tb_pixel_buffer.v src/rtl/pixel_buffer.v
vvp sim.vvp

# 4. BRAM Controller
iverilog -o sim.vvp src/tb/tb_bram_ctrl.v src/rtl/bram_ctrl.v
vvp sim.vvp

# 5. AES Controller  ← Most important: uses NIST test vectors
iverilog -o sim.vvp \
  src/tb/tb_aes_ctrl.v src/rtl/aes_ctrl.v src/rtl/aes_core.v \
  src/rtl/aes_encipher_block.v src/rtl/aes_decipher_block.v \
  src/rtl/aes_key_mem.v src/rtl/aes_sbox.v src/rtl/aes_inv_sbox.v
vvp sim.vvp

# 6. End-to-end top-level
iverilog -o sim.vvp \
  src/tb/tb_top.v src/rtl/top.v src/rtl/aes_ctrl.v \
  src/rtl/uart_rx.v src/rtl/uart_tx.v src/rtl/pixel_buffer.v \
  src/rtl/bram_ctrl.v src/rtl/aes_core.v src/rtl/aes_encipher_block.v \
  src/rtl/aes_decipher_block.v src/rtl/aes_key_mem.v \
  src/rtl/aes_sbox.v src/rtl/aes_inv_sbox.v
vvp sim.vvp
```

All testbenches print `*** ALL TESTS PASSED ***` on success.

---

## Python Host Script

Install dependencies:

```bash
pip install pyserial opencv-python numpy
```

### Encrypt (PC → FPGA)

```bash
# Set SW0 = 0 (encrypt mode), then run:
python host/uart_host.py --mode encrypt --port COM3 --image input.png
```

Sends 16384 raw grayscale bytes. FPGA encrypts each 16-byte block and stores ciphertext in BRAM. LED0 lights up during encryption; LED2 when done.

### Decrypt (FPGA → PC)

```bash
# Set SW0 = 1 (decrypt mode), press btnR on board, then run:
python host/uart_host.py --mode decrypt --port COM3 --output decrypted.png
```

FPGA streams 16384 decrypted bytes. Script reconstructs and saves the image.

> **COM port**: check Windows Device Manager → Ports (COM & LPT) for the Basys 3 USB-UART bridge.

---

## Vivado Project Setup

1. Open Vivado 2023.1 → **Create New Project**
2. Add all files from `src/rtl/` as Design Sources
3. Add all files from `src/tb/` as Simulation Sources
4. Add `constraints/basys3.xdc` as Constraints
5. Set **Top Module** to `top`
6. Run **Synthesis → Implementation → Generate Bitstream**
7. Open Hardware Manager, connect Basys 3, program device

> **Timing**: The secworks S-Box is pipelined. Expect ~3 ns slack at 100 MHz on Artix-7. If WNS is negative, reduce clock to 50 MHz by changing the XDC `create_clock -period` to `20.000`.

---

## Demo Flow

1. Program bitstream to Basys 3
2. Open terminal: `python host/uart_host.py --mode encrypt --port COM3 --image photo.png`
3. Watch LED0 blink as 1024 blocks are encrypted — LED2 lights when done
4. Flip SW0 up, press btnR on the board
5. Run: `python host/uart_host.py --mode decrypt --port COM3 --output result.png`
6. Compare `photo.png` and `result.png` — they should be identical

---

## AES Key

The demo uses NIST standard key `2b7e151628aed2a6abf7158809cf4f3c` hardcoded in `top.v`:

```verilog
localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
```

Change this for any real deployment.

---

## Credits

- AES RTL core: [secworks/aes](https://github.com/secworks/aes) by Joachim Strömbergson (BSD 2-Clause)
- UART, pixel buffer, BRAM controller, AES FSM, top-level: custom implementation
