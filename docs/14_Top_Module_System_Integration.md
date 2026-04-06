# Document 14: Top Module and System Integration (top.v)

> **Goal**: By the end of this document, you will understand how `top.v` ties everything together —
> the system FSM, how encryption and decryption paths work, the byte extraction logic,
> and how the constraint file maps signals to physical pins.

---

## Table of Contents
1. [What Does the Top Module Do?](#1-what-does-the-top-module-do)
2. [Module Interface — The Physical Pins](#2-module-interface--the-physical-pins)
3. [Constants and Parameters](#3-constants-and-parameters)
4. [Module Instantiations — Connecting the Hardware](#4-module-instantiations--connecting-the-hardware)
5. [The 7-State System FSM](#5-the-7-state-system-fsm)
6. [Detailed State Walkthrough: Encryption Path](#6-detailed-state-walkthrough-encryption-path)
7. [Detailed State Walkthrough: Decryption Path](#7-detailed-state-walkthrough-decryption-path)
8. [The Byte Extraction Logic](#8-the-byte-extraction-logic)
9. [Button Edge Detection](#9-button-edge-detection)
10. [LED Status Indicators](#10-led-status-indicators)
11. [The Constraint File Connection](#11-the-constraint-file-connection)
12. [Complete Encryption Scenario: Step by Step](#12-complete-encryption-scenario-step-by-step)
13. [Key Takeaways](#13-key-takeaways)

---

## 1. What Does the Top Module Do?

`top.v` is the **conductor** of the orchestra. Every other module does one specific thing (receive bytes, encrypt blocks, store data, etc.), but the top module:

1. **Coordinates everything** through a central FSM
2. **Routes data** between modules (UART → Buffer → AES → BRAM → AES → UART)
3. **Manages addresses** for BRAM read/write
4. **Handles user input** (switches and buttons)
5. **Drives status LEDs** to show what the system is doing

### Analogy: An Assembly Line Manager

The top module is like a factory manager:
- Workers (uart_rx, pixel_buffer, aes_ctrl, bram_ctrl, uart_tx) do specific jobs
- The manager (top.v) tells each worker when to start, passes materials between stations, and tracks progress
- The manager also handles the control panel (switches, buttons, LEDs)

---

## 2. Module Interface — The Physical Pins

```verilog
module top(
    input  wire       clk,           // 100 MHz clock       → Pin W5
    input  wire       rst_btn,       // Center button reset  → Pin U18
    input  wire       uart_rx_pin,   // UART receive line    → Pin B18
    output wire       uart_tx_pin,   // UART transmit line   → Pin A18
    input  wire       mode_sw,       // SW0: 0=enc, 1=dec   → Pin V17
    input  wire       btn_start,     // Right button start   → Pin T17
    output reg  [3:0] status_led     // LED[3:0] status      → Pins U16,E19,U19,V19
);
```

These are the **only signals that go to physical FPGA pins**. Everything inside is internal wiring.

```
Physical World                      FPGA Internal
──────────────                      ──────────────
Crystal Oscillator ──W5──► clk ──────────────────┐
Center Button      ──U18─► rst_btn ──────────────┤
USB-UART RX        ──B18─► uart_rx_pin ──────────┤
                                                   ├──► top.v (and all sub-modules)
USB-UART TX        ──A18◄─ uart_tx_pin ◄─────────┤
Switch SW0         ──V17─► mode_sw ──────────────┤
Right Button       ──T17─► btn_start ─────────────┤
LED0               ──U16◄─ status_led[0] ◄───────┤
LED1               ──E19◄─ status_led[1] ◄───────┤
LED2               ──U19◄─ status_led[2] ◄───────┤
LED3               ──V19◄─ status_led[3] ◄───────┘
```

---

## 3. Constants and Parameters

```verilog
localparam TOTAL_BLOCKS = 10'd1024;    // 128×128 image / 16 bytes = 1024 blocks
localparam BYTES_PER_BLOCK = 4'd16;    // AES works on 16-byte blocks

// The AES-128 key (NIST test vector — hardcoded)
localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
```

**Why is the key hardcoded?** This is a demo/educational project. In a production system, the key would be loaded dynamically (e.g., via UART, DIP switches, or secure key storage). Hardcoding makes the demo simple and allows verification against known NIST test vectors.

---

## 4. Module Instantiations — Connecting the Hardware

### UART Receiver

```verilog
uart_rx u_uart_rx(
    .clk       (clk),
    .rst       (rst_btn),
    .rx        (uart_rx_pin),      // Physical RX pin
    .data_out  (rx_data),          // 8-bit received byte
    .data_valid(rx_valid)          // Pulse when byte is ready
);
```

### UART Transmitter

```verilog
uart_tx u_uart_tx(
    .clk     (clk),
    .rst     (rst_btn),
    .data_in (tx_data),            // 8-bit byte to send
    .send    (tx_send),            // Pulse to start sending
    .tx      (uart_tx_pin),        // Physical TX pin
    .ready   (tx_ready)            // HIGH when ready for next byte
);
```

### Pixel Buffer

```verilog
pixel_buffer u_pixel_buffer(
    .clk        (clk),
    .rst        (rst_btn),
    .pixel_in   (rx_data),                  // Byte from UART RX
    .pixel_valid(rx_valid & ~mode_sw),      // ONLY feed during encrypt mode
    .block_out  (pbuf_block),               // 128-bit assembled block
    .block_valid(pbuf_valid)                // Pulse when 16 bytes ready
);
```

**Important: `rx_valid & ~mode_sw`**
- `rx_valid` = UART received a byte
- `~mode_sw` = NOT decrypt mode (i.e., encrypt mode)
- The `&` (AND) means: pixel buffer only accepts bytes during encryption. This prevents stray data from corrupting the buffer during decryption.

### AES Controller

```verilog
aes_ctrl u_aes_ctrl(
    .clk       (clk),
    .rst       (rst_btn),
    .key_in    (AES_KEY),           // Hardcoded key
    .block_in  (aes_block_in),      // Set by system FSM
    .mode      (aes_mode),          // Set by system FSM (1=enc, 0=dec)
    .start     (aes_start),         // Pulse from system FSM
    .block_out (aes_block_out),     // Result
    .done      (aes_done)           // Completion pulse
);
```

### BRAM Controller

```verilog
bram_ctrl u_bram_ctrl(
    .clk   (clk),
    .wr_en (bram_wr_en),           // Write enable from system FSM
    .rd_en (bram_rd_en),           // Read enable from system FSM
    .addr  (bram_addr),            // Address from system FSM
    .din   (bram_din),             // Data to write
    .dout  (bram_dout)             // Data read out
);
```

---

## 5. The 7-State System FSM

```
                              ┌───────────────────────────────────────┐
                              │                                       │
                              ▼                                       │
                        ┌──────────┐                                  │
            ┌──────────►│ SYS_IDLE │◄──────────────┐                 │
            │           └────┬─────┘               │                 │
            │                │                     │                 │
            │    ┌───────────┴──────────┐          │                 │
            │    │ pbuf_valid=1         │ btn_start │                 │
            │    │ & mode=encrypt       │ & mode=decrypt              │
            │    │                      │ & encrypt_done              │
            │    ▼                      ▼                             │
            │  ┌──────────────┐   ┌──────────────┐                  │
            │  │SYS_ENCRYPT   │   │SYS_DECRYPT   │                  │
            │  │    _WAIT     │   │    _READ     │──┐               │
            │  │(wait AES)    │   │(read BRAM)   │  │               │
            │  └──────┬───────┘   └──────────────┘  │               │
            │         │ aes_done                     │               │
            │         ▼                              ▼               │
            │  ┌──────────────┐   ┌──────────────┐                  │
            │  │SYS_ENCRYPT   │   │SYS_DECRYPT   │                  │
            │  │    _STORE    │   │    _WAIT     │                  │
            │  │(write BRAM)  │   │(decrypt AES) │                  │
            │  └──────┬───────┘   └──────┬───────┘                  │
            │         │                   │ aes_done                 │
            │    ┌────┴────┐              ▼                          │
            │    │ more     │ done  ┌──────────────┐                │
            │    │ blocks?  │──────►│SYS_DECRYPT   │                │
            │    └─────────┘       │    _TX       │                │
            │         │            │(send bytes)  │                │
            │    all 1024          └──────┬───────┘                │
            │    blocks done              │                        │
            │         │          ┌────────┴────────┐               │
            └─────────┘          │ more     │ done │               │
                                 │ blocks?  │──────┤               │
                                 └──────────┘      │               │
                                       │           ▼               │
                                  all 1024   ┌──────────┐          │
                                  blocks     │ SYS_DONE │          │
                                  done       └──────────┘          │
                                       │                           │
                                       └───────────────────────────┘
```

### State Descriptions

| State | Code | Purpose |
|-------|------|---------|
| `SYS_IDLE` (0) | Waiting | Wait for blocks from pixel buffer (encrypt) or button press (decrypt) |
| `SYS_ENCRYPT_WAIT` (1) | Processing | AES is encrypting a block — wait for `aes_done` |
| `SYS_ENCRYPT_STORE` (2) | Storing | Write ciphertext to BRAM, increment address |
| `SYS_DECRYPT_READ` (3) | Reading | Read ciphertext from BRAM |
| `SYS_DECRYPT_WAIT` (4) | Processing | AES is decrypting — wait for `aes_done` |
| `SYS_DECRYPT_TX` (5) | Transmitting | Send 16 decrypted bytes via UART, one at a time |
| `SYS_DONE` (6) | Finished | All blocks processed, LED2 stays on |

---

## 6. Detailed State Walkthrough: Encryption Path

### SYS_IDLE → SYS_ENCRYPT_WAIT

When the pixel buffer has assembled 16 bytes:

```verilog
if (!mode_sw && pbuf_valid) begin         // Encrypt mode + block ready
    aes_block_in <= pbuf_block;           // Feed 128-bit block to AES
    aes_mode     <= 1'b1;                 // Set encrypt mode
    aes_start    <= 1'b1;                 // Start AES
    sys_state    <= SYS_ENCRYPT_WAIT;
    status_led   <= 4'b0001;             // LED0 ON = encrypting
end
```

### SYS_ENCRYPT_WAIT → SYS_ENCRYPT_STORE

Wait for AES to finish, then prepare BRAM write:

```verilog
SYS_ENCRYPT_WAIT: begin
    status_led <= 4'b0001;
    if (aes_done) begin
        bram_din   <= aes_block_out;      // Ciphertext from AES
        bram_addr  <= wr_addr;            // Current write address
        bram_wr_en <= 1'b1;              // Write to BRAM
        sys_state  <= SYS_ENCRYPT_STORE;
    end
end
```

### SYS_ENCRYPT_STORE → SYS_IDLE or SYS_DONE

Increment address, check if all blocks done:

```verilog
SYS_ENCRYPT_STORE: begin
    wr_addr <= wr_addr + 10'd1;           // Next address
    if (wr_addr + 10'd1 == TOTAL_BLOCKS) begin
        encrypt_done_flag <= 1'b1;        // All 1024 blocks encrypted!
        status_led <= 4'b0100;            // LED2 ON = done
        sys_state  <= SYS_IDLE;
    end else begin
        sys_state <= SYS_IDLE;            // Wait for next block
    end
end
```

**Key insight**: After storing each encrypted block, the FSM returns to IDLE to wait for the pixel buffer to assemble the next 16 bytes from UART. The pixel buffer is autonomous — it keeps collecting bytes in the background.

---

## 7. Detailed State Walkthrough: Decryption Path

### Triggering Decryption

```verilog
// In SYS_IDLE:
if (mode_sw && btn_start && !btn_start_prev && encrypt_done_flag) begin
    rd_addr   <= 10'd0;              // Start reading from address 0
    sys_state <= SYS_DECRYPT_READ;
    status_led <= 4'b0010;           // LED1 ON = decrypting
end
```

This requires ALL of these conditions:
- `mode_sw` = 1 (switch in decrypt position)
- `btn_start` = 1 (button pressed)
- `!btn_start_prev` = previous cycle button was NOT pressed (rising edge detection)
- `encrypt_done_flag` = encryption is complete (all 1024 blocks stored in BRAM)

### SYS_DECRYPT_READ → SYS_DECRYPT_WAIT

```verilog
SYS_DECRYPT_READ: begin
    bram_addr       <= rd_addr;       // Set BRAM address
    bram_rd_en      <= 1'b1;          // Read from BRAM
    decrypt_started <= 1'b0;          // Reset flag for DECRYPT_WAIT
    sys_state       <= SYS_DECRYPT_WAIT;
end
```

### SYS_DECRYPT_WAIT → SYS_DECRYPT_TX

```verilog
SYS_DECRYPT_WAIT: begin
    // First cycle: BRAM data is available (1-cycle read latency)
    if (!decrypt_started) begin
        aes_block_in    <= bram_dout;     // Ciphertext from BRAM
        aes_mode        <= 1'b0;          // Decrypt mode
        aes_start       <= 1'b1;          // Start AES
        decrypt_started <= 1'b1;          // Don't start again!
    end
    if (aes_done) begin
        decrypt_result <= aes_block_out;  // Latch 128-bit plaintext
        tx_byte_idx    <= 4'd0;           // Start from byte 0
        sys_state      <= SYS_DECRYPT_TX;
    end
end
```

**Why the `decrypt_started` flag?** The FSM stays in `SYS_DECRYPT_WAIT` for many cycles while AES processes. Without the flag, `aes_start` would be pulsed every cycle, causing chaos.

### SYS_DECRYPT_TX — Sending 16 Bytes One by One

```verilog
SYS_DECRYPT_TX: begin
    if (tx_ready && !tx_send) begin       // UART ready and not already sending
        tx_data <= tx_byte_from_block;    // Current byte from 128-bit result
        tx_send <= 1'b1;                  // Start UART transmission

        if (tx_byte_idx == 4'd15) begin   // Sent all 16 bytes?
            rd_addr <= rd_addr + 10'd1;   // Next BRAM address
            if (rd_addr + 10'd1 == TOTAL_BLOCKS) begin
                sys_state <= SYS_DONE;    // All done!
            end else begin
                sys_state <= SYS_DECRYPT_READ;  // Next block
            end
        end else begin
            tx_byte_idx <= tx_byte_idx + 4'd1;  // Next byte
        end
    end
end
```

---

## 8. The Byte Extraction Logic

After decryption, we have a 128-bit result but UART sends 1 byte at a time. We need to extract each of the 16 bytes:

```verilog
wire [7:0] tx_byte_from_block;
assign tx_byte_from_block = decrypt_result[(15 - tx_byte_idx) * 8 +: 8];
```

### Understanding the `+:` Operator

`[base +: width]` is Verilog's **indexed part-select**:
- Start at bit position `base`
- Select `width` bits going upward

```
decrypt_result[(15 - tx_byte_idx) * 8 +: 8]

When tx_byte_idx = 0:  (15-0)*8 = 120  →  decrypt_result[120 +: 8] = bits [127:120] = MSB byte
When tx_byte_idx = 1:  (15-1)*8 = 112  →  decrypt_result[112 +: 8] = bits [119:112]
When tx_byte_idx = 2:  (15-2)*8 = 104  →  decrypt_result[104 +: 8] = bits [111:104]
...
When tx_byte_idx = 15: (15-15)*8 = 0   →  decrypt_result[0 +: 8]   = bits [7:0]    = LSB byte
```

### Numerical Example

```
decrypt_result = 128'h10111213_14151617_18191A1B_1C1D1E1F

tx_byte_idx = 0:  bits[127:120] = 0x10  (first byte sent)
tx_byte_idx = 1:  bits[119:112] = 0x11
tx_byte_idx = 2:  bits[111:104] = 0x12
...
tx_byte_idx = 15: bits[7:0]    = 0x1F   (last byte sent)
```

This sends bytes **MSB first** — matching how the pixel buffer packed them.

---

## 9. Button Edge Detection

The system uses **rising edge detection** for the start button to prevent repeated triggers while the button is held down:

```verilog
reg btn_start_prev;    // Previous value of btn_start

always @(posedge clk) begin
    btn_start_prev <= btn_start;   // Remember previous state

    // Detect rising edge:
    if (btn_start && !btn_start_prev) begin
        // Button was just pressed! (transition from 0 to 1)
    end
end
```

```
btn_start:      _____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_________
btn_start_prev: ______|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|________
                      ↑
            Rising edge detected here
            (btn_start=1, btn_start_prev=0)
            ONLY for this one clock cycle!
```

Without edge detection, holding the button would trigger decryption every clock cycle (100 million times per second!) instead of once.

---

## 10. LED Status Indicators

```verilog
// In the FSM, LEDs are set based on current state:
SYS_IDLE:          status_led <= 4'b0000;  // All OFF
SYS_ENCRYPT_WAIT:  status_led <= 4'b0001;  // LED0 ON = encrypting
SYS_ENCRYPT_STORE: (keeps LED0 = encrypting)
SYS_DECRYPT_READ:  status_led <= 4'b0010;  // LED1 ON = decrypting
SYS_DECRYPT_WAIT:  (keeps LED1 = decrypting)
SYS_DECRYPT_TX:    (keeps LED1 = decrypting)
SYS_DONE:          status_led <= 4'b0100;  // LED2 ON = done
encrypt_done_flag: status_led <= 4'b0100;  // LED2 ON after encryption completes
```

```
LED Mapping:
  status_led[3] = LED3 (V19) = Error     (unused in normal operation)
  status_led[2] = LED2 (U19) = Done      ●
  status_led[1] = LED1 (E19) = Decrypting ●
  status_led[0] = LED0 (U16) = Encrypting ●
```

---

## 11. The Constraint File Connection

Here's how the top module ports map to physical pins via `basys3.xdc`:

```
top.v Port          XDC File                           Physical Pin
─────────────      ──────────────────────              ────────────
clk            ←→  set_property PACKAGE_PIN W5   ←→   100MHz crystal
rst_btn        ←→  set_property PACKAGE_PIN U18  ←→   Center button
uart_rx_pin    ←→  set_property PACKAGE_PIN B18  ←→   USB-UART (PC → FPGA)
uart_tx_pin    ←→  set_property PACKAGE_PIN A18  ←→   USB-UART (FPGA → PC)
mode_sw        ←→  set_property PACKAGE_PIN V17  ←→   Switch SW0
btn_start      ←→  set_property PACKAGE_PIN T17  ←→   Right button
status_led[0]  ←→  set_property PACKAGE_PIN U16  ←→   LED0
status_led[1]  ←→  set_property PACKAGE_PIN E19  ←→   LED1
status_led[2]  ←→  set_property PACKAGE_PIN U19  ←→   LED2
status_led[3]  ←→  set_property PACKAGE_PIN V19  ←→   LED3
```

**If any port name in `top.v` doesn't match the port name in `basys3.xdc`, Vivado will report an error!** The names must match exactly.

---

## 12. Complete Encryption Scenario: Step by Step

Let's trace through encrypting the first AES block (16 bytes) of an image:

```
Time    Event                           State           LEDs
────    ─────                           ─────           ────
0       Board powered on, reset         SYS_IDLE        0000
        pressed (rst_btn=1)

1ms     Reset released, SW0=0           SYS_IDLE        0000
        (encrypt mode)

2ms     Python script starts            SYS_IDLE        0000
        sending image bytes...

2ms+    UART receives byte 0            SYS_IDLE        0000
        pixel_buffer: byte_cnt=0

...     UART receives bytes 1-14        SYS_IDLE        0000
        pixel_buffer: accumulating

~3.4ms  UART receives byte 15           SYS_IDLE→       0001
        pixel_buffer: block_valid!      ENCRYPT_WAIT
        AES starts encrypting

~3.4ms  AES key expansion (first        ENCRYPT_WAIT    0001
+54cyc  ever, ~54 cycles)
+54cyc  AES block encryption            ENCRYPT_WAIT    0001
        (~54 more cycles)

~3.4ms  aes_done pulse!                 →ENCRYPT_STORE  0001
+110cyc Write ciphertext to BRAM[0]

~3.4ms  Return to IDLE, wr_addr=1       SYS_IDLE        0001
+111cyc Wait for next 16 bytes...

...     Repeat for all 1024 blocks      SYS_IDLE↔       0001
        (takes ~1.4 seconds total)      ENCRYPT_WAIT↔
                                        ENCRYPT_STORE

~1.4s   Block 1023 encrypted!           SYS_IDLE        0100
        encrypt_done_flag=1             (done!)

        User flips SW0 UP (decrypt)
        User presses btnR

~1.4s+  Rising edge on btn_start        SYS_DECRYPT_    0010
        rd_addr=0                       READ

...     Decrypt all 1024 blocks,        DECRYPT cycle   0010
        send each via UART
        (takes ~1.4 seconds)

~2.8s   All blocks sent                 SYS_DONE        0100
        Python script saves image
```

---

## 13. Key Takeaways

1. **`top.v` is the system orchestrator** — it connects UART, pixel buffer, AES, and BRAM through a 7-state FSM.

2. **Encryption is event-driven**: the FSM reacts to pixel buffer's `block_valid` pulse, processes one block, returns to IDLE, and waits for the next block.

3. **Decryption is sequential**: after button press, the FSM reads, decrypts, and transmits blocks one after another without waiting for external input.

4. **The byte extractor** uses `[(15 - idx) * 8 +: 8]` to pull individual bytes from the 128-bit decrypted result in MSB-first order.

5. **Edge detection** on the start button prevents repeated triggers while the button is held.

6. **The hardcoded key** `2b7e151628aed2a6abf7158809cf4f3c` is the NIST AES-128 test key, useful for verification.

7. **The constraint file is the bridge** between Verilog signal names and physical FPGA pins. Every port in `top.v` must have a matching entry in `basys3.xdc`.

8. **Pulse signals** (`aes_start`, `bram_wr_en`, `bram_rd_en`, `tx_send`) are set to 1 for one cycle and automatically return to 0 via the defaults at the top of the FSM.

---

> **Next**: [Document 15 — Testbenches, Simulation, and Running](15_Testbenches_Simulation_and_Running.md) — Learn how to verify the design through simulation and run it on real hardware with the Python host script.
