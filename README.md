# AES-128 Transparent Memory Encryption on FPGA

A hardware AES-128 image encryption system implemented on the **Digilent Basys 3** (Artix-7 XC7A35T) using Vivado 2023.1. A 128×128 grayscale image is streamed from a PC over UART, encrypted block-by-block using the [secworks AES core](https://github.com/secworks/aes), stored in on-chip BRAM, then decrypted on demand and streamed back. The system supports **4 operation modes** with a dynamically supplied 128-bit key over UART.

---

## System Overview

```
PC (Python)  ──UART──►  uart_rx.v
                              │
              ┌───── 16-byte key ─────┐
              │                       │
              ▼                       ▼
       user_key_reg            pixel_buffer.v    (16 bytes → 128-bit block)
              │                       │
              └───────────┬───────────┘
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

## Modes of Operation

The system supports 4 modes selected by two switches (`SW1`, `SW0`) before pressing `btnR`:

| Mode | SW1 | SW0 | Name | Description |
|------|-----|-----|------|-------------|
| 1 | 0 | 0 | **Full Encrypt** | Send key + plaintext image → FPGA encrypts → stores ciphertext in BRAM → sends encrypted image back |
| 2 | 0 | 1 | **Full Decrypt** | Send key + ciphertext image → FPGA stores in BRAM → decrypts → sends plaintext back |
| 3 | 1 | 0 | **Key-only Retrieve** | Send key only → FPGA verifies key matches the one used during last Mode 1 → if match, sends raw encrypted BRAM contents; if mismatch, sends `0xFF` error byte |
| 4 | 1 | 1 | **Key-only Decrypt** | Send key only → FPGA decrypts stored BRAM contents with the supplied key → sends plaintext back |

> **All modes** receive a 16-byte AES key over UART first (sent immediately after pressing `btnR`).

---

## File Structure

```
aes-image/
├── src/
│   ├── rtl/
│   │   ├── aes.v                  # secworks — existing
│   │   ├── aes_core.v             # secworks — existing
│   │   ├── aes_encipher_block.v   # secworks — existing
│   │   ├── aes_decipher_block.v   # secworks — existing
│   │   ├── aes_key_mem.v          # secworks — existing
│   │   ├── aes_sbox.v             # secworks — existing
│   │   ├── aes_inv_sbox.v         # secworks — existing
│   │   ├── uart_rx.v              # UART receiver
│   │   ├── uart_tx.v              # UART transmitter
│   │   ├── pixel_buffer.v         # 16-byte → 128-bit assembler
│   │   ├── bram_ctrl.v            # 1024×128-bit BRAM wrapper
│   │   ├── aes_ctrl.v             # AES FSM controller
│   │   └── top.v                  # Top-level integration (4-mode FSM)
│   └── tb/
│       ├── tb_aes.v               # secworks — existing
│       ├── tb_uart_rx.v           # UART RX testbench
│       ├── tb_uart_tx.v           # UART TX testbench
│       ├── tb_pixel_buffer.v      # Pixel buffer testbench
│       ├── tb_bram_ctrl.v         # BRAM controller testbench
│       ├── tb_aes_ctrl.v          # AES controller testbench
│       └── tb_top.v               # End-to-end 4-mode simulation
├── constraints/
│   └── basys3.xdc                 # Basys 3 pin assignments
└── host/
    └── uart_host.py               # Python PC-side client (4-mode)
```

---

## Hardware Specifications

| Parameter         | Value                        |
|-------------------|------------------------------|
| Board             | Digilent Basys 3             |
| FPGA              | Artix-7 XC7A35T-1CPG236C    |
| Tool              | Vivado 2023.1                |
| Clock             | 100 MHz                      |
| UART baud rate    | 115200 (8N1)                 |
| AES key size      | 128-bit (supplied over UART) |
| Image size        | 128 × 128 pixels (grayscale) |
| Total data        | 16384 bytes (16 KB)          |
| AES blocks        | 1024 blocks × 128 bits       |
| BRAM usage        | 1 × BRAM36 tile              |

---

## Board Interface

| Signal   | Pin  | Description                               |
|----------|------|-------------------------------------------|
| `clk`    | W5   | 100 MHz system clock                      |
| `uart_tx_pin` | A18 | UART TX to PC                        |
| `uart_rx_pin` | B18 | UART RX from PC                      |
| `rst_btn` | U18 | btnC — active-high reset                  |
| `btn_start` | T17 | btnR — trigger operation (starts key RX) |
| `mode_sw` | V17 | SW0: 0=encrypt, 1=decrypt                |
| `mode_sw1` | V16 | SW1: 0=full image, 1=key-only           |
| `status_led[0]` | U16 | LED0 — Encrypting               |
| `status_led[1]` | E19 | LED1 — Decrypting               |
| `status_led[2]` | U19 | LED2 — Done                     |
| `status_led[3]` | V19 | LED3 — Error (key mismatch)     |

---

## Module Descriptions

### `uart_rx.v`
Deserialises UART serial data at 115200 baud into 8-bit bytes. Uses a double-flop synchroniser and samples at mid-bit for noise immunity. Outputs a one-cycle `data_valid` pulse per received byte.

### `uart_tx.v`
Serialises 8-bit bytes onto the UART TX line. Asserts `ready` when idle. Generates start bit, 8 data bits (LSB first), and stop bit.

### `pixel_buffer.v`
Accumulates 16 incoming bytes into a 128-bit shift register (MSB-first). Asserts `block_valid` for one cycle when 16 bytes have been received. Includes a `soft_rst` input to clear state between mode transitions without a full system reset.

### `bram_ctrl.v`
A simple synchronous BRAM wrapper inferred by Vivado as BRAM36 primitives. 1024 entries × 128 bits (16 KB total). Separate write and read enable signals.

### `aes_ctrl.v`
The critical FSM that drives the secworks `aes_core` directly (not via the `aes.v` register wrapper). Implements the required handshake:
1. Assert `init` → wait for `ready` to go low then high (key expansion)
2. Assert `next` → wait for `ready` to go low then high (block processed)
3. Read `result` on `done` pulse

Key expansion runs **once** per session (tracked by `key_expanded` flag). A `key_reset` input allows forcing re-expansion when a new key is supplied.

### `top.v`
Top-level system FSM with 15 states supporting 4 operation modes. All modes begin with 16-byte key reception over UART, then branch based on latched `{SW1, SW0}`:
- **Mode 1 (00)**: `DISPATCH` → `ENCRYPT_RX` → `ENCRYPT_WAIT` → `ENCRYPT_STORE` → `BRAM_STREAM` → `BRAM_STREAM_TX` → `DONE`
- **Mode 2 (01)**: `DISPATCH` → `CIPHER_RX` → `DECRYPT_READ` → `DECRYPT_WAIT` → `DECRYPT_TX` → `DONE`
- **Mode 3 (10)**: `DISPATCH` → `KEY_VERIFY` → `BRAM_STREAM`/`ERROR` → `DONE`
- **Mode 4 (11)**: `DISPATCH` → `DECRYPT_READ` → `DECRYPT_WAIT` → `DECRYPT_TX` → `DONE`

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

## Prerequisites

### Python Dependencies

```bash
pip install pyserial opencv-python numpy
```

### Icarus Verilog (for simulation)

Download from [http://iverilog.icarus.com/](http://iverilog.icarus.com/) or install via package manager.

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

## Simulation (Icarus Verilog)

Run testbenches individually:

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

# 6. End-to-end top-level (all 4 modes)
iverilog -o sim.vvp \
  src/tb/tb_top.v src/rtl/top.v src/rtl/aes_ctrl.v \
  src/rtl/uart_rx.v src/rtl/uart_tx.v src/rtl/pixel_buffer.v \
  src/rtl/bram_ctrl.v src/rtl/aes_core.v src/rtl/aes_encipher_block.v \
  src/rtl/aes_decipher_block.v src/rtl/aes_key_mem.v \
  src/rtl/aes_sbox.v src/rtl/aes_inv_sbox.v
vvp sim.vvp
```

All testbenches print `*** ALL TESTS PASSED ***` on success.

The `tb_top.v` testbench runs 4 phases:
1. **Phase 1** — Mode 1 (Full Encrypt): sends key + 16 plaintext bytes, verifies non-zero ciphertext output
2. **Phase 2** — Mode 3 (Retrieve, correct key): sends same key, verifies BRAM contents match Phase 1
3. **Phase 3** — Mode 3 (Retrieve, wrong key): sends a different key, verifies `0xFF` error response
4. **Phase 4** — Mode 4 (Key-only Decrypt): sends original key, verifies plaintext recovery matches Phase 1 input

---

## Testing All 4 Modes on FPGA

> **How it works**: The Python script opens the serial port first, then prompts you to set the switches and press btnR on the board. This ensures proper synchronization — just follow the on-screen prompts.

### Step 0 — Setup

1. Program the bitstream to the Basys 3 board via Vivado Hardware Manager
2. Identify the COM port: open **Windows Device Manager → Ports (COM & LPT)** and note the Basys 3 USB-UART bridge port (e.g., `COM3`)
3. Press **btnC** (center button) to reset the FPGA — all LEDs should turn off

### Step 1 — Mode 1: Full Encrypt (SW1=0, SW0=0)

This mode sends the AES key and a plaintext image to the FPGA. The FPGA encrypts the image, stores the ciphertext in BRAM, saves the key internally, and streams the encrypted image back to the PC.

1. Run the Python script (put everything on **one line** in PowerShell):

```powershell
python host/uart_host.py --mode encrypt --port COM3 --image input.png --key 2b7e151628aed2a6abf7158809cf4f3c
```

2. The script will prompt you:
   - Set **SW0 = DOWN**, **SW1 = DOWN**
   - Press **btnR** on the board
   - Press **Enter** in the terminal
3. **Watch the LEDs**:
   - LED0 lights up → encryption in progress
   - LED2 lights up → encryption complete, streaming encrypted data back
4. The script saves the encrypted image as `encrypted.png` (should look like random noise)
5. The FPGA now holds the encrypted image in BRAM and remembers the key

> **Note**: Use `--encrypted_output filename.png` to specify a different output filename.

### Step 2 — Mode 2: Full Decrypt (SW1=0, SW0=1)

This mode sends the AES key and an encrypted image file from disk. The FPGA stores the ciphertext in BRAM, decrypts it block-by-block, and streams the plaintext back.

> **⚠️ Warning**: Pressing **btnC** clears the stored encryption key from Mode 1. If you plan to test Mode 3 (retrieve) or Mode 4 (decrypt stored), run those **before** Mode 2. The recommended order is: Mode 1 → Mode 3 → Mode 4 → btnC → Mode 2.

1. Press **btnC** to reset the FPGA
2. Run:

```powershell
python host/uart_host.py --mode decrypt --port COM3 --input encrypted.png --key 2b7e151628aed2a6abf7158809cf4f3c --output decrypted_mode2.png
```

3. Follow the on-screen prompt: set **SW0 = UP**, **SW1 = DOWN**, press **btnR**, then **Enter**
4. **Watch the LEDs**:
   - LED1 lights up → receiving ciphertext / decrypting
   - LED2 lights up → done
5. Compare `decrypted_mode2.png` with `input.png` — they should be identical

### Step 3 — Mode 3: Key-only Retrieve (SW1=1, SW0=0)

This mode verifies the supplied key matches the key used during the last Mode 1 encryption. If the key matches, the FPGA streams the raw encrypted BRAM contents back. If the key doesn't match, the FPGA sends a single `0xFF` error byte.

**Prerequisite**: You must have run Mode 1 at least once (so the FPGA has a stored key and encrypted data in BRAM). Do **NOT** reset the FPGA between Mode 1 and Mode 3.

#### Test with correct key:

```powershell
python host/uart_host.py --mode retrieve --port COM3 --key 2b7e151628aed2a6abf7158809cf4f3c --output retrieved.png
```

Follow the prompt: set **SW0 = DOWN**, **SW1 = UP**, press **btnR**, then **Enter**.

- LED2 lights up → key verified, streaming encrypted data
- `retrieved.png` should match `encrypted.png` from Mode 1

#### Test with wrong key:

```powershell
python host/uart_host.py --mode retrieve --port COM3 --key 00112233445566778899aabbccddeeff --output should_fail.png
```

Follow the prompt: set **SW0 = DOWN**, **SW1 = UP**, press **btnR**, then **Enter**.

- LED3 lights up → key mismatch error
- The script prints: `Key mismatch — access denied (received 0xFF)`

### Step 4 — Mode 4: Key-only Decrypt (SW1=1, SW0=1)

This mode decrypts the data already stored in BRAM using the supplied key, without sending any image data.

**Prerequisite**: BRAM must contain encrypted data from a previous Mode 1 or Mode 2 operation. Do **NOT** reset the FPGA between the encrypt and this step.

```powershell
python host/uart_host.py --mode decrypt_stored --port COM3 --key 2b7e151628aed2a6abf7158809cf4f3c --output decrypted_mode4.png
```

Follow the prompt: set **SW0 = UP**, **SW1 = UP**, press **btnR**, then **Enter**.

- LED1 lights up → decryption in progress
- LED2 lights up → done
- Compare `decrypted_mode4.png` with `input.png` — they should be identical

---

## Complete End-to-End Test Sequence

Run all 4 modes in sequence. Each script will prompt you for the switch/button actions. **Do not press btnC (reset) between steps** — the BRAM and stored key must persist across modes.

```powershell
# Step 1: Mode 1 — Encrypt (script prompts: SW0=DOWN, SW1=DOWN, btnR)
python host/uart_host.py --mode encrypt --port COM3 --image input.png --key 2b7e151628aed2a6abf7158809cf4f3c --encrypted_output encrypted.png

# Step 2: Mode 3 — Retrieve with correct key (script prompts: SW0=DOWN, SW1=UP, btnR)
python host/uart_host.py --mode retrieve --port COM3 --key 2b7e151628aed2a6abf7158809cf4f3c --output retrieved.png

# Step 3: Mode 3 — Retrieve with wrong key (should fail)
python host/uart_host.py --mode retrieve --port COM3 --key 00112233445566778899aabbccddeeff --output should_fail.png

# Step 4: Mode 4 — Decrypt stored data (script prompts: SW0=UP, SW1=UP, btnR)
python host/uart_host.py --mode decrypt_stored --port COM3 --key 2b7e151628aed2a6abf7158809cf4f3c --output decrypted.png

# Step 5: Mode 2 — Full decrypt from file (press btnC to reset first!)
python host/uart_host.py --mode decrypt --port COM3 --input encrypted.png --key 2b7e151628aed2a6abf7158809cf4f3c --output decrypted_mode2.png
```

### Expected Results

| Step | Mode | Expected LED | Expected Output |
|------|------|-------------|-----------------|
| 1 | Mode 1 (Encrypt) | LED0 → LED2 | `encrypted.png` — random noise |
| 2 | Mode 3 (Retrieve ✓) | LED2 | `retrieved.png` — matches `encrypted.png` |
| 3 | Mode 3 (Retrieve ✗) | LED3 | Script prints "access denied" |
| 4 | Mode 4 (Decrypt stored) | LED1 → LED2 | `decrypted.png` — matches `input.png` |
| 5 | Mode 2 (Full decrypt) | LED1 → LED2 | `decrypted_mode2.png` — matches `input.png` |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No LEDs light after btnR | FPGA not programmed or wrong bitstream | Re-program via Vivado Hardware Manager |
| Script times out waiting for data | btnR not pressed or pressed too late | Follow the script's on-screen prompt: set switches → press btnR → press Enter |
| Garbled/corrupted output image | Wrong COM port or baud rate mismatch | Verify COM port in Device Manager; ensure 115200 baud |
| LED3 lights up unexpectedly | Key mismatch in Mode 3 | Ensure you use the exact same key as the Mode 1 encrypt session |
| Mode 4 output doesn't match original | BRAM was cleared by a reset | Do **not** press btnC between Mode 1 and Mode 4 |
| `encrypted.png` is all zeros | Image not sent or encryption failed | Check that `input.png` exists and is readable |
| PowerShell rejects `\` line breaks | PowerShell uses backtick for continuation | Put the entire command on one line, or use `` ` `` instead of `\` |

---

## Credits

- AES RTL core: [secworks/aes](https://github.com/secworks/aes) by Joachim Strömbergson (BSD 2-Clause)
- UART, pixel buffer, BRAM controller, AES FSM, top-level: custom implementation
