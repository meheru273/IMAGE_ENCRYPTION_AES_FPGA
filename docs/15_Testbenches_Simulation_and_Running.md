# Document 15: Testbenches, Simulation, and Running the Project

> **Goal**: By the end of this document, you will understand how testbenches work in Verilog,
> how to run simulations in Vivado, and how to do a complete end-to-end test using the Python
> host script with real hardware.

---

## Table of Contents
1. [What is a Testbench?](#1-what-is-a-testbench)
2. [Testbench Anatomy — Key Patterns](#2-testbench-anatomy--key-patterns)
3. [Project Testbench Overview](#3-project-testbench-overview)
4. [Walkthrough: tb_uart_rx.v — Unit Testing the UART Receiver](#4-walkthrough-tb_uart_rxv--unit-testing-the-uart-receiver)
5. [Walkthrough: tb_aes_ctrl.v — Testing with NIST Vectors](#5-walkthrough-tb_aes_ctrlv--testing-with-nist-vectors)
6. [Walkthrough: tb_bram_ctrl.v — Memory Testing](#6-walkthrough-tb_bram_ctrlv--memory-testing)
7. [Walkthrough: tb_top.v — End-to-End System Test](#7-walkthrough-tb_topv--end-to-end-system-test)
8. [Running Simulations in Vivado](#8-running-simulations-in-vivado)
9. [Running Simulations with Icarus Verilog (Command Line)](#9-running-simulations-with-icarus-verilog-command-line)
10. [The Python Host Script (uart_host.py)](#10-the-python-host-script-uart_hostpy)
11. [Complete End-to-End Demo on Real Hardware](#11-complete-end-to-end-demo-on-real-hardware)
12. [The Secworks Testbenches](#12-the-secworks-testbenches)
13. [Key Takeaways](#13-key-takeaways)

---

## 1. What is a Testbench?

A **testbench** is a Verilog file that:
- **Instantiates** your design (the "Device Under Test" or DUT)
- **Generates stimuli** (inputs like clock, reset, data)
- **Observes outputs** and checks if they match expected values
- Reports **PASS** or **FAIL**

Testbenches are **not synthesizable** — they don't become real hardware. They exist only for simulation. They use special Verilog features like `$display` (print text), `#delay` (wait), and `initial` blocks that only work in simulators.

### Analogy: Quality Control Inspector

Think of a testbench as a quality control inspector at a factory:
- The inspector doesn't build the product (DUT)
- They feed test inputs and measure outputs
- They compare results against a specification
- They report whether the product passes or fails

---

## 2. Testbench Anatomy — Key Patterns

### Pattern 1: Clock Generation

Every testbench needs a clock:

```verilog
reg clk;
localparam CLK_PERIOD = 10;   // 10 ns = 100 MHz

initial clk = 0;
always #(CLK_PERIOD / 2) clk = ~clk;  // Toggle every 5 ns

// Resulting waveform:
// clk: _|‾|_|‾|_|‾|_|‾|_|‾|_  (period = 10 ns)
```

`initial clk = 0;` sets the starting value. `always #5 clk = ~clk;` inverts the clock every 5 ns, creating a 10 ns period.

### Pattern 2: Reset Sequence

```verilog
initial begin
    rst = 1;                // Assert reset
    #(CLK_PERIOD * 5);     // Hold for 5 clock cycles (50 ns)
    rst = 0;                // Release reset
end
```

### Pattern 3: Stimulus Generation with `initial` Block

```verilog
initial begin
    // Wait for reset to finish
    #(CLK_PERIOD * 10);

    // Apply test input
    data_in = 8'hA3;
    send = 1;
    #CLK_PERIOD;
    send = 0;

    // Wait for result
    @(posedge done);    // Wait for 'done' signal to go HIGH
    #1;                 // Small delay for signal settling

    // Check result
    if (result !== expected)
        $display("FAIL: got %h, expected %h", result, expected);
    else
        $display("PASS");
end
```

### Pattern 4: Timeout Watchdog

Prevents infinite simulation if something goes wrong:

```verilog
initial begin
    #(CLK_PERIOD * 50000);    // Wait 50,000 cycles max
    $display("ERROR: Simulation timed out!");
    $finish;
end
```

### Pattern 5: Tasks for Reusable Operations

Tasks are like functions in testbenches:

```verilog
task send_byte;
    input [7:0] byte_val;
    integer i;
    begin
        rx = 0;                        // Start bit
        #BIT_PERIOD;
        for (i = 0; i < 8; i = i + 1) begin
            rx = byte_val[i];         // Data bits (LSB first)
            #BIT_PERIOD;
        end
        rx = 1;                        // Stop bit
        #BIT_PERIOD;
    end
endtask
```

---

## 3. Project Testbench Overview

Our project has **11 testbenches** organized in two layers:

### Layer 1: Custom Module Tests (Project-Specific)

| Testbench | Tests Module | What It Verifies |
|-----------|-------------|-----------------|
| `tb_uart_rx.v` | `uart_rx` | Receiving 4 different bytes correctly |
| `tb_uart_tx.v` | `uart_tx` | Transmitting 4 different bytes correctly |
| `tb_pixel_buffer.v` | `pixel_buffer` | 16 bytes → 128-bit block assembly |
| `tb_bram_ctrl.v` | `bram_ctrl` | Write/read at different addresses |
| `tb_aes_ctrl.v` | `aes_ctrl` | Encrypt/decrypt with NIST test vectors |
| `tb_top.v` | `top` | Full system: UART→encrypt→BRAM→decrypt→UART roundtrip |

### Layer 2: Secworks AES Core Tests

| Testbench | Tests Module | What It Verifies |
|-----------|-------------|-----------------|
| `tb_aes.v` | `aes` (wrapper) | 20 NIST ECB test vectors via register interface |
| `tb_aes_core.v` | `aes_core` | 20 NIST ECB test vectors via direct interface |
| `tb_aes_encipher_block.v` | `aes_encipher_block` | 8 encryption tests with pre-loaded round keys |
| `tb_aes_decipher_block.v` | `aes_decipher_block` | 8 decryption tests with pre-loaded round keys |
| `tb_aes_key_mem.v` | `aes_key_mem` | Key expansion for 9 different keys |

### Testing Hierarchy

```
                   tb_top.v (full system test)
                      │
        ┌─────────────┼─────────────────────────┐
        │             │                          │
  tb_uart_rx.v   tb_aes_ctrl.v            tb_bram_ctrl.v
  tb_uart_tx.v        │
  tb_pixel_buffer.v   │
                      │
        ┌─────────────┼─────────────────────────┐
        │             │                          │
  tb_aes_core.v  tb_aes_key_mem.v    tb_aes_encipher_block.v
                                      tb_aes_decipher_block.v
```

**Bottom-up testing**: Test individual modules first, then test the integrated system.

---

## 4. Walkthrough: tb_uart_rx.v — Unit Testing the UART Receiver

### What It Tests

Sends 4 different byte values via bit-banging on the `rx` line and verifies the receiver outputs the correct bytes:

| Test | Byte | Binary | Purpose |
|------|------|--------|---------|
| 1 | `0x55` | `01010101` | Alternating bits — tests bit sampling |
| 2 | `0xA3` | `10100011` | Mixed pattern |
| 3 | `0xFF` | `11111111` | All ones — stop bit is also 1, no transition |
| 4 | `0x00` | `00000000` | All zeros — start and data are same level |

### Key Code: The `send_byte` Task

```verilog
task send_byte;
    input [7:0] byte_val;
    integer i;
    begin
        rx = 1'b0;                          // Send START bit (LOW)
        #(BIT_PERIOD);                       // Wait 8680 ns (one bit period)
        for (i = 0; i < 8; i = i + 1) begin
            rx = byte_val[i];               // Send data bits LSB first
            #(BIT_PERIOD);
        end
        rx = 1'b1;                          // Send STOP bit (HIGH)
        #(BIT_PERIOD);
    end
endtask
```

### Test Execution Flow

```verilog
initial begin
    rx = 1'b1;                               // Idle HIGH
    rst = 1'b1;
    #(CLK_PERIOD * 5);
    rst = 1'b0;
    #(CLK_PERIOD * 10);

    $display("Test 1: send 0x55");
    send_byte(8'h55);                        // Transmit byte
    check_byte(8'h55);                       // Verify received correctly
    #(BIT_PERIOD * 5);                       // Inter-test gap

    $display("Test 2: send 0xA3");
    send_byte(8'hA3);
    check_byte(8'hA3);
    // ... (Tests 3 and 4 similar)
end
```

### Verification Task

```verilog
task check_byte;
    input [7:0] expected;
    begin
        @(posedge data_valid);               // Wait for receiver to output
        #1;                                   // Small settle delay
        if (data_out !== expected) begin
            $display("  FAIL: expected 0x%02h, got 0x%02h", expected, data_out);
            error_ctr = error_ctr + 1;
        end else
            $display("  PASS: received 0x%02h", data_out);
    end
endtask
```

---

## 5. Walkthrough: tb_aes_ctrl.v — Testing with NIST Vectors

### What It Tests

Uses official **NIST SP 800-38A** test vectors to verify the AES controller:

| Test | Operation | Input | Expected Output |
|------|-----------|-------|----------------|
| 1 | Encrypt (with key expansion) | `6bc1bee22e409f96e93d7e117393172a` | `3ad77bb40d7a3660a89ecaf32466ef97` |
| 2 | Decrypt (key already expanded) | `3ad77bb40d7a3660a89ecaf32466ef97` | `6bc1bee22e409f96e93d7e117393172a` |
| 3 | Encrypt 2nd block (no key expansion) | `ae2d8a571e03ac9c9eb76fac45af8e51` | `f5d3d58503b9699de785895a96fdbaaf` |

### Why These Tests Are Important

- **Test 1**: Verifies encryption AND key expansion work correctly together
- **Test 2**: Verifies decryption works with the same expanded key
- **Test 3**: Verifies the `key_expanded` optimization — the second encrypt should skip key expansion and still produce the correct result

### Key Code: Test 1

```verilog
// Test 1: Encrypt with key expansion
$display("Test 1: Encrypt NIST block 0 (with key expansion)");
key_in   = NIST_KEY;
block_in = NIST_PT0;
mode     = 1'b1;                    // Encrypt
start    = 1'b1;
#CLK_PERIOD;
start    = 1'b0;                    // One-cycle pulse

@(posedge done);                    // Wait for completion
#1;                                 // Settle

if (block_out !== NIST_CT0) begin
    $display("  FAIL: expected %h, got %h", NIST_CT0, block_out);
    error_ctr = error_ctr + 1;
end else
    $display("  PASS: ciphertext matches NIST CT0");
```

---

## 6. Walkthrough: tb_bram_ctrl.v — Memory Testing

### What It Tests

| Test | Action | Address | Data | Verification |
|------|--------|---------|------|-------------|
| 1 | Write + Read | 0 | `DEADBEEFCAFEBABE0123456789ABCDEF` | Read matches write |
| 2 | Write + Read | 100 | `112233445566778899AABBCCDDEEFF00` | Read matches write |
| 3 | Write + Read | 1023 (max) | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` | Read matches write |
| 4 | Re-read | 0 | (no write) | Address 0 still has test 1 data |

### Key Code: Write and Read with Latency

```verilog
// Write to address 0
addr  = 10'd0;
din   = 128'hDEADBEEFCAFEBABE0123456789ABCDEF;
wr_en = 1'b1;
#CLK_PERIOD;
wr_en = 1'b0;

// Read from address 0 (note 1-cycle latency!)
addr  = 10'd0;
rd_en = 1'b1;
#CLK_PERIOD;
rd_en = 1'b0;
#CLK_PERIOD;              // Wait one MORE cycle for read data to appear!

// Now check
if (dout !== 128'hDEADBEEFCAFEBABE0123456789ABCDEF) begin
    $display("FAIL");
end
```

**Important**: The extra `#CLK_PERIOD` after `rd_en` is because BRAM reads are synchronous — data appears one clock cycle after the read request.

---

## 7. Walkthrough: tb_top.v — End-to-End System Test

This is the most comprehensive test — it verifies the entire system:

### Test Flow

```
Phase 1: ENCRYPT
  ┌─────────┐    UART bit-bang     ┌──────┐
  │Testbench│───────────────────►│ DUT  │
  │ sends   │  16 bytes           │ (top)│
  │ 0x10-1F │  via uart_rx_pin   │      │
  └─────────┘                     │      │
                                  │  encrypt→BRAM │
  Force encrypt_done_flag=1       │      │
  (only testing 1 block,          │      │
   not all 1024)                  │      │

Phase 2: DECRYPT
  mode_sw=1, press btn_start      │      │
                                  │  BRAM→decrypt │
  ┌─────────┐    UART capture     │      │
  │Testbench│◄──────────────────│      │
  │ captures│  16 bytes          │      │
  │ bytes   │  from uart_tx_pin  │      │
  └─────────┘                     └──────┘

Phase 3: VERIFY
  Compare sent bytes (0x10-0x1F) with received bytes
  If all match: *** END-TO-END TEST PASSED ***
```

### Why Force `encrypt_done_flag`?

The testbench only sends 1 block (16 bytes), but the system expects 1024 blocks before considering encryption "done". To avoid sending all 1024 blocks in simulation (which would take very long), the testbench forces the flag:

```verilog
force dut.encrypt_done_flag = 1'b1;
force dut.wr_addr = 10'd1;
```

This tells the system "encryption is complete with 1 block stored" so it can proceed to decryption.

---

## 8. Running Simulations in Vivado

### Step 1: Set the Simulation Top Module

1. In the **Sources** panel, switch to **Simulation Sources** view
2. Right-click on the testbench you want to run (e.g., `tb_aes_ctrl`)
3. Select **"Set as Top"**

### Step 2: Run Behavioral Simulation

1. In the **Flow Navigator** (left panel), click **"Run Simulation"** → **"Run Behavioral Simulation"**
2. Vivado compiles and runs the simulation
3. The **Waveform Viewer** opens showing signal traces
4. Check the **Tcl Console** at the bottom for `$display` output (PASS/FAIL messages)

### Step 3: Analyze the Waveform

The waveform viewer shows signal values over time:

```
Signal      0ns    100ns   200ns   300ns   400ns   500ns
──────      ───    ─────   ─────   ─────   ─────   ─────
clk         _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
rst         ‾‾‾‾‾|____________________________________
state       IDLE  |KEY_INIT|WK_LOW| ..... |WK_HIGH....
core_ready  ‾‾‾‾‾‾‾‾‾‾‾‾‾|______________|‾‾‾‾‾‾‾‾‾‾‾
```

**Tips for using the waveform viewer:**
- **Zoom in/out** with the magnifying glass buttons or scroll wheel
- **Add signals**: Drag from the object panel on the left
- **Set radix**: Right-click a signal → "Radix" → "Hexadecimal" (for data buses)
- **Find edges**: Click a signal, use left/right arrow buttons to jump to next transition
- The **yellow cursor** (vertical line) shows the current time — click to move it

### Step 4: Check Results

Look at the **Tcl Console** output:
```
Test 1: Encrypt NIST block 0 (with key expansion)
  PASS: ciphertext matches NIST CT0
Test 2: Decrypt NIST block 0 (key already expanded)
  PASS: plaintext matches NIST PT0
Test 3: Encrypt NIST block 1 (no key expansion needed)
  PASS: ciphertext matches NIST CT1
*** ALL AES CTRL TESTS PASSED ***
```

---

## 9. Running Simulations with Icarus Verilog (Command Line)

**Icarus Verilog** is a free, open-source Verilog simulator. The project includes a Makefile for it.

### Install Icarus Verilog

- **Windows**: Download from https://bleyer.org/icarus/ or use `choco install iverilog`
- **Linux**: `sudo apt install iverilog`
- **macOS**: `brew install icarus-verilog`

### Using the Makefile (Secworks Tests)

```bash
cd toolruns/

# Build all testbenches
make all

# Run specific tests
make sim-core      # Run AES core tests (20 NIST vectors)
make sim-keymem    # Run key expansion tests
make sim-encipher  # Run encipher tests
make sim-decipher  # Run decipher tests
make sim-top       # Run AES wrapper tests

# Clean build artifacts
make clean
```

### Running Custom Testbenches Manually

The Makefile only covers Secworks tests. For custom module tests:

```bash
# Compile and run tb_aes_ctrl
iverilog -Wall -o aes_ctrl_test.sim \
    ../src/rtl/aes_sbox.v \
    ../src/rtl/aes_inv_sbox.v \
    ../src/rtl/aes_key_mem.v \
    ../src/rtl/aes_encipher_block.v \
    ../src/rtl/aes_decipher_block.v \
    ../src/rtl/aes_core.v \
    ../src/rtl/aes_ctrl.v \
    ../src/tb/tb_aes_ctrl.v
./aes_ctrl_test.sim

# Compile and run tb_uart_rx
iverilog -Wall -o uart_rx_test.sim \
    ../src/rtl/uart_rx.v \
    ../src/tb/tb_uart_rx.v
./uart_rx_test.sim

# Compile and run tb_bram_ctrl
iverilog -Wall -o bram_test.sim \
    ../src/rtl/bram_ctrl.v \
    ../src/tb/tb_bram_ctrl.v
./bram_test.sim
```

---

## 10. The Python Host Script (uart_host.py)

### Purpose

`uart_host.py` is the PC-side companion that communicates with the FPGA over UART. It has two modes:

### Prerequisites

Install the required Python packages:
```bash
pip install pyserial opencv-python numpy
```

### Encrypt Mode — Send Image to FPGA

```bash
python uart_host.py --mode encrypt --port COM3 --image input.png
```

What this does:
1. Loads `input.png` as a grayscale image
2. Resizes it to exactly 128×128 pixels
3. Flattens it into 16,384 raw bytes
4. Sends all bytes to the FPGA over UART at 115,200 baud
5. Sends in 256-byte chunks with 10ms delays between chunks

**Finding your COM port:**
- **Windows**: Open Device Manager → Ports (COM & LPT) → look for "USB Serial Port (COM3)" or similar
- **Linux**: `ls /dev/ttyUSB*` → usually `/dev/ttyUSB0` or `/dev/ttyUSB1`
- **macOS**: `ls /dev/cu.usbserial*`

### Decrypt Mode — Receive Image from FPGA

```bash
python uart_host.py --mode decrypt --port COM3 --output decrypted.png
```

What this does:
1. Opens the serial port and waits for data
2. Reads 16,384 bytes from the FPGA
3. Reshapes into a 128×128 pixel array
4. Saves as `decrypted.png`
5. Optionally displays the image on screen

### Important: You must flip SW0 and press btnR on the board before running decrypt mode!

---

## 11. Complete End-to-End Demo on Real Hardware

### Step-by-Step: Encrypt an Image and Decrypt It Back

**Prerequisites:**
- Vivado project set up with all source files (see Document 02)
- Bitstream generated and FPGA programmed
- Python packages installed
- A grayscale test image (any size — the script resizes it to 128×128)

### Phase 1: Program the FPGA

1. Open Vivado, open your project
2. Generate Bitstream (if not already done)
3. Open Hardware Manager → Auto Connect → Program Device
4. Verify: all LEDs should be OFF (system idle)

### Phase 2: Encrypt

1. On the Basys 3 board: ensure **SW0 is DOWN** (encrypt mode)
2. Press **btnC** (center) to reset the system
3. On your PC, run:
   ```bash
   python host/uart_host.py --mode encrypt --port COM3 --image myimage.png
   ```
4. Watch the board: **LED0** should light up (encrypting)
5. Wait about 1.5 seconds for transfer to complete
6. **LED2** should light up (done) — all 1024 blocks encrypted and stored in BRAM

### Phase 3: Decrypt

1. Flip **SW0 UP** (decrypt mode)
2. On your PC, start the decrypt script FIRST (it will wait for data):
   ```bash
   python host/uart_host.py --mode decrypt --port COM3 --output result.png
   ```
3. Press **btnR** (right button) on the board to start decryption
4. Watch the board: **LED1** lights up (decrypting)
5. Wait about 1.5 seconds for transfer
6. **LED2** lights up (done)
7. The Python script saves `result.png` — it should be identical to your original image!

### Verifying the Result

Compare the original and recovered images:
```python
import cv2
import numpy as np

original = cv2.imread("myimage.png", cv2.IMREAD_GRAYSCALE)
original = cv2.resize(original, (128, 128))
recovered = cv2.imread("result.png", cv2.IMREAD_GRAYSCALE)

if np.array_equal(original, recovered):
    print("SUCCESS: Images are identical!")
else:
    diff = np.sum(original != recovered)
    print(f"MISMATCH: {diff} pixels differ")
```

---

## 12. The Secworks Testbenches

The original Secworks AES core comes with extensive testbenches. Here's what they cover:

### tb_aes_core.v — 20 NIST Test Vectors

Tests both AES-128 and AES-256 with official NIST test data:

| Group | Key | Tests |
|-------|-----|-------|
| AES-128, Key 1 | `2b7e1516...` | 4 encrypt + 4 decrypt = 8 tests |
| AES-128, Key 2 | `00010203...` | 1 encrypt + 1 decrypt = 2 tests |
| AES-256, Key 1 | `603deb10...` | 4 encrypt + 4 decrypt = 8 tests |
| AES-256, Key 2 | `00010203...` | 1 encrypt + 1 decrypt = 2 tests |

**Total: 20 tests** — comprehensive coverage of the AES algorithm.

### tb_aes_key_mem.v — Key Expansion Tests

Tests 9 different keys (5 for AES-128, 4 for AES-256). For each key, it verifies **every single round key** matches the expected NIST values. This is the most thorough key expansion test.

### tb_aes_encipher_block.v and tb_aes_decipher_block.v

These test the encryption and decryption datapaths independently by pre-loading round keys (bypassing key expansion). This isolates the datapath logic from key generation.

---

## 13. Key Takeaways

1. **Testbenches are Verilog files that simulate and verify your design**. They use `initial` blocks, `#delays`, `$display`, and `$finish` — features that only work in simulation, not in real hardware.

2. **Five key testbench patterns**: clock generation, reset sequence, stimulus application, timeout watchdog, and assertion checking.

3. **Test bottom-up**: First test individual modules (UART, BRAM, AES), then test the integrated system (tb_top).

4. **NIST test vectors** provide "ground truth" for AES verification. If your hardware produces the correct NIST output for a given input and key, the implementation is correct.

5. **Vivado's behavioral simulation** lets you visualize the waveforms — extremely valuable for debugging timing issues.

6. **Icarus Verilog** provides a free command-line alternative for quick simulation without launching Vivado's full GUI.

7. **The Python host script** bridges PC and FPGA for real hardware testing. It handles image loading, serial communication, and result verification.

8. **The end-to-end test** is the ultimate verification: send an image → encrypt on FPGA → decrypt on FPGA → receive image → compare. If the images match, the entire system works correctly.

---

> **Next**: [Document 16 — Drawbacks, Bottlenecks, and Future Research](16_Drawbacks_Bottlenecks_Future_Research.md) — Analysis of the project's limitations and opportunities for academic publication.
