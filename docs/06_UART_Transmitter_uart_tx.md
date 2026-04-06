# Document 06: UART Transmitter (`uart_tx.v`)

> **Goal**: By the end of this document, you will fully understand every line of the UART transmitter
> module — how it takes a parallel 8-bit byte, serializes it onto a single wire with correct start
> and stop bits, and signals the rest of the system when it is ready for the next byte. You will be
> able to trace through the complete transmission of any byte, clock cycle by clock cycle.

---

## Table of Contents
1. [What Does `uart_tx` Do?](#1-what-does-uart_tx-do)
2. [Module Interface — Every Port Explained](#2-module-interface--every-port-explained)
3. [Parameters and Local Parameters](#3-parameters-and-local-parameters)
4. [How `ready` Works — Combinational Assign vs Register](#4-how-ready-works--combinational-assign-vs-register)
5. [FSM State Diagram](#5-fsm-state-diagram)
6. [Detailed Walkthrough of Each State](#6-detailed-walkthrough-of-each-state)
7. [Complete Numerical Example: Transmitting 0x41 ('A')](#7-complete-numerical-example-transmitting-0x41-a)
8. [Comparison: uart_tx vs uart_rx — How TX Mirrors RX](#8-comparison-uart_tx-vs-uart_rx--how-tx-mirrors-rx)
9. [How the Top Module Uses uart_tx — The send/ready Handshake](#9-how-the-top-module-uses-uart_tx--the-sendready-handshake)
10. [Key Takeaways](#10-key-takeaways)

---

## 1. What Does `uart_tx` Do?

`uart_tx` is the **UART Transmitter** module. Its job is the **exact opposite** of `uart_rx`:
it takes an 8-bit parallel byte from the FPGA's internal logic and converts it into a serial
bitstream on a single wire (`tx`) that the PC can receive.

### Analogy: A Morse Code Operator

Imagine a telegraph operator who has a written word (the byte) on a piece of paper. She needs
to tap it out on the telegraph key one letter at a time:
1. She checks that the line is clear (IDLE, line HIGH).
2. Someone hands her a word and says "send this!" (the `send` signal).
3. She taps a "dash" to signal "incoming!" (start bit = LOW).
4. She taps out each letter one by one (8 data bits, LSB first).
5. She holds the key up for a moment to say "word complete" (stop bit = HIGH).
6. She says "ready for the next word!" (the `ready` signal goes HIGH).

### Where It Sits in the System

```
  FPGA                                              PC (Python)
  ┌─────────────────────────────────────┐           ┌──────────┐
  │                                     │  USB/UART │          │
  │  BRAM ──► [aes_ctrl] ──► decrypted  │  serial   │ Receives │
  │                           128-bit   │  data     │ bytes    │
  │                           block     │ ─────────►│          │
  │           │                         │  one bit  │ Saves    │
  │           ▼                         │  at a     │ image    │
  │    [byte extract] ──► data_in[7:0]  │  time     │          │
  │                       send ──►      │           │          │
  │                      [uart_tx] ──►  tx pin      │          │
  │                       ready ◄──     │           │          │
  │                                     │           └──────────┘
  └─────────────────────────────────────┘
```

During decryption, the top module reads encrypted blocks from BRAM, decrypts them, extracts
individual bytes, and feeds them to `uart_tx` one at a time. `uart_tx` serializes each byte
and sends it out the TX pin to the PC.

---

## 2. Module Interface — Every Port Explained

Here is the module declaration:

```verilog
module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire       send,
    output reg        tx,
    output wire       ready
);
```

### Port Table

| Port | Direction | Width | Type | Description |
|------|-----------|-------|------|-------------|
| `clk` | input | 1 bit | `wire` | The FPGA system clock (100 MHz on Basys 3). All logic updates on the rising edge of this clock. |
| `rst` | input | 1 bit | `wire` | Synchronous active-high reset. When `rst = 1`, all registers go to their initial values and the TX line is driven HIGH (idle). |
| `data_in` | input | 8 bits | `wire` | The byte to transmit. The top module places the byte on these 8 wires before asserting `send`. The transmitter captures (latches) this value when `send` goes HIGH. |
| `send` | input | 1 bit | `wire` | "Please transmit the byte on `data_in` now." When the top module pulses this HIGH for one clock cycle (while `ready` is HIGH), the transmitter begins sending the byte. |
| `tx` | output | 1 bit | `reg` | The serial data line going to the USB-UART bridge and then to the PC. Idles HIGH (1). Goes LOW for the start bit, then carries each data bit, then goes HIGH for the stop bit. |
| `ready` | output | 1 bit | `wire` | "I am idle and can accept a new byte." HIGH when the transmitter is in the IDLE state, LOW when it is busy sending a byte. The top module must check `ready` before asserting `send`. |

### Visual Port Diagram

```
                     ┌─────────────────┐
           clk ─────►│                 │
           rst ─────►│                 │
                     │    uart_tx      │
  data_in [7:0]────►│                 ├─────► tx
          send ─────►│                 ├─────► ready
                     │                 │
                     └─────────────────┘

  Inputs (left):                    Outputs (right):
  - clk:      100 MHz system clock  - tx:    serial data to PC
  - rst:      synchronous reset     - ready: "I can accept a byte"
  - data_in:  the byte to send
  - send:     "start transmitting!"
```

### Why `tx` is `reg` but `ready` is `wire`

- **`tx`** is assigned inside an `always @(posedge clk)` block, so it must be `reg`. In
  hardware, it becomes a flip-flop that holds the current TX line level.

- **`ready`** is assigned with a continuous `assign` statement (combinational logic), so it
  is `wire`. It is not a flip-flop — it is a simple comparison that produces 1 or 0 instantly.
  More on this in Section 4.

---

## 3. Parameters and Local Parameters

```verilog
parameter CLK_FREQ  = 100_000_000;
parameter BAUD_RATE = 115_200;

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868
```

These are identical to `uart_rx` (see [Document 05, Section 3](05_UART_Receiver_uart_rx.md#3-parameters-and-local-parameters--the-math)):

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `CLK_FREQ` | 100,000,000 | FPGA clock frequency in Hz (100 MHz) |
| `BAUD_RATE` | 115,200 | Serial communication speed in bits/sec |
| `CLKS_PER_BIT` | 868 | Number of clock cycles per UART bit period |

```
CLKS_PER_BIT = 100,000,000 / 115,200 = 868 (integer division)

Each bit on the TX line is held for exactly 868 clock cycles = 8.68 us.
```

### What's Missing Compared to uart_rx?

Notice there is **no `HALF_BIT` parameter** in `uart_tx`. The receiver (`uart_rx`) needs
`HALF_BIT` to align its sampling to the middle of each bit. The transmitter does not sample
anything — it just **drives** the TX line for exact bit periods. So `CLKS_PER_BIT` is the
only timing constant needed.

```
  uart_rx needs:                        uart_tx needs:
  - CLKS_PER_BIT (868) for data bits   - CLKS_PER_BIT (868) for all bits
  - HALF_BIT (434) for mid-start align  (no mid-bit alignment needed!)
```

---

## 4. How `ready` Works — Combinational Assign vs Register

```verilog
assign ready = (state == S_IDLE);
```

This single line is worth understanding deeply, because it illustrates an important hardware
concept.

### What It Does

`ready` is HIGH (`1`) whenever the FSM is in the IDLE state, and LOW (`0`) in all other states
(START, DATA, STOP). This tells the top module: "I am not busy — you can give me a new byte."

```
  state:    S_IDLE   S_START   S_DATA   S_DATA   ...   S_STOP   S_IDLE
  ready:    ‾‾‾‾‾‾‾|_________________________________________|‾‾‾‾‾‾‾
              HIGH     LOW throughout transmission              HIGH
            (can       (busy — do NOT assert send!)          (can accept
            accept                                            next byte)
            a byte)
```

### Why `assign` (wire) Instead of `reg`?

The `assign` statement creates **combinational logic** — a simple equality comparator that
produces its output instantly (within a few nanoseconds of gate delay) whenever `state` changes.
There is no clock involved.

```
  Hardware created by "assign ready = (state == S_IDLE);"

                  state[2:0]
                      │
                      ▼
                ┌───────────┐
                │           │
                │  == 3'd0  │──► ready
                │  (S_IDLE) │
                │           │
                └───────────┘
                  Comparator
                  (pure gates,
                   no flip-flop)
```

An alternative would be to make `ready` a `reg` and assign it inside the `always` block:

```verilog
// Alternative (NOT what the code does):
reg ready;
always @(posedge clk) begin
    ready <= (state == S_IDLE);
end
```

This would add a **one-cycle delay**: `ready` would go HIGH one clock cycle after `state`
becomes S_IDLE. The `assign` version is instant — `ready` changes in the **same cycle** that
`state` becomes S_IDLE.

For a handshake signal, the instant response of `assign` is preferable: the top module can
see `ready == 1` and assert `send` in the very next clock cycle, without wasting a cycle.

### The Tradeoff

| Approach | Timing | Delay |
|----------|--------|-------|
| `assign ready = (state == S_IDLE);` | Combinational | Zero clock cycles (instant) |
| `ready <= (state == S_IDLE);` in always block | Registered | One clock cycle delay |

Our code uses the combinational approach for faster handshaking.

---

## 5. FSM State Diagram

The transmitter uses the same 4-state structure as the receiver:

```verilog
localparam S_IDLE  = 3'd0;
localparam S_START = 3'd1;
localparam S_DATA  = 3'd2;
localparam S_STOP  = 3'd3;
```

### ASCII State Diagram

```
                   ┌──────────────────────────────────────────┐
                   │                                          │
                   ▼                                          │
            ┌─────────────┐                                   │
            │   S_IDLE     │                                   │
            │   (3'd0)     │                                   │
            │              │                                   │
            │  tx = 1      │                                   │
            │  (line idle) │                                   │
            │              │                                   │
            │  ready = 1   │                                   │
            └─────────────┘                                   │
                  │                                            │
                  │ send == 1                                  │
                  │ (top module requests transmission)         │
                  │ => latch data_in into tx_shift             │
                  ▼                                            │
            ┌─────────────┐                                   │
            │  S_START     │                                   │
            │  (3'd1)      │                                   │
            │              │                                   │
            │  tx = 0      │                                   │
            │ (start bit)  │                                   │
            │              │                                   │
            │  Count 868   │                                   │
            │  clocks      │                                   │
            └─────────────┘                                   │
                  │                                            │
                  │ clk_cnt == 867                             │
                  │ (start bit complete)                       │
                  ▼                                            │
            ┌─────────────┐                                   │
            │  S_DATA      │◄────┐                            │
            │  (3'd2)      │     │ bit_idx < 7                │
            │              │     │ (more bits to send)        │
            │  tx = tx_    │─────┘                            │
            │  shift       │  clk_cnt == 867                  │
            │  [bit_idx]   │                                   │
            │              │                                   │
            │  Count 868   │                                   │
            │  per bit     │                                   │
            └─────────────┘                                   │
                  │                                            │
                  │ bit_idx == 7 AND clk_cnt == 867           │
                  │ (all 8 data bits sent)                    │
                  ▼                                            │
            ┌─────────────┐                                   │
            │  S_STOP      │                                   │
            │  (3'd3)      │───────────────────────────────────┘
            │              │  clk_cnt == 867
            │  tx = 1      │  (stop bit complete)
            │  (stop bit)  │  => back to IDLE
            │              │
            │  Count 868   │
            │  clocks      │
            └─────────────┘
```

### The Four States at a Glance

| State | Code | TX Line | Duration | What Triggers Exit |
|-------|------|---------|----------|--------------------|
| `S_IDLE` | `3'd0` | HIGH (1) — idle | Indefinite | `send == 1` |
| `S_START` | `3'd1` | LOW (0) — start bit | 868 clocks | `clk_cnt == 867` |
| `S_DATA` | `3'd2` | `tx_shift[bit_idx]` — data | 8 x 868 = 6,944 clocks | `bit_idx == 7` AND `clk_cnt == 867` |
| `S_STOP` | `3'd3` | HIGH (1) — stop bit | 868 clocks | `clk_cnt == 867` |

---

## 6. Detailed Walkthrough of Each State

### Internal Registers

```verilog
reg [2:0]  state;      // Current FSM state
reg [15:0] clk_cnt;    // Clock cycle counter within current bit period
reg [2:0]  bit_idx;    // Which data bit (0-7) we are currently transmitting
reg [7:0]  tx_shift;   // Local copy of the byte being transmitted
```

**`tx_shift`** deserves special attention: when `send` is asserted, the byte from `data_in`
is copied into `tx_shift`. From that point on, the transmitter works from `tx_shift`,
not `data_in`. This means the top module is free to change `data_in` immediately — the
transmitter has its own copy.

```
  Why latch into tx_shift?

  data_in: [  byte A  ][  byte B  ][  byte C  ]   <- top module can change this anytime
                ↓
           tx_shift = byte A                        <- transmitter keeps its own stable copy
                                                       while serializing
```

### 6.1 S_IDLE — Waiting for a Transmission Request

```verilog
S_IDLE: begin
    tx <= 1'b1;
    if (send) begin
        tx_shift <= data_in;
        state    <= S_START;
        clk_cnt  <= 16'd0;
    end
end
```

**What is happening**: The transmitter is idle. The TX line is held HIGH (the UART idle
level). It waits for the top module to assert `send`.

**Line-by-line**:

- `tx <= 1'b1;` — Drive the TX line HIGH every clock cycle while idle. This is the UART
  idle state. The receiving side (PC) expects to see a constant HIGH when no data is being sent.

- `if (send) begin` — The top module is requesting a transmission. The top module should only
  assert `send` when `ready == 1` (which it is, since we are in S_IDLE).

- `tx_shift <= data_in;` — **Latch the byte!** Copy the 8-bit value from `data_in` into the
  internal `tx_shift` register. From this point forward, `data_in` can change without
  affecting the transmission — we have our own copy.

- `state <= S_START;` — Begin the transmission by moving to the START state.

- `clk_cnt <= 16'd0;` — Reset the clock counter to prepare for counting the start bit period.

**Important**: Notice that `tx` is still set to `1'b1` in this cycle. It does not go LOW until
the **next** clock cycle when we enter S_START. This is because non-blocking assignments
(`<=`) take effect at the end of the current cycle.

### 6.2 S_START — Sending the Start Bit

```verilog
S_START: begin
    tx <= 1'b0;
    if (clk_cnt == CLKS_PER_BIT - 1) begin
        clk_cnt <= 16'd0;
        bit_idx <= 3'd0;
        state   <= S_DATA;
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: We drive the TX line LOW for exactly 868 clock cycles. This is the
**start bit** that tells the receiver "a byte is coming!"

```
  tx line during S_START:

  IDLE        S_START (868 clock cycles)              S_DATA
  ‾‾‾‾‾‾‾‾‾‾|_______________________________________|...
    tx = 1    tx = 0 for 868 cycles                   first data bit
              |◄─────── 868 clocks ────────►|
```

**Line-by-line**:

- `tx <= 1'b0;` — Drive TX LOW. This line executes **every clock cycle** we are in S_START,
  keeping TX solidly at 0 for the entire start bit duration.

- `if (clk_cnt == CLKS_PER_BIT - 1)` — Have we held TX LOW for 868 cycles? (0 to 867 = 868
  values.)

- `clk_cnt <= 16'd0;` — Reset counter for the first data bit.

- `bit_idx <= 3'd0;` — Ensure we start transmitting from bit 0 (the LSB).

- `state <= S_DATA;` — Move to the DATA state to begin sending the 8 data bits.

- `clk_cnt <= clk_cnt + 16'd1;` — Not done yet — keep counting.

### 6.3 S_DATA — Sending the 8 Data Bits

```verilog
S_DATA: begin
    tx <= tx_shift[bit_idx];
    if (clk_cnt == CLKS_PER_BIT - 1) begin
        clk_cnt <= 16'd0;
        if (bit_idx == 3'd7) begin
            state <= S_STOP;
        end else begin
            bit_idx <= bit_idx + 3'd1;
        end
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: This is the core of the transmitter. For each of the 8 data bits, we
drive the TX line to the value of that bit and hold it for exactly 868 clock cycles. Bits are
sent **LSB first** (bit 0, then bit 1, ..., then bit 7).

```
  tx line during S_DATA (example byte 0x41 = 01000001):

  bit_idx:    0     1     2     3     4     5     6     7
  tx value:   1     0     0     0     0     0     1     0
              ↑                                   ↑
             LSB                                 MSB-1

  tx line:  ‾‾‾‾‾|_____|_____|_____|_____|_____|‾‾‾‾‾|_____|
            D0=1   D1=0  D2=0  D3=0  D4=0  D5=0 D6=1  D7=0

            |◄868►|◄868►|◄868►|◄868►|◄868►|◄868►|◄868►|◄868►|
```

**Line-by-line**:

- `tx <= tx_shift[bit_idx];` — **This is the key line!** It drives the TX line to the value
  of the current data bit. `tx_shift[bit_idx]` extracts bit number `bit_idx` from the byte:
  - When `bit_idx = 0`: `tx = tx_shift[0]` (the LSB, transmitted first)
  - When `bit_idx = 1`: `tx = tx_shift[1]`
  - ...
  - When `bit_idx = 7`: `tx = tx_shift[7]` (the MSB, transmitted last)

  This line executes every clock cycle while in S_DATA, holding the TX line steady at the
  current bit value for the full 868-cycle bit period.

- `if (clk_cnt == CLKS_PER_BIT - 1)` — Have we held this bit for 868 cycles?

- `clk_cnt <= 16'd0;` — Reset counter for the next bit (or stop bit).

- `if (bit_idx == 3'd7)` — Have we sent all 8 bits (indices 0 through 7)?
  - **YES**: Move to `S_STOP`. All data bits are on the wire.
  - **NO**: `bit_idx <= bit_idx + 3'd1;` — Move to the next bit.

- `clk_cnt <= clk_cnt + 16'd1;` — Not done with this bit period yet — keep counting.

### 6.4 S_STOP — Sending the Stop Bit

```verilog
S_STOP: begin
    tx <= 1'b1;
    if (clk_cnt == CLKS_PER_BIT - 1) begin
        clk_cnt <= 16'd0;
        state   <= S_IDLE;
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: We drive TX HIGH for 868 clock cycles. This is the **stop bit**,
signaling to the receiver that the byte is complete. After the stop bit, we return to IDLE.

```
  tx line during S_STOP:

  ...last data bit...   S_STOP (868 clocks)    S_IDLE
  _____________________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|‾‾‾‾‾‾‾‾‾‾‾‾
    (D7)                 tx = 1 (stop bit)      tx = 1 (idle)
                        |◄──── 868 clocks ────►|
```

**Line-by-line**:

- `tx <= 1'b1;` — Drive TX HIGH for the stop bit. This is held for 868 clock cycles.

- `if (clk_cnt == CLKS_PER_BIT - 1)` — Have we held the stop bit for 868 cycles?

- `clk_cnt <= 16'd0;` — Reset counter.

- `state <= S_IDLE;` — Transmission complete! Return to IDLE. The `ready` signal will
  immediately go HIGH (because `ready = (state == S_IDLE)` is combinational).

**Note**: Unlike `uart_rx`, there is no `data_valid` pulse here. The transmitter does not
need to notify anyone that it finished — the `ready` signal going HIGH is sufficient for the
top module to know it can send the next byte.

### 6.5 Default — Safety Net

```verilog
default: state <= S_IDLE;
```

Same as in `uart_rx`: if the state register somehow holds an invalid value, the FSM recovers
by returning to IDLE. Defensive coding — always include a `default` case.

---

## 7. Complete Numerical Example: Transmitting 0x41 ('A')

Let's trace through the **entire** process of transmitting the byte **0x41**, which is the
ASCII code for the letter 'A'.

### Setup

```
Byte to transmit: 0x41 = ASCII 'A'
Binary: 0100_0001

Bits in UART transmission order (LSB first):
  bit 0 (LSB) = 1
  bit 1       = 0
  bit 2       = 0
  bit 3       = 0
  bit 4       = 0
  bit 5       = 0
  bit 6       = 1
  bit 7 (MSB) = 0
```

The complete UART frame on the TX wire will look like:

```
            START  D0  D1  D2  D3  D4  D5  D6  D7  STOP
  tx:  ‾‾‾‾|____|‾‾‾‾|____|____|____|____|____|‾‾‾‾|____|‾‾‾‾|‾‾‾‾‾‾
             0    1    0    0    0    0    0    1    0    1
            LOW  HIGH  LOW  LOW  LOW  LOW  LOW HIGH LOW  HIGH
```

### Phase 1: S_IDLE — Receiving the Send Command

The transmitter is idle. The top module places 0x41 on `data_in` and asserts `send`.

```
Clock Cycle  | state   | send | data_in | tx | ready | clk_cnt | Action
─────────────┼─────────┼──────┼─────────┼────┼───────┼─────────┼─────────────
...          | S_IDLE  |  0   |  ----   |  1 |   1   |    --   | Idle, tx=HIGH
Cycle N      | S_IDLE  |  1   |  0x41   |  1 |   1   | (reset) | send asserted!
             |         |      |         |    |       |    0    | tx_shift <= 0x41
             |         |      |         |    |       |         | state <= S_START
             |         |      |         |    |       |         | clk_cnt <= 0
```

At the end of cycle N:
- `tx_shift` holds 0x41 (01000001)
- `state` transitions to S_START
- `ready` will go LOW in the next cycle (because state is no longer S_IDLE)

### Phase 2: S_START — Sending the Start Bit (868 Clocks)

The TX line is driven LOW for exactly 868 clock cycles.

```
Clock Cycle  | state   | tx | clk_cnt | bit_idx | Action
─────────────┼─────────┼────┼─────────┼─────────┼──────────────────
N+1          | S_START |  0 |    0    |    --   | tx driven LOW (start bit)
N+2          | S_START |  0 |    1    |    --   | clk_cnt++
N+3          | S_START |  0 |    2    |    --   | clk_cnt++
...          | S_START |  0 |   ...   |    --   | counting...
N+868        | S_START |  0 |   867   |    --   | clk_cnt == 867!
             |         |    |         |    0    | Start bit complete!
             |         |    |         |         | clk_cnt <= 0
             |         |    |         |         | bit_idx <= 0
             |         |    |         |         | state <= S_DATA
```

The receiver on the other end (the PC's UART) detects this LOW-going edge and begins its
own synchronization process (as described in Document 05).

### Phase 3: S_DATA — Sending All 8 Data Bits

Each data bit is held on the TX line for 868 clock cycles. The bits are sent LSB first.

```
tx_shift = 0x41 = 0100_0001

tx_shift[0] = 1  (D0, sent first)
tx_shift[1] = 0  (D1)
tx_shift[2] = 0  (D2)
tx_shift[3] = 0  (D3)
tx_shift[4] = 0  (D4)
tx_shift[5] = 0  (D5)
tx_shift[6] = 1  (D6)
tx_shift[7] = 0  (D7, sent last)
```

```
Clock Cycle       | state  | tx | clk_cnt | bit_idx | tx_shift[bit_idx] | Action
──────────────────┼────────┼────┼─────────┼─────────┼───────────────────┼──────────────
--- Bit 0 (D0) -----------------------------------------------------------------------
N+869             | S_DATA |  1 |    0    |    0    | tx_shift[0] = 1   | tx = 1
N+870             | S_DATA |  1 |    1    |    0    |                   | clk_cnt++
...               | S_DATA |  1 |   ...   |    0    |                   | counting...
N+1736            | S_DATA |  1 |   867   |    0    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 1
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 1 (D1) -----------------------------------------------------------------------
N+1737            | S_DATA |  0 |    0    |    1    | tx_shift[1] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    1    |                   | counting...
N+2604            | S_DATA |  0 |   867   |    1    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 2
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 2 (D2) -----------------------------------------------------------------------
N+2605            | S_DATA |  0 |    0    |    2    | tx_shift[2] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    2    |                   | counting...
N+3472            | S_DATA |  0 |   867   |    2    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 3
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 3 (D3) -----------------------------------------------------------------------
N+3473            | S_DATA |  0 |    0    |    3    | tx_shift[3] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    3    |                   | counting...
N+4340            | S_DATA |  0 |   867   |    3    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 4
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 4 (D4) -----------------------------------------------------------------------
N+4341            | S_DATA |  0 |    0    |    4    | tx_shift[4] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    4    |                   | counting...
N+5208            | S_DATA |  0 |   867   |    4    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 5
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 5 (D5) -----------------------------------------------------------------------
N+5209            | S_DATA |  0 |    0    |    5    | tx_shift[5] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    5    |                   | counting...
N+6076            | S_DATA |  0 |   867   |    5    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 6
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 6 (D6) -----------------------------------------------------------------------
N+6077            | S_DATA |  1 |    0    |    6    | tx_shift[6] = 1   | tx = 1
...               | S_DATA |  1 |   ...   |    6    |                   | counting...
N+6944            | S_DATA |  1 |   867   |    6    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx <= 7
                  |        |    |         |         |                   | clk_cnt <= 0
--- Bit 7 (D7) -----------------------------------------------------------------------
N+6945            | S_DATA |  0 |    0    |    7    | tx_shift[7] = 0   | tx = 0
...               | S_DATA |  0 |   ...   |    7    |                   | counting...
N+7812            | S_DATA |  0 |   867   |    7    |                   | clk_cnt==867!
                  |        |    |         |         |                   | bit_idx == 7!
                  |        |    |         |         |                   | All 8 bits sent!
                  |        |    |         |         |                   | state <= S_STOP
                  |        |    |         |         |                   | clk_cnt <= 0
```

### Verifying the Transmitted Bits

Looking at the TX line levels from the table above:

```
  Bit     tx_shift[bit]   TX Line   Duration
  ───     ─────────────   ───────   ────────
  START   (start bit)       0       868 clocks
  D0      tx_shift[0]=1    1       868 clocks
  D1      tx_shift[1]=0    0       868 clocks
  D2      tx_shift[2]=0    0       868 clocks
  D3      tx_shift[3]=0    0       868 clocks
  D4      tx_shift[4]=0    0       868 clocks
  D5      tx_shift[5]=0    0       868 clocks
  D6      tx_shift[6]=1    1       868 clocks
  D7      tx_shift[7]=0    0       868 clocks
  STOP    (stop bit)        1       868 clocks

  A receiver would reconstruct: D7 D6 D5 D4 D3 D2 D1 D0
                               =  0  1  0  0  0  0  0  1
                               = 0100_0001
                               = 0x41 = 'A'   Correct!
```

### Phase 4: S_STOP — Sending the Stop Bit (868 Clocks)

```
Clock Cycle       | state  | tx | clk_cnt | ready | Action
──────────────────┼────────┼────┼─────────┼───────┼──────────────
N+7813            | S_STOP |  1 |    0    |   0   | tx = 1 (stop bit)
N+7814            | S_STOP |  1 |    1    |   0   | clk_cnt++
...               | S_STOP |  1 |   ...   |   0   | counting...
N+8680            | S_STOP |  1 |   867   |   0   | clk_cnt == 867!
                  |        |    |         |       | Transmission complete!
                  |        |    |         |       | state <= S_IDLE
                  |        |    |         |       | clk_cnt <= 0
──────────────────┼────────┼────┼─────────┼───────┼──────────────
N+8681            | S_IDLE |  1 |    0    |   1   | Back to IDLE!
                  |        |    |         |       | ready goes HIGH immediately
                  |        |    |         |       | (combinational assign)
```

### Summary: Complete TX Line Waveform for 0x41

```
  Clock:  0              868          1736         2604         3472
  tx:     ‾‾‾‾‾‾‾‾‾‾‾‾‾|____________|‾‾‾‾‾‾‾‾‾‾‾‾|____________|____________
          IDLE            START (0)    D0 = 1        D1 = 0       D2 = 0

         3472         4340         5208         6076         6944
         ____________|____________|____________|____________|‾‾‾‾‾‾‾‾‾‾‾‾
         D3 = 0       D4 = 0       D5 = 0       D6 = 1

         6944         7812         8680
         ‾‾‾‾‾‾‾‾‾‾‾‾|____________|‾‾‾‾‾‾‾‾‾‾‾‾|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
         D6 = 1        D7 = 0       STOP (1)      IDLE (1)

  Total: 10 bit periods x 868 clocks = 8,680 clock cycles = 86.8 us
```

---

## 8. Comparison: uart_tx vs uart_rx — How TX Mirrors RX

The transmitter and receiver are mirror images of each other. Understanding one makes the
other easy to understand.

### Side-by-Side Comparison

```
  uart_rx (Receiver)                    uart_tx (Transmitter)
  ──────────────────                    ──────────────────────
  Converts: serial → parallel           Converts: parallel → serial
  Input: rx wire (serial)               Input: data_in[7:0] (parallel)
  Output: data_out[7:0] (parallel)      Output: tx wire (serial)

  ┌────────┐   serial    ┌────────┐    ┌────────┐   serial    ┌────────┐
  │   PC   ├────────────►│uart_rx │    │uart_tx ├────────────►│   PC   │
  │(sender)│  1 bit at   │        │    │        │  1 bit at   │(recvr) │
  └────────┘  a time     └────────┘    └────────┘  a time     └────────┘
                         data_out[7:0]  data_in[7:0]
                         data_valid     send / ready
```

### Feature Comparison Table

| Feature | uart_rx | uart_tx |
|---------|---------|---------|
| **Direction** | Serial-to-parallel | Parallel-to-serial |
| **FSM states** | IDLE, START, DATA, STOP | IDLE, START, DATA, STOP |
| **State encoding** | Same (3'd0 to 3'd3) | Same (3'd0 to 3'd3) |
| **CLKS_PER_BIT** | 868 | 868 |
| **HALF_BIT** | 434 (needed for mid-bit sampling) | Not needed (TX drives, doesn't sample) |
| **Synchronizer** | Yes (double flip-flop on rx) | No (tx is driven by internal logic) |
| **Start bit** | Detects falling edge, verifies at mid-point | Drives tx LOW for 868 clocks |
| **Data bits** | Samples rx at center of each bit | Drives tx to each bit value for 868 clocks |
| **Stop bit** | Waits 868 clocks, then outputs byte | Drives tx HIGH for 868 clocks |
| **Handshake out** | `data_valid` pulse (1 cycle) | `ready` level (combinational) |
| **Handshake in** | None (always listening) | `send` pulse (from top module) |
| **Internal register** | `rx_shift` (assembles incoming bits) | `tx_shift` (holds byte being sent) |
| **Bit access** | `rx_shift[bit_idx] <= rx_sync_1` (write) | `tx <= tx_shift[bit_idx]` (read) |

### The Key Symmetry

The transmitter and receiver use the **same bit-indexing pattern** but in opposite directions:

```
  uart_rx:  rx_shift[bit_idx] <= rx_sync_1;
            ^^^^^^^^                 ^^^^^^^^
            Write TO the shift       Read FROM the rx line
            register at position     (which bit value to store)
            bit_idx

  uart_tx:  tx <= tx_shift[bit_idx];
            ^^    ^^^^^^^^
            Drive the tx line        Read FROM the shift
            (output)                 register at position
                                     bit_idx (which bit to send)
```

Both process bits in LSB-first order (bit_idx goes 0, 1, 2, ..., 7), which matches the
UART protocol specification.

### Why No Synchronizer in uart_tx?

The `rx` input in `uart_rx` comes from the **outside world** (asynchronous, no relationship
to our clock). It needs a double flip-flop synchronizer to prevent metastability.

The `tx` output in `uart_tx` is **driven by our own FSM** (synchronous, already aligned to
our clock). There is nothing to synchronize — the signal originates from our own flip-flops.

```
  uart_rx:  External → [sync FF1] → [sync FF2] → FSM reads rx_sync_1
            ^^^^^^^^
            Asynchronous!
            Needs synchronization!

  uart_tx:  FSM drives → [tx flip-flop] → External
                          ^^^^^^^^^^^^^^^
                          Already synchronous!
                          No synchronization needed!
```

---

## 9. How the Top Module Uses uart_tx — The send/ready Handshake

### The Handshake Protocol

The top module and `uart_tx` communicate using a simple two-signal handshake:

```
  top.v                          uart_tx
  ┌──────────────┐               ┌──────────────┐
  │              │   data_in     │              │
  │  Places byte ├──────────────►│              │
  │  on data_in  │               │              │
  │              │   send        │              │
  │  Asserts    ├──────────────►│  Starts      │
  │  send=1     │               │  transmitting│
  │              │   ready       │              │
  │  Checks     │◄──────────────┤  Reports     │
  │  ready      │               │  status      │
  └──────────────┘               └──────────────┘
```

### The Rules

1. **Before sending**: The top module MUST check that `ready == 1` before asserting `send`.
   If `ready == 0`, the transmitter is busy and will ignore `send`.

2. **Starting a transmission**: The top module places the byte on `data_in` and asserts
   `send = 1` for one clock cycle.

3. **During transmission**: `ready` drops to 0. The top module must wait.

4. **After transmission**: `ready` goes back to 1. The top module can now send the next byte.

### Timing Diagram of the Handshake

```
  clk:        |__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|   ...   |__|‾|__|‾|__|‾|__|‾|
                                                        (8680 clocks later)

  data_in:    ====< 0x41 >========================================< 0x42 >==
                     ↑                                                ↑
                     Byte A placed                                   Byte B placed

  send:       ________|‾‾‾‾|____________________________________________|‾‾‾‾|___
                       ↑                                                  ↑
                       Send byte A!                                      Send byte B!

  ready:      ‾‾‾‾‾‾‾‾‾‾‾‾|_______________________________________|‾‾‾‾‾‾‾‾‾‾‾|___
                            ↑                                        ↑
                       Goes LOW (busy)                          Goes HIGH (done)
                       Top module must wait                     Top module can send

  tx:         ‾‾‾‾‾‾‾‾‾‾‾‾‾|____|‾‾‾‾|____|____|____|____|____|‾‾‾‾|____|‾‾‾‾|‾‾‾‾
                             START D0   D1   D2   D3   D4   D5  D6   D7  STOP
                                   Byte 0x41 being transmitted
```

### Example from top.v (Simplified)

During decryption, the top module sends 16 bytes (one decrypted AES block) to the PC.
Here is a simplified version of how it works:

```verilog
// In top.v (simplified for clarity):
reg [3:0] byte_idx;     // Which byte (0-15) of the 128-bit block
reg [7:0] tx_byte;      // The byte to send

// Extract one byte from the 128-bit decrypted block:
//   byte_idx = 0 → most significant byte (bits 127:120)
//   byte_idx = 15 → least significant byte (bits 7:0)
always @(*) begin
    tx_byte = aes_block_out[(15 - byte_idx)*8 +: 8];
end

// Send it when uart_tx is ready:
always @(posedge clk) begin
    if (uart_tx_ready && need_to_send) begin
        tx_send <= 1'b1;
        // ... advance to next byte ...
    end else begin
        tx_send <= 1'b0;
    end
end

// Connect to uart_tx:
uart_tx u_tx (
    .clk(clk),
    .rst(rst),
    .data_in(tx_byte),
    .send(tx_send),
    .tx(uart_tx_pin),
    .ready(uart_tx_ready)
);
```

The `ready`/`send` handshake ensures bytes are sent one at a time with correct timing,
even though the top module's FSM runs millions of times faster than a UART byte transmission.

### Back-to-Back Byte Transmission

When sending multiple bytes (like all 16,384 bytes of the image), the top module sends
them as fast as `uart_tx` allows:

```
  Byte 1            Byte 2            Byte 3
  ┌───────────┐     ┌───────────┐     ┌───────────┐
  │S|D0...D7|P│     │S|D0...D7|P│     │S|D0...D7|P│
  └───────────┘     └───────────┘     └───────────┘
  |◄── 8680 ──►|    |◄── 8680 ──►|    |◄── 8680 ──►|
      clocks            clocks            clocks

  ready: ___|‾|_______________|‾|_______________|‾|___
             ↑                 ↑                 ↑
        send byte 1       send byte 2       send byte 3

  No idle gap between bytes — maximum throughput!
  (ready goes HIGH for ~1 cycle between bytes)
```

At 115,200 baud, the total time to send 16,384 bytes:
```
16,384 bytes x 8,680 clocks/byte x 10 ns/clock
= 16,384 x 86,800 ns
= 1,422,131,200 ns
= ~1.42 seconds
```

---

## 10. Key Takeaways

1. **`uart_tx` converts parallel data to serial**: It takes an 8-bit byte (`data_in`) and
   sends it out one bit at a time on the `tx` wire, wrapped in a UART frame (start bit, 8 data
   bits LSB-first, stop bit).

2. **The send/ready handshake** is how the top module and `uart_tx` communicate:
   - `ready = 1` means "give me a byte."
   - The top module asserts `send = 1` for one cycle with the byte on `data_in`.
   - `ready` drops to 0 while the byte is being serialized.
   - `ready` returns to 1 when done.

3. **`ready` is combinational** (`assign ready = (state == S_IDLE);`) — it responds instantly
   when the FSM returns to IDLE, with no one-cycle delay. This is more efficient than a
   registered version.

4. **`tx_shift` latches the byte** at the moment `send` is asserted. This frees the top module
   to change `data_in` immediately without corrupting the ongoing transmission.

5. **No synchronizer is needed** because the `tx` output is driven by our own synchronous logic.
   Synchronizers are only needed for **inputs** that come from external, asynchronous sources.

6. **No `HALF_BIT` is needed** because the transmitter drives the line — it does not need to
   find the middle of a bit period. Only the receiver needs mid-bit alignment.

7. **The FSM mirrors `uart_rx`**: Same 4 states (IDLE, START, DATA, STOP), same bit-indexing
   pattern (`tx_shift[bit_idx]`), same 868-clock bit period. The only difference is the
   direction: TX drives the line, RX samples it.

8. **Each transmitted byte takes exactly 8,680 clock cycles** (10 bit periods x 868 clocks
   = 86.8 microseconds). Transmitting the full 16 KB image takes about 1.42 seconds.

9. **The `tx` line idles HIGH** and uses LOW for the start bit. This is the UART standard —
   both `uart_rx` and `uart_tx` agree on this convention.

10. **The `default` case** ensures the FSM can never get stuck in an undefined state — it
    always recovers to IDLE.

---

> **Next**: [Document 07 -- Pixel Buffer (pixel_buffer.v)](07_Pixel_Buffer_pixel_buffer.md) -- Learn how the pixel buffer collects 16 individual bytes from `uart_rx` into a single 128-bit AES block.
