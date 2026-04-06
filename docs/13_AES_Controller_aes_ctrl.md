# Document 13: AES Controller (aes_ctrl.v)

> **Goal**: By the end of this document, you will understand how the custom AES controller FSM
> drives the Secworks aes_core with proper handshaking, manages key expansion, and processes
> encryption/decryption blocks.

---

## Table of Contents
1. [What Does the AES Controller Do?](#1-what-does-the-aes-controller-do)
2. [Why Do We Need a Controller?](#2-why-do-we-need-a-controller)
3. [Module Interface](#3-module-interface)
4. [The aes_core Instantiation](#4-the-aes_core-instantiation)
5. [The 8-State FSM](#5-the-8-state-fsm)
6. [The Ready-Handshake Protocol](#6-the-ready-handshake-protocol)
7. [Key Expansion Optimization](#7-key-expansion-optimization)
8. [Complete Code Walkthrough](#8-complete-code-walkthrough)
9. [Timing Diagrams](#9-timing-diagrams)
10. [How top.v Uses the AES Controller](#10-how-topv-uses-the-aes-controller)
11. [Key Takeaways](#11-key-takeaways)

---

## 1. What Does the AES Controller Do?

The AES controller is the **bridge** between the simple top-level interface ("here's a block, encrypt/decrypt it, tell me when done") and the more complex aes_core interface (with `init`, `next`, `ready` handshaking signals).

### Analogy: A Secretary Managing a Worker

Think of the aes_controller as a secretary:
- The **boss** (top.v) says: "Encrypt this block"
- The **secretary** (aes_ctrl) knows the exact protocol:
  1. First, expand the key (if not already done)
  2. Wait for the key expansion to finish
  3. Then submit the block for processing
  4. Wait for the result
  5. Report back to the boss: "Here's the result"
- The **worker** (aes_core) does the actual encryption but needs to be managed properly

---

## 2. Why Do We Need a Controller?

The Secworks `aes_core` has a specific interface protocol:

```
aes_core expects:
  1. First: Assert 'init' for 1 cycle → triggers key expansion
  2. Wait: Poll 'ready' signal → goes LOW then HIGH when key expansion is done
  3. Then: Assert 'next' for 1 cycle → triggers block processing
  4. Wait: Poll 'ready' signal → goes LOW then HIGH when block is done
  5. Read: 'result' is valid, 'result_valid' is HIGH
```

Without the controller, `top.v` would need to implement all this handshaking logic itself long with all the other system logic. The controller encapsulates this complexity.

### Why Not Use aes.v (the Secworks Wrapper)?

The Secworks project includes `aes.v`, a register-mapped wrapper that provides a bus interface (address/data/read/write). Our project **bypasses** this wrapper and drives `aes_core` directly because:
- We don't need a bus interface (we control the core from one FSM)
- Direct control is simpler and faster (no register read/write overhead)
- We can manage the handshake protocol exactly the way we need

---

## 3. Module Interface

```verilog
module aes_ctrl(
    input  wire          clk,          // System clock
    input  wire          rst,          // Active-high reset
    input  wire [127:0]  key_in,       // AES-128 key
    input  wire [127:0]  block_in,     // Plaintext (encrypt) or ciphertext (decrypt)
    input  wire          mode,         // 1 = encrypt, 0 = decrypt
    input  wire          start,        // Pulse HIGH to begin processing
    output reg  [127:0]  block_out,    // Encrypted/decrypted result
    output reg           done          // Pulse HIGH for 1 cycle when result is ready
);
```

### Port Descriptions

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 bit | System clock |
| `rst` | Input | 1 bit | Active-high reset — clears FSM and key_expanded flag |
| `key_in` | Input | 128 bits | The AES-128 key (constant in our project) |
| `block_in` | Input | 128 bits | Data to process |
| `mode` | Input | 1 bit | 1 = encrypt, 0 = decrypt |
| `start` | Input | 1 bit | One-cycle pulse to start processing |
| `block_out` | Output | 128 bits | Result after encryption/decryption |
| `done` | Output | 1 bit | One-cycle pulse when `block_out` is valid |

---

## 4. The aes_core Instantiation

```verilog
aes_core aes_inst(
    .clk          (clk),
    .reset_n      (~rst),                  // Secworks uses active-LOW reset
    .encdec       (mode_reg),              // 1 = encrypt, 0 = decrypt
    .init         (core_init),             // Pulse to start key expansion
    .next         (core_next),             // Pulse to start block processing
    .ready        (core_ready),            // HIGH when core is idle/done
    .key          ({key_in, 128'd0}),      // 256-bit key port, upper 128 = our key
    .keylen       (1'b0),                  // 0 = AES-128 mode
    .block        (block_reg),             // Input block
    .result       (core_result),           // Output result
    .result_valid (core_result_valid)       // HIGH when result is valid
);
```

### Important Details

**`.reset_n(~rst)`** — The Secworks modules use **active-low reset** (`reset_n = 0` means reset). Our project uses **active-high reset** (`rst = 1` means reset). The `~` (NOT) inverts the signal to bridge this difference.

**`.key({key_in, 128'd0})`** — The aes_core supports both AES-128 and AES-256. Its key port is 256 bits wide. For AES-128, we put our 128-bit key in the **upper 128 bits** and **zero-pad the lower 128 bits**:

```
256-bit key port: [key_in (128 bits)] [000...000 (128 bits)]
                   ↑ our actual key    ↑ zero padding

Example:
  key_in = 128'h2b7e151628aed2a6abf7158809cf4f3c
  key port = 256'h2b7e151628aed2a6abf7158809cf4f3c_00000000000000000000000000000000
```

**`.keylen(1'b0)`** — Selects AES-128 mode. If we wanted AES-256, we'd set this to `1'b1` and provide a full 256-bit key.

---

## 5. The 8-State FSM

```
           ┌──────────────────────────────────────┐
           │                                      │
           ▼                                      │
      ┌─────────┐     start=1                     │
      │ S_IDLE  │──────────────┐                  │
      └─────────┘              │                  │
                               │                  │
              ┌──── key_expanded? ────┐           │
              │ NO                     │ YES       │
              ▼                        ▼           │
      ┌────────────┐          ┌─────────────┐     │
      │ S_KEY_INIT │          │ S_BLOCK_NEXT│     │
      │ init=1     │          │ next=1      │     │
      └─────┬──────┘          └──────┬──────┘     │
            │                        │             │
            ▼                        ▼             │
      ┌──────────────┐      ┌──────────────────┐  │
      │S_WAIT_KEY_LOW│      │S_WAIT_BLOCK_LOW  │  │
      │wait !ready   │      │wait !ready       │  │
      └─────┬────────┘      └──────┬───────────┘  │
            │ ready=0               │ ready=0      │
            ▼                       ▼              │
      ┌───────────────┐     ┌───────────────────┐ │
      │S_WAIT_KEY_HIGH│     │S_WAIT_BLOCK_HIGH  │ │
      │wait ready     │     │wait ready         │ │
      └─────┬─────────┘     └──────┬────────────┘ │
            │ ready=1               │ ready=1      │
            │                       │              │
            │ set key_expanded=1    │ latch result │
            │                       │              │
            └──► S_BLOCK_NEXT       ▼              │
                                ┌────────┐         │
                                │ S_DONE │         │
                                │ done=1 │─────────┘
                                └────────┘
```

### State Descriptions

| State | Purpose | What Happens |
|-------|---------|-------------|
| `S_IDLE` | Wait for work | Latches `block_in`, `mode`; jumps to KEY_INIT or BLOCK_NEXT |
| `S_KEY_INIT` | Start key expansion | Asserts `core_init` for 1 cycle |
| `S_WAIT_KEY_LOW` | Wait for core to start working | Polls until `core_ready` goes LOW |
| `S_WAIT_KEY_HIGH` | Wait for key expansion to finish | Polls until `core_ready` goes back HIGH; sets `key_expanded` |
| `S_BLOCK_NEXT` | Start block processing | Asserts `core_next` for 1 cycle |
| `S_WAIT_BLOCK_LOW` | Wait for core to start working | Polls until `core_ready` goes LOW |
| `S_WAIT_BLOCK_HIGH` | Wait for block to finish | Polls until `core_ready` goes HIGH; latches result |
| `S_DONE` | Signal completion | Asserts `done` for 1 cycle; returns to IDLE |

---

## 6. The Ready-Handshake Protocol

The most important concept in this module is the **ready-handshake**. The aes_core uses a `ready` signal that follows this pattern:

```
              ┌─────────── Operation Running ──────────┐
              │                                         │
ready:  ‾‾‾‾‾|_________________________________________|‾‾‾‾‾‾‾
              ↑                                         ↑
        init/next asserted                        Operation complete
        (core starts working)                     (result is valid)
```

### Why Wait for ready=LOW First?

You might wonder: why not just wait for `ready=HIGH`? Because `ready` starts HIGH (idle). If we only waited for HIGH, we'd immediately think the operation was done before it even started!

The full handshake is:
1. **Assert init/next** for 1 cycle
2. **Wait for ready to go LOW** — confirms the core received our command and started working
3. **Wait for ready to go HIGH** — confirms the operation is complete

```
Time →
init:   _|‾|_____________________________
ready:  ‾‾‾‾|___________________________|‾‾‾‾‾
             ↑                           ↑
         "I started"              "I'm done"
state:  INIT  WAIT_LOW    WAIT_HIGH      BLOCK_NEXT...
```

---

## 7. Key Expansion Optimization

A critical optimization: **key expansion only happens ONCE**:

```verilog
reg key_expanded;    // Flag: has the key already been expanded?

// In S_IDLE:
if (start) begin
    if (!key_expanded)
        state <= S_KEY_INIT;     // First block: expand key first
    else
        state <= S_BLOCK_NEXT;   // Subsequent blocks: skip key expansion
end
```

Since all 1024 blocks use the same key, we expand it once for block 0 and then skip straight to block processing for blocks 1 through 1023.

### Impact on Timing

```
First block:   KEY_INIT → WAIT_KEY → BLOCK_NEXT → WAIT_BLOCK → DONE
               (~54 cycle key expansion) + (~54 cycle encryption) = ~108 cycles

Blocks 2-1024: BLOCK_NEXT → WAIT_BLOCK → DONE
               (~54 cycle encryption only) = ~54 cycles

Total for 1024 blocks: 108 + (1023 × 54) ≈ 55,350 cycles
At 100 MHz: 55,350 × 10 ns = 0.55 ms
```

Without this optimization, every block would need key expansion, doubling the total time.

---

## 8. Complete Code Walkthrough

### Internal Registers

```verilog
reg [3:0]   state;          // FSM state
reg         key_expanded;    // Has key been expanded?
reg         core_init;       // Pulse to start key expansion
reg         core_next;       // Pulse to start block processing
reg [127:0] block_reg;       // Latched input block
reg         mode_reg;        // Latched encrypt/decrypt mode
```

### Defaults (Pulse Management)

```verilog
// At the start of every clock cycle:
core_init <= 1'b0;   // Default: init is LOW
core_next <= 1'b0;   // Default: next is LOW
done      <= 1'b0;   // Default: done is LOW
```

This pattern ensures that `core_init`, `core_next`, and `done` are only HIGH for **exactly one clock cycle** when they need to be. The default resets them to LOW automatically.

### S_IDLE — Latching Inputs

```verilog
S_IDLE: begin
    if (start) begin
        block_reg <= block_in;    // Latch the input block
        mode_reg  <= mode;        // Latch the mode (enc/dec)
        if (!key_expanded)
            state <= S_KEY_INIT;
        else
            state <= S_BLOCK_NEXT;
    end
end
```

**Why latch the inputs?** Because `block_in` and `mode` come from `top.v` and might change on the next clock cycle. By latching them into `block_reg` and `mode_reg`, we freeze the values for the duration of processing.

### S_KEY_INIT — One-Cycle Init Pulse

```verilog
S_KEY_INIT: begin
    core_init <= 1'b1;      // Assert init for exactly 1 cycle
    state     <= S_WAIT_KEY_LOW;
end
```

Next cycle: `core_init` automatically falls back to 0 (default).

### S_WAIT_KEY_LOW and S_WAIT_KEY_HIGH — Handshake

```verilog
S_WAIT_KEY_LOW: begin
    if (!core_ready)              // ready went LOW = core started
        state <= S_WAIT_KEY_HIGH;
end

S_WAIT_KEY_HIGH: begin
    if (core_ready) begin         // ready went HIGH = core finished
        key_expanded <= 1'b1;     // Mark key as expanded
        state        <= S_BLOCK_NEXT;  // Now process the block
    end
end
```

### S_BLOCK_NEXT — Start Block Processing

```verilog
S_BLOCK_NEXT: begin
    core_next <= 1'b1;      // Assert next for exactly 1 cycle
    state     <= S_WAIT_BLOCK_LOW;
end
```

### S_WAIT_BLOCK_LOW and S_WAIT_BLOCK_HIGH — Block Handshake

```verilog
S_WAIT_BLOCK_LOW: begin
    if (!core_ready)
        state <= S_WAIT_BLOCK_HIGH;
end

S_WAIT_BLOCK_HIGH: begin
    if (core_ready) begin
        block_out <= core_result;   // Latch the result!
        state     <= S_DONE;
    end
end
```

### S_DONE — Signal Completion

```verilog
S_DONE: begin
    done  <= 1'b1;    // One-cycle pulse: "result is ready"
    state <= S_IDLE;   // Go back and wait for next block
end
```

---

## 9. Timing Diagrams

### First Block (with Key Expansion)

```
Clock:    __|‾|__|‾|__|‾|__|‾|__|‾|__|‾|..........|‾|__|‾|__|‾|..........|‾|__|‾|__
start:    ___|‾‾|__________________________________________________________________
state:    IDLE|KINIT|WKLOW|  ...WKHIGH...  |BNEXT|WBLOW|  ...WBHIGH... |DONE|IDLE
core_init:____|‾‾|_____________________________________________________________
core_next:________________________________________|‾‾|_________________________
core_ready:‾‾‾‾‾‾|____(key expanding)____|‾‾‾‾‾‾|____(block processing)___|‾‾‾
block_out: ================================================================|RESULT|
done:      _______________________________________________________________|‾‾|____
                                                                           ↑
                                             Result valid for 1 cycle ─────┘
```

### Subsequent Blocks (Key Already Expanded)

```
Clock:    __|‾|__|‾|__|‾|__|‾|__|‾|..........|‾|__|‾|__
start:    ___|‾‾|________________________________________
state:    IDLE|BNEXT|WBLOW|  ...WBHIGH... |DONE|IDLE
core_next:____|‾‾|__________________________________
core_ready:‾‾‾‾‾|____(block processing)____|‾‾‾
block_out: ====================================|RESULT|
done:      ____________________________________|‾‾|____

Note: KEY_INIT is SKIPPED because key_expanded=1
```

---

## 10. How top.v Uses the AES Controller

### Instantiation

```verilog
aes_ctrl u_aes_ctrl(
    .clk       (clk),
    .rst       (rst_btn),
    .key_in    (AES_KEY),           // Constant: 128'h2b7e151628aed2a6abf7158809cf4f3c
    .block_in  (aes_block_in),      // Set by top FSM before starting
    .mode      (aes_mode),          // 1=encrypt, 0=decrypt
    .start     (aes_start),         // One-cycle pulse from top FSM
    .block_out (aes_block_out),     // Result captured by top FSM
    .done      (aes_done)           // One-cycle pulse triggers next top FSM state
);
```

### Usage in Encryption Path

```verilog
// SYS_IDLE: pixel buffer has a complete block
if (!mode_sw && pbuf_valid) begin
    aes_block_in <= pbuf_block;    // Feed plaintext block
    aes_mode     <= 1'b1;          // Encrypt mode
    aes_start    <= 1'b1;          // Start pulse
    sys_state    <= SYS_ENCRYPT_WAIT;
end

// SYS_ENCRYPT_WAIT: wait for AES to finish
if (aes_done) begin
    bram_din   <= aes_block_out;   // Grab the ciphertext
    bram_wr_en <= 1'b1;            // Store in BRAM
    ...
end
```

### Usage in Decryption Path

```verilog
// SYS_DECRYPT_WAIT: read from BRAM, decrypt
if (!decrypt_started) begin
    aes_block_in    <= bram_dout;   // Feed ciphertext from BRAM
    aes_mode        <= 1'b0;        // Decrypt mode
    aes_start       <= 1'b1;        // Start pulse
    decrypt_started <= 1'b1;
end
if (aes_done) begin
    decrypt_result <= aes_block_out;  // Grab the plaintext
    ...
end
```

---

## 11. Key Takeaways

1. **aes_ctrl is the bridge** between the simple top-level interface and the complex aes_core handshaking protocol.

2. **The ready-handshake** requires: assert init/next → wait for ready LOW → wait for ready HIGH. This 3-step process prevents false "done" detections.

3. **Key expansion happens only once** (`key_expanded` flag). This saves ~54 cycles per block for blocks 2-1024.

4. **Active-low reset bridging**: `~rst` converts our active-high reset for the Secworks active-low convention.

5. **AES-128 key padding**: The 128-bit key is placed in the upper half of the 256-bit key port, with zeros in the lower half. `keylen=0` selects AES-128 mode.

6. **Pulse signals** (`core_init`, `core_next`, `done`) are HIGH for exactly 1 clock cycle using the default-to-zero pattern.

7. **Inputs are latched** (`block_reg`, `mode_reg`) to prevent issues if the top module changes them during processing.

---

> **Next**: [Document 14 — Top Module and System Integration](14_Top_Module_System_Integration.md) — See how all modules are connected and orchestrated by the top-level FSM.
