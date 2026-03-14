# Document 05: UART Receiver (`uart_rx.v`)

> **Goal**: By the end of this document, you will fully understand every line of the UART receiver
> module — how it detects a start bit, samples incoming data bits at the correct moment, assembles
> them into a byte, and signals the rest of the system that a valid byte has arrived. You will be
> able to trace through the entire state machine cycle-by-cycle for any incoming byte.

---

## Table of Contents
1. [What Does `uart_rx` Do?](#1-what-does-uart_rx-do)
2. [Module Interface — Every Port Explained](#2-module-interface--every-port-explained)
3. [Parameters and Local Parameters — The Math](#3-parameters-and-local-parameters--the-math)
4. [The Double Flip-Flop Synchronizer](#4-the-double-flip-flop-synchronizer)
5. [FSM State Diagram](#5-fsm-state-diagram)
6. [Detailed Walkthrough of Each State](#6-detailed-walkthrough-of-each-state)
7. [Complete Numerical Example: Receiving 0x55](#7-complete-numerical-example-receiving-0x55)
8. [Timing Diagram — Where Sampling Happens](#8-timing-diagram--where-sampling-happens)
9. [The `data_valid` Pulse and How the Top Module Uses It](#9-the-data_valid-pulse-and-how-the-top-module-uses-it)
10. [Key Takeaways](#10-key-takeaways)

---

## 1. What Does `uart_rx` Do?

`uart_rx` is the **UART Receiver** module. Its job is to listen on a single wire (`rx`), detect
incoming UART frames from the PC, and convert the serial bitstream back into parallel 8-bit bytes.

### Analogy: A Tape Recorder with Perfect Timing

Imagine you are listening to a friend spell out a word over the phone, one letter at a time, at a
pre-agreed pace. You know:
- Silence (the line is quiet) means no message is coming.
- A "beep" (start bit) means "get ready, here come 8 letters!"
- You then listen at exact intervals to hear each letter.
- A final "ding" (stop bit) means "that was the last letter."
- You write down the complete word and shout "GOT IT!" (data_valid pulse).

`uart_rx` does exactly this, but with electrical signals and a 100 MHz clock counting time.

### Where It Sits in the System

```
  PC (Python)                    FPGA
  ┌──────────┐                  ┌─────────────────────────────────────┐
  │          │   USB/UART       │                                     │
  │  Sends   │  serial data     │   rx pin                            │
  │  bytes   │ ────────────────►│ ──► [uart_rx] ──► data_out[7:0]    │
  │          │  one bit at      │                    data_valid        │
  │          │  a time           │         │                            │
  └──────────┘                  │         ▼                            │
                                │   [pixel_buffer] ──► 128-bit block  │
                                │         │                            │
                                │         ▼                            │
                                │   [aes_ctrl / aes_core] ──► BRAM    │
                                └─────────────────────────────────────┘
```

Every byte the PC sends eventually passes through `uart_rx` first. It is the front door of the
entire FPGA system.

---

## 2. Module Interface — Every Port Explained

Here is the module declaration:

```verilog
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);
```

### Port Table

| Port | Direction | Width | Type | Description |
|------|-----------|-------|------|-------------|
| `clk` | input | 1 bit | `wire` | The FPGA system clock (100 MHz on Basys 3). Every piece of logic in this module updates on the **rising edge** of this clock. |
| `rst` | input | 1 bit | `wire` | Synchronous active-high reset. When `rst = 1`, all internal registers are forced to their initial values. The module does nothing until `rst` goes back to `0`. |
| `rx` | input | 1 bit | `wire` | The raw serial data line coming from the USB-UART bridge chip. This wire carries the UART frame one bit at a time. It idles HIGH (1) when no data is being sent. **This signal is asynchronous** — it has no relationship to our `clk`. |
| `data_out` | output | 8 bits | `reg` | The received byte. After `uart_rx` successfully receives all 8 data bits and the stop bit, this register holds the complete byte. It stays valid until the next byte is received. |
| `data_valid` | output | 1 bit | `reg` | A one-clock-cycle HIGH pulse that says "the byte on `data_out` is ready and correct." Other modules (like `pixel_buffer`) watch this signal to know when to grab the byte. |

### Visual Port Diagram

```
                     ┌─────────────────┐
           clk ─────►│                 │
           rst ─────►│                 │
                     │    uart_rx      │
            rx ─────►│                 ├─────► data_out [7:0]
                     │                 ├─────► data_valid
                     │                 │
                     └─────────────────┘

  Inputs (left):                    Outputs (right):
  - clk:  100 MHz system clock     - data_out:   the received byte
  - rst:  synchronous reset        - data_valid: 1-cycle "byte ready" pulse
  - rx:   serial data from PC
```

### Why `data_out` and `data_valid` are `reg` (not `wire`)

Both outputs are assigned inside an `always @(posedge clk)` block, so Verilog requires them to be
declared as `reg`. In hardware, they become flip-flops — they hold their value from one clock edge
to the next.

---

## 3. Parameters and Local Parameters — The Math

```verilog
parameter CLK_FREQ  = 100_000_000;
parameter BAUD_RATE = 115_200;

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868
localparam HALF_BIT     = CLKS_PER_BIT / 2;      // 434
```

### `CLK_FREQ` — The FPGA Clock Frequency

- Default: `100_000_000` (100 million Hz = 100 MHz)
- This is the Basys 3 board's onboard oscillator frequency.
- The underscores are just for readability: `100_000_000` = `100000000`.
- Declared as `parameter` so it can be overridden when instantiating (e.g., in testbenches).

### `BAUD_RATE` — The Serial Communication Speed

- Default: `115_200` (115,200 bits per second)
- Both the PC and FPGA must agree on this number. If they differ, data gets corrupted.
- This is the most common high-speed baud rate and matches our Python script's configuration.

### `CLKS_PER_BIT` — Clock Cycles Per UART Bit

This is the most critical calculation in the entire module:

```
CLKS_PER_BIT = CLK_FREQ / BAUD_RATE
             = 100,000,000 / 115,200
             = 868.055...
             ≈ 868  (integer division truncates the decimal)
```

**What it means**: Each bit in the UART frame lasts exactly **868 clock cycles**. To read a bit,
we wait 868 clocks, then sample the line.

```
  One UART bit period:
  |◄──────────────────── 868 clock cycles ────────────────────►|
  |                                                              |
  Clock: |_|‾|_|‾|_|‾|_|‾|_|‾|_|‾| ... (868 rising edges) ... |_|‾|
  RX:    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
         The RX line holds a stable 0 or 1 for 868 clock cycles.
```

### `HALF_BIT` — Half a Bit Period

```
HALF_BIT = CLKS_PER_BIT / 2
         = 868 / 2
         = 434
```

**What it means**: To sample a bit at its **center** (the most stable point), we count 434 clock
cycles from the start of that bit. This is used during the start bit to align our sampling to the
middle of each bit period.

```
  Why sample at the center?

  |◄─────── One bit period (868 clocks) ───────►|
  |                                               |
  RX: ___________________________________________
       ↑            ↑              ↑
    Transition   MID-POINT      Transition
    (noisy)    (434 clocks)     (noisy)
               SAMPLE HERE!
               Most stable,
               farthest from
               both edges.
```

### Why `localparam` Instead of `parameter`?

- `CLKS_PER_BIT` and `HALF_BIT` are **derived constants** — they are calculated from the real
  parameters (`CLK_FREQ` and `BAUD_RATE`).
- Using `localparam` means they cannot be accidentally overridden from outside the module.
- They are computed at **synthesis time** (before the design is loaded onto the FPGA), not at
  runtime. The division happens in the Verilog compiler, not in hardware.

---

## 4. The Double Flip-Flop Synchronizer

```verilog
reg rx_sync_0, rx_sync_1;

always @(posedge clk) begin
    if (rst) begin
        rx_sync_0 <= 1'b1;
        rx_sync_1 <= 1'b1;
    end else begin
        rx_sync_0 <= rx;
        rx_sync_1 <= rx_sync_0;
    end
end
```

### Why Do We Need This?

The `rx` signal comes from the outside world (the USB-UART chip on the Basys 3). It changes
at completely unpredictable times relative to our 100 MHz clock. As explained in
[Document 04 — Section 8](04_UART_Protocol_Deep_Dive.md#8-metastability--why-we-need-a-double-flip-flop),
this creates a **metastability** risk: if `rx` changes at the exact moment of a clock edge, a
flip-flop can enter an unstable "neither 0 nor 1" state that can cause the entire FSM to
malfunction.

### How the Synchronizer Works

We pass the raw `rx` through **two flip-flops in series**:

```
  External World         FPGA Internal Logic
       │                        │
       │    ┌──────┐    ┌──────┐    ┌──────────────────────┐
  rx ──┼───►│ FF1  ├───►│ FF2  ├───►│  FSM (safe to use)   │
       │    │      │    │      │    │  uses rx_sync_1       │
       │    └──┬───┘    └──┬───┘    └──────────────────────┘
       │       │           │
       │   rx_sync_0   rx_sync_1
       │   (might be   (almost certainly
       │    metastable)  stable)
       │
  Asynchronous
  (dangerous!)
```

### Line-by-Line Explanation

**`reg rx_sync_0, rx_sync_1;`**

Declares two 1-bit registers. These will become two physical flip-flops in the FPGA.

**`if (rst) begin`**

On reset, both flip-flops are forced to `1'b1` (HIGH). This is important because the UART idle
state is HIGH. If we reset to 0, the FSM would falsely detect a "start bit" immediately after
reset.

**`rx_sync_0 <= rx;`**

First flip-flop (FF1): captures the raw, asynchronous `rx` signal. This flip-flop might go
metastable, but it has an entire clock period (10 ns at 100 MHz) to settle before the second
flip-flop reads it.

**`rx_sync_1 <= rx_sync_0;`**

Second flip-flop (FF2): captures the output of FF1. By the time FF2 reads `rx_sync_0`, that
signal has had 10 ns to resolve from any metastable state. The probability of metastability
propagating through both flip-flops is astronomically low (once per thousands of years at
100 MHz).

### Timing of the Synchronizer

The synchronizer introduces a **2-clock-cycle delay** between the real `rx` and `rx_sync_1`:

```
Clock:      __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
              1    2    3    4    5    6    7

rx:         ‾‾‾‾‾‾‾|_______________________________   (goes LOW at some random time)
                     ↑
rx_sync_0:  ‾‾‾‾‾‾‾‾‾‾‾|__________________________   (captured 1 cycle later)
                          ↑
rx_sync_1:  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_______________________  (captured 2 cycles later)
                              ↑
                         This is the signal
                         the FSM actually sees.

Delay = 2 clock cycles = 20 ns at 100 MHz.
This is negligible compared to one bit period (8,680 ns).
```

**Key rule**: The rest of the module **never** reads `rx` directly. It always reads `rx_sync_1`.

---

## 5. FSM State Diagram

The receiver uses a 4-state **Finite State Machine** (FSM) to process each incoming UART frame:

```verilog
localparam S_IDLE  = 3'd0;
localparam S_START = 3'd1;
localparam S_DATA  = 3'd2;
localparam S_STOP  = 3'd3;
```

### ASCII State Diagram

```
                          ┌──────────────────────────────────────┐
                          │                                      │
                          ▼                                      │
                   ┌─────────────┐                               │
            ┌─────│   S_IDLE     │◄──────────────────────┐      │
            │     │   (3'd0)     │                        │      │
            │     │              │      rx_sync_1 == 1    │      │
            │     │ Wait for     │      (false start)     │      │
            │     │ falling edge │                        │      │
            │     └─────────────┘                        │      │
            │           │                                 │      │
            │           │ rx_sync_1 == 0                  │      │
            │           │ (start bit detected!)           │      │
            │           ▼                                 │      │
            │     ┌─────────────┐                        │      │
            │     │  S_START    │                        │      │
            │     │  (3'd1)     │────────────────────────┘      │
            │     │             │  clk_cnt == 433 AND           │
            │     │ Wait 434    │  rx_sync_1 == 1               │
            │     │ clocks to   │  (noise, not a real           │
            │     │ mid-start   │   start bit)                  │
            │     └─────────────┘                               │
            │           │                                        │
            │           │ clk_cnt == 433 AND                     │
            │           │ rx_sync_1 == 0                         │
            │           │ (confirmed start bit!)                 │
            │           ▼                                        │
            │     ┌─────────────┐                               │
            │     │  S_DATA     │◄────┐                         │
            │     │  (3'd2)     │     │ bit_idx < 7             │
            │     │             │     │ (more bits to receive)  │
            │     │ Sample one  │─────┘                         │
            │     │ data bit    │  clk_cnt == 867               │
            │     │ every 868   │                               │
            │     │ clocks      │                               │
            │     └─────────────┘                               │
            │           │                                        │
            │           │ bit_idx == 7 AND clk_cnt == 867       │
            │           │ (all 8 bits received!)                │
            │           ▼                                        │
            │     ┌─────────────┐                               │
            │     │  S_STOP     │                               │
            │     │  (3'd3)     │───────────────────────────────┘
            │     │             │  clk_cnt == 867
            │     │ Wait 868    │  (stop bit period done)
            │     │ clocks for  │  => output data_out, pulse data_valid
            │     │ stop bit    │
            │     └─────────────┘
            │
            │     ┌─────────────┐
            └────►│  default    │──► Goes to S_IDLE
                  │  (safety)   │    (catches illegal states)
                  └─────────────┘
```

### The Four States at a Glance

| State | Code | Purpose | Duration | What Triggers Exit |
|-------|------|---------|----------|--------------------|
| `S_IDLE` | `3'd0` | Wait for the RX line to go LOW (start bit falling edge) | Indefinite | `rx_sync_1 == 0` |
| `S_START` | `3'd1` | Count 434 clocks to reach the middle of the start bit, then verify it is still LOW | 434 clocks | `clk_cnt == 433` |
| `S_DATA` | `3'd2` | Sample one data bit every 868 clocks, repeat 8 times (bits 0 through 7) | 8 x 868 = 6,944 clocks | `bit_idx == 7` AND `clk_cnt == 867` |
| `S_STOP` | `3'd3` | Wait 868 clocks for the stop bit, then output the byte and pulse `data_valid` | 868 clocks | `clk_cnt == 867` |

---

## 6. Detailed Walkthrough of Each State

### Internal Registers

Before diving into the states, let's understand every internal register:

```verilog
reg [2:0]  state;      // Current FSM state (3 bits: can hold 0-7, we use 0-3)
reg [15:0] clk_cnt;    // Clock cycle counter within the current state
                        //   16 bits wide: can count up to 65,535
                        //   We only need to count to 867, but 16 bits gives headroom
reg [2:0]  bit_idx;    // Which data bit we are currently receiving (0 to 7)
reg [7:0]  rx_shift;   // Shift register where received bits are assembled into a byte
```

### 6.1 S_IDLE — Waiting for a Start Bit

```verilog
S_IDLE: begin
    clk_cnt <= 16'd0;
    bit_idx <= 3'd0;
    if (rx_sync_1 == 1'b0)
        state <= S_START;
end
```

**What is happening**: The module is idle, waiting for the PC to start sending a byte. The
UART line idles HIGH (`1`). The module continuously resets `clk_cnt` and `bit_idx` to zero
so they are ready when a byte arrives.

**Line-by-line**:

- `clk_cnt <= 16'd0;` — Reset the clock counter to zero every single clock cycle. This ensures
  the counter starts fresh when we leave IDLE.

- `bit_idx <= 3'd0;` — Reset the bit index to zero. When we start receiving data, we want to
  begin at bit 0.

- `if (rx_sync_1 == 1'b0)` — Check if the synchronized RX line has gone LOW. Remember, UART
  idle is HIGH. A transition from HIGH to LOW is the **start bit** — the PC is beginning to
  send a byte.

- `state <= S_START;` — Move to the START state to verify this is a real start bit (not just
  noise).

**Analogy**: You are sitting by the phone. It rings (rx goes LOW). You pick up the phone and
say "let me make sure someone is really there" (move to S_START to verify).

### 6.2 S_START — Verifying the Start Bit at Mid-Point

```verilog
S_START: begin
    if (clk_cnt == HALF_BIT - 1) begin
        clk_cnt <= 16'd0;
        if (rx_sync_1 == 1'b0)
            state <= S_DATA;
        else
            state <= S_IDLE;
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: We detected a LOW on the RX line in IDLE. But was it a real start bit
or just a brief noise glitch? To find out, we wait **434 clock cycles** (half a bit period) to
reach the **center** of the start bit, then check again.

```
  What we're doing in S_START:

  rx_sync_1:  ‾‾‾‾|_________________________________________
                   ↑                    ↑
              We detected this     We check again here
              LOW in S_IDLE        (434 clocks later)
              (entered S_START)    at the CENTER of the start bit

              |◄── 434 clocks ──►|
                   (HALF_BIT)

  If still LOW → real start bit → go to S_DATA
  If now HIGH  → was just noise → go back to S_IDLE
```

**Line-by-line**:

- `if (clk_cnt == HALF_BIT - 1)` — We check for `HALF_BIT - 1` (= 433), not `HALF_BIT` (434).
  Why? Because `clk_cnt` starts at 0. Counting from 0 to 433 is **434 cycles**
  (0, 1, 2, ..., 433 = 434 values). This is a classic **off-by-one** pattern in hardware:
  to count N cycles, compare against N-1.

- `clk_cnt <= 16'd0;` — Reset the counter. We are now aligned to the center of the start bit.
  From this point forward, counting 868 more cycles will land us at the center of the next
  bit (data bit 0).

- `if (rx_sync_1 == 1'b0)` — The mid-bit verification. Is the line still LOW?
  - **YES** (`rx_sync_1 == 0`): This is a legitimate start bit. Proceed to receive data.
    `state <= S_DATA;`
  - **NO** (`rx_sync_1 == 1`): The line went back HIGH — it was just a noise glitch.
    Go back to idle. `state <= S_IDLE;`

- `clk_cnt <= clk_cnt + 16'd1;` — If we haven't reached 433 yet, keep counting.

**Why verify?**: A noise spike might cause the RX line to dip LOW for just a few clock cycles.
Without this check, the module would try to receive a nonexistent byte and produce garbage.
By waiting to the mid-point, we filter out short noise spikes.

### 6.3 S_DATA — Receiving the 8 Data Bits

```verilog
S_DATA: begin
    if (clk_cnt == CLKS_PER_BIT - 1) begin
        clk_cnt <= 16'd0;
        rx_shift[bit_idx] <= rx_sync_1;
        if (bit_idx == 3'd7) begin
            bit_idx <= 3'd0;
            state   <= S_STOP;
        end else begin
            bit_idx <= bit_idx + 3'd1;
        end
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: This is the core of the receiver. We wait 868 clock cycles (one full
bit period), then sample the RX line to read one data bit. We repeat this 8 times to collect
all 8 data bits (bit 0 through bit 7, LSB first).

```
  Sampling points during S_DATA:

  rx_sync_1: __|‾‾‾‾‾‾‾‾‾|_________|‾‾‾‾‾‾‾‾‾|_________|‾‾‾‾‾ ...
               │    D0     │    D1    │    D2    │    D3    │
               |◄── 868 ──►|◄── 868 ──►|◄── 868 ──►|◄── 868 ──►|

  clk_cnt:   0...........867  0.......867  0.......867  0.......867
                            ↑            ↑            ↑            ↑
                          SAMPLE       SAMPLE       SAMPLE       SAMPLE
                          bit_idx=0    bit_idx=1    bit_idx=2    bit_idx=3
```

**Line-by-line**:

- `if (clk_cnt == CLKS_PER_BIT - 1)` — Have we counted 868 cycles (0 to 867)? If yes, we are
  at the center of the current data bit.

- `clk_cnt <= 16'd0;` — Reset counter for the next bit period.

- `rx_shift[bit_idx] <= rx_sync_1;` — **This is the key line!** It places the sampled bit
  directly into the correct position in `rx_shift`. Because UART sends LSB first:
  - First bit received (bit_idx = 0) goes into `rx_shift[0]` (the LSB)
  - Second bit received (bit_idx = 1) goes into `rx_shift[1]`
  - ...
  - Eighth bit received (bit_idx = 7) goes into `rx_shift[7]` (the MSB)

  This is more elegant than a traditional shift register. Instead of shifting bits around,
  we directly place each bit at its final position. The result is the correctly-ordered byte
  with no additional reconstruction needed.

- `if (bit_idx == 3'd7)` — Have we received all 8 bits (indices 0 through 7)?
  - **YES**: Reset `bit_idx` to 0, move to `S_STOP` to wait for the stop bit.
  - **NO**: Increment `bit_idx` to prepare for the next data bit.

- `clk_cnt <= clk_cnt + 16'd1;` — If we haven't hit 867 yet, keep counting.

**Why `rx_shift[bit_idx]` instead of a traditional shift?**

A traditional shift register would do something like:
```verilog
rx_shift <= {rx_sync_1, rx_shift[7:1]};  // shift right, new bit at MSB
```

Our code uses indexed assignment instead:
```verilog
rx_shift[bit_idx] <= rx_sync_1;  // place bit directly at correct position
```

Both approaches produce the same result, but the indexed assignment is easier to understand:
bit 0 goes to position 0, bit 1 goes to position 1, and so on. No mental gymnastics needed.

### 6.4 S_STOP — Waiting for the Stop Bit, Outputting the Byte

```verilog
S_STOP: begin
    if (clk_cnt == CLKS_PER_BIT - 1) begin
        clk_cnt    <= 16'd0;
        data_out   <= rx_shift;
        data_valid <= 1'b1;
        state      <= S_IDLE;
    end else begin
        clk_cnt <= clk_cnt + 16'd1;
    end
end
```

**What is happening**: All 8 data bits are now in `rx_shift`. The UART protocol says the next
bit on the line is the **stop bit** (always HIGH). We wait one full bit period (868 clocks)
to let the stop bit pass, then output the received byte and pulse `data_valid`.

**Line-by-line**:

- `if (clk_cnt == CLKS_PER_BIT - 1)` — Have we waited the full stop bit period (868 clocks)?

- `clk_cnt <= 16'd0;` — Reset the counter.

- `data_out <= rx_shift;` — Copy the fully assembled byte from the internal shift register
  to the output port. This is when the byte becomes visible to the rest of the system.

- `data_valid <= 1'b1;` — Pulse HIGH for exactly one clock cycle. This tells downstream
  modules (like `pixel_buffer`) "there is a fresh, valid byte on `data_out` right now —
  grab it!"

- `state <= S_IDLE;` — Return to idle, ready for the next byte.

**Important**: Note that at the top of the `always` block (outside the `case` statement),
there is:
```verilog
data_valid <= 1'b0;
```

This means `data_valid` is driven LOW **every clock cycle by default**. It only goes HIGH
for the **single clock cycle** when we execute `data_valid <= 1'b1;` in S_STOP. On the
very next clock cycle, the default assignment takes over and drives it back LOW. This creates
a clean **one-cycle pulse**.

```
  data_valid timing:

  Clock:      |__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|
  data_valid: _________________________|‾‾‾|________________________
                                        ↑
                              Exactly ONE clock cycle wide.
                              This is the moment pixel_buffer
                              reads data_out.
```

### 6.5 Default — Safety Net

```verilog
default: state <= S_IDLE;
```

If the `state` register ever holds a value outside {0, 1, 2, 3} (e.g., due to a cosmic ray
flipping a bit, or a synthesis tool optimization error), the FSM will recover by going back to
IDLE. Without this, the FSM could get stuck in an undefined state permanently.

This is a defensive coding practice — always include `default` in your `case` statements.

---

## 7. Complete Numerical Example: Receiving 0x55

Let's trace through the **entire** process of receiving the byte **0x55**.

### Setup

```
Byte to receive: 0x55
Binary:          0101_0101
Bits in UART transmission order (LSB first):
  bit 0 = 1
  bit 1 = 0
  bit 2 = 1
  bit 3 = 0
  bit 4 = 1
  bit 5 = 0
  bit 6 = 1
  bit 7 = 0
```

The full UART frame on the wire looks like:

```
                START  D0  D1  D2  D3  D4  D5  D6  D7  STOP
rx_sync_1: ‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|____|‾‾‾‾|‾‾‾‾
                  0    1    0    1    0    1    0    1    0    1
```

0x55 is a convenient test byte because its bits alternate: 1, 0, 1, 0, 1, 0, 1, 0 (LSB first).
This makes the waveform easy to visualize and is a common test pattern.

### Phase 1: S_IDLE — Detecting the Start Bit

The module is in S_IDLE. The RX line has been HIGH (idle). Suddenly, the PC starts sending 0x55.

```
Clock Cycle  | state   | rx_sync_1 | clk_cnt | bit_idx | Action
─────────────┼─────────┼───────────┼─────────┼─────────┼──────────────────────
...          | S_IDLE  |     1     |    0    |    0    | Waiting... line is HIGH
...          | S_IDLE  |     1     |    0    |    0    | Still waiting...
Cycle N      | S_IDLE  |     0     |    0    |    0    | rx went LOW! Start bit!
             |         |           |         |         | => state <= S_START
```

The moment `rx_sync_1` goes to 0, the FSM transitions to S_START. Note that due to the
double flip-flop, this detection happens 2 clock cycles after the actual RX line changed.
That 20 ns delay is negligible.

### Phase 2: S_START — Verifying at Mid-Point (Count to 433)

We need to count 434 clock cycles (0 through 433) to reach the center of the start bit.

```
Clock Cycle  | state   | rx_sync_1 | clk_cnt | bit_idx | Action
─────────────┼─────────┼───────────┼─────────┼─────────┼──────────────────────
N+1          | S_START |     0     |    0    |    0    | Start counting
N+2          | S_START |     0     |    1    |    0    | clk_cnt++
N+3          | S_START |     0     |    2    |    0    | clk_cnt++
...          | S_START |     0     |   ...   |    0    | counting...
N+434        | S_START |     0     |   433   |    0    | clk_cnt == HALF_BIT-1!
             |         |           |         |         | rx_sync_1 is still 0
             |         |           |         |         | => Confirmed start bit!
             |         |           |         |         | clk_cnt <= 0
             |         |           |         |         | => state <= S_DATA
```

If `rx_sync_1` had been 1 at cycle N+434, the module would go back to S_IDLE (false alarm).

### Phase 3: S_DATA — Sampling All 8 Data Bits

Now we are at the center of the start bit. Counting 868 more clocks lands us at the center
of data bit 0 (D0). We sample, then count 868 again for D1, and so on for all 8 bits.

```
Clock Cycle       | state  | rx_sync_1 | clk_cnt | bit_idx | rx_shift   | Action
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+435             | S_DATA |     0     |    0    |    0    | 00000000   | Start counting for D0
N+436             | S_DATA |     0     |    1    |    0    | 00000000   | clk_cnt++
...               | S_DATA |   ...     |   ...   |    0    | 00000000   | counting...
N+1302            | S_DATA |     1     |   867   |    0    | 00000000   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=1
                  |        |           |         |         | 00000001   | rx_shift[0] <= 1
                  |        |           |         |         |            | bit_idx <= 1
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+1303            | S_DATA |     1     |    0    |    1    | 00000001   | Start counting for D1
...               |        |           |         |         |            | counting...
N+2170            | S_DATA |     0     |   867   |    1    | 00000001   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=0
                  |        |           |         |         | 00000001   | rx_shift[1] <= 0
                  |        |           |         |         |            | bit_idx <= 2
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+2171            | S_DATA |     0     |    0    |    2    | 00000001   | Start counting for D2
...               |        |           |         |         |            | counting...
N+3038            | S_DATA |     1     |   867   |    2    | 00000001   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=1
                  |        |           |         |         | 00000101   | rx_shift[2] <= 1
                  |        |           |         |         |            | bit_idx <= 3
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+3039            | S_DATA |     1     |    0    |    3    | 00000101   | Start counting for D3
...               |        |           |         |         |            | counting...
N+3906            | S_DATA |     0     |   867   |    3    | 00000101   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=0
                  |        |           |         |         | 00000101   | rx_shift[3] <= 0
                  |        |           |         |         |            | bit_idx <= 4
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+3907            | S_DATA |     0     |    0    |    4    | 00000101   | Start counting for D4
...               |        |           |         |         |            | counting...
N+4774            | S_DATA |     1     |   867   |    4    | 00000101   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=1
                  |        |           |         |         | 00010101   | rx_shift[4] <= 1
                  |        |           |         |         |            | bit_idx <= 5
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+4775            | S_DATA |     1     |    0    |    5    | 00010101   | Start counting for D5
...               |        |           |         |         |            | counting...
N+5642            | S_DATA |     0     |   867   |    5    | 00010101   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=0
                  |        |           |         |         | 00010101   | rx_shift[5] <= 0
                  |        |           |         |         |            | bit_idx <= 6
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+5643            | S_DATA |     0     |    0    |    6    | 00010101   | Start counting for D6
...               |        |           |         |         |            | counting...
N+6510            | S_DATA |     1     |   867   |    6    | 00010101   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=1
                  |        |           |         |         | 01010101   | rx_shift[6] <= 1
                  |        |           |         |         |            | bit_idx <= 7
                  |        |           |         |         |            | clk_cnt <= 0
──────────────────┼────────┼───────────┼─────────┼─────────┼────────────┼──────────────
N+6511            | S_DATA |     1     |    0    |    7    | 01010101   | Start counting for D7
...               |        |           |         |         |            | counting...
N+7378            | S_DATA |     0     |   867   |    7    | 01010101   | clk_cnt==867!
                  |        |           |         |         |            | Sample: rx_sync_1=0
                  |        |           |         |         | 01010101   | rx_shift[7] <= 0
                  |        |           |         |         |            | bit_idx == 7!
                  |        |           |         |         |            | All 8 bits done!
                  |        |           |         |         |            | bit_idx <= 0
                  |        |           |         |         |            | => state <= S_STOP
                  |        |           |         |         |            | clk_cnt <= 0
```

### Reconstructing the Byte

After all 8 bits are sampled, `rx_shift` contains:

```
  rx_shift[7] = 0  (D7, last bit received)
  rx_shift[6] = 1
  rx_shift[5] = 0
  rx_shift[4] = 1
  rx_shift[3] = 0
  rx_shift[2] = 1
  rx_shift[1] = 0
  rx_shift[0] = 1  (D0, first bit received)

  rx_shift = 0101_0101 = 0x55   Correct!
```

### Phase 4: S_STOP — Outputting the Byte

```
Clock Cycle       | state  | rx_sync_1 | clk_cnt | data_out | data_valid | Action
──────────────────┼────────┼───────────┼─────────┼──────────┼────────────┼──────────
N+7379            | S_STOP |     0     |    0    | (old)    |     0      | Start counting
N+7380            | S_STOP |     1     |    1    | (old)    |     0      | clk_cnt++
...               | S_STOP |     1     |   ...   | (old)    |     0      | counting...
N+8246            | S_STOP |     1     |   867   | (old)    |     0      | clk_cnt==867!
                  |        |           |         | 01010101 |     1      | data_out <= rx_shift
                  |        |           |         | = 0x55   |            | data_valid <= 1
                  |        |           |         |          |            | => state <= S_IDLE
──────────────────┼────────┼───────────┼─────────┼──────────┼────────────┼──────────
N+8247            | S_IDLE |     1     |    0    |   0x55   |     0      | Back to idle.
                  |        |           |         |          |            | data_valid back to 0
                  |        |           |         |          |            | (default assignment)
```

### Summary of Total Duration

```
Phase            Clock Cycles
─────            ────────────
S_IDLE           1 (detection cycle)
S_START          434 (half-bit verification)
S_DATA           8 x 868 = 6,944 (eight data bits)
S_STOP           868 (stop bit)
─────            ────────────
Total            1 + 434 + 6,944 + 868 = 8,247 clock cycles

At 100 MHz: 8,247 x 10 ns = 82,470 ns = 82.47 us

(Theoretical: 10 bit periods x 868 clocks = 8,680 clocks = 86.8 us.
 The difference is because we jump from the falling edge mid-start rather
 than waiting a full start bit period. This is by design.)
```

---

## 8. Timing Diagram — Where Sampling Happens

This diagram shows the complete UART frame for byte 0x55 and exactly where each sample point
falls:

```
  rx_sync_1:
  ‾‾‾‾‾‾┐     ┌─────┐     ┌─────┐     ┌─────┐     ┌─────┐     ┌─────────
        │     │     │     │     │     │     │     │     │     │     │
        │     │     │     │     │     │     │     │     │     │     │
        └─────┘     └─────┘     └─────┘     └─────┘     └─────┘     │
   IDLE  START  D0=1  D1=0  D2=1  D3=0  D4=1  D5=0  D6=1  D7=0  STOP  IDLE

  Sample
  Points:  ↑       ↑     ↑     ↑     ↑     ↑     ↑     ↑     ↑     ↑
           │       │     │     │     │     │     │     │     │     │
         S_START  D0    D1    D2    D3    D4    D5    D6    D7  S_STOP
         verify  sample sample ...  ...   ...   ...   ...  sample  output
        (434clk) (+868) (+868)(+868)(+868)(+868)(+868)(+868)(+868) data_valid=1

  clk_cnt
  resets:  0      0     0     0     0     0     0     0     0     0


  Detailed timing (clock cycle offsets from start bit detection):

  Event                  Offset from detection    clk_cnt at sample
  ─────                  ─────────────────────    ──────────────────
  Start bit detected     0                        --
  Mid-start verified     434                      433
  Sample D0 (bit 0)      434 + 868  = 1302       867
  Sample D1 (bit 1)      434 + 1736 = 2170       867
  Sample D2 (bit 2)      434 + 2604 = 3038       867
  Sample D3 (bit 3)      434 + 3472 = 3906       867
  Sample D4 (bit 4)      434 + 4340 = 4774       867
  Sample D5 (bit 5)      434 + 5208 = 5642       867
  Sample D6 (bit 6)      434 + 6076 = 6510       867
  Sample D7 (bit 7)      434 + 6944 = 7378       867
  Stop bit done          434 + 7812 = 8246       867
```

Notice how the sample points all fall in the **center** of each bit period. This gives the
maximum margin for timing errors between the sender and receiver clocks.

```
  Zoomed in on one data bit:

  |◄──────────── 868 clock cycles ─────────────►|
  |                                               |
  rx:  ───────────────────────────────────────────
       ↑              ↑              ↑
    Bit starts     SAMPLE          Bit ends
    (transition)   POINT           (transition)
                   (434 clocks
                    from start)

       |◄── 434 ──►|◄──── 434 ────►|

  Even if the sender's clock is slightly off, the sample point
  has 434 cycles of margin on each side before hitting a transition.
```

---

## 9. The `data_valid` Pulse and How the Top Module Uses It

### The One-Cycle Pulse

`data_valid` is HIGH for exactly **one clock cycle**, then goes back LOW. Here is how this
works mechanically:

```verilog
always @(posedge clk) begin
    if (rst) begin
        // ... reset ...
        data_valid <= 1'b0;         // Reset: data_valid = 0
    end else begin
        data_valid <= 1'b0;         // DEFAULT: data_valid = 0 every cycle

        case (state)
            // ...
            S_STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    data_valid <= 1'b1;  // OVERRIDE: data_valid = 1 for this ONE cycle
                    // ...
                end
            end
        endcase
    end
end
```

In Verilog's non-blocking assignment semantics, when both `data_valid <= 1'b0` and
`data_valid <= 1'b1` execute in the same clock cycle, the **last assignment wins**. So
during the single cycle in S_STOP, `data_valid` becomes 1. On the very next cycle, only the
default `data_valid <= 1'b0` executes, so it goes back to 0.

```
  Timeline:

  Cycle K-1:   data_valid <= 0  (default)               → data_valid = 0
  Cycle K:     data_valid <= 0  (default, overridden)
               data_valid <= 1  (S_STOP fires)           → data_valid = 1
  Cycle K+1:   data_valid <= 0  (default, back to IDLE)  → data_valid = 0

  Result:
  data_valid: _____|‾‾‾‾‾|_________________________________
                   ↑     ↑
              Goes HIGH   Goes LOW
              (1 cycle)   (stays LOW until next byte)
```

### How `pixel_buffer` Uses This Signal

In `top.v`, the `pixel_buffer` module is connected to `uart_rx`'s outputs:

```verilog
// In top.v (simplified):
wire [7:0] rx_data;
wire       rx_valid;

uart_rx u_rx (
    .clk(clk),
    .rst(rst),
    .rx(uart_rx_pin),
    .data_out(rx_data),
    .data_valid(rx_valid)
);

pixel_buffer u_pbuf (
    .clk(clk),
    .rst(rst),
    .byte_in(rx_data),       // Connected to uart_rx's data_out
    .byte_valid(rx_valid),   // Connected to uart_rx's data_valid
    // ...
);
```

When `data_valid` pulses HIGH for one cycle:
1. `pixel_buffer` sees `byte_valid == 1`
2. It reads `byte_in` (which holds the received byte)
3. It shifts the byte into its 128-bit accumulator
4. After 16 such pulses (16 bytes), the buffer has a complete AES block

```
  uart_rx           pixel_buffer          aes_ctrl
  ┌──────┐          ┌──────────┐          ┌──────────┐
  │      ├─data_out─┤byte_in   │          │          │
  │      ├─data_    │          │          │          │
  │      │  valid──►│byte_valid│          │          │
  │      │          │          ├─block───►│          │
  │      │          │          │  [127:0] │          │
  │      │          │          ├─block───►│          │
  │      │          │          │  _valid  │          │
  └──────┘          └──────────┘          └──────────┘

  Byte 1:  data_valid pulse → pixel_buffer stores byte 1
  Byte 2:  data_valid pulse → pixel_buffer stores byte 2
  ...
  Byte 16: data_valid pulse → pixel_buffer stores byte 16
                               → block_valid pulse!
                               → aes_ctrl gets 128-bit block
```

### Why a One-Cycle Pulse?

A one-cycle pulse is the standard handshaking mechanism in synchronous digital design:
- It is **unambiguous**: each pulse means exactly one event (one byte received).
- It is **self-clearing**: you don't need a separate "acknowledge" signal to clear it.
- It is **glitch-free**: because it is generated by a flip-flop, it transitions cleanly.

If `data_valid` were held HIGH for longer (say, the entire stop bit period), `pixel_buffer`
might accidentally count the same byte multiple times.

---

## 10. Key Takeaways

1. **`uart_rx` converts serial data to parallel**: It listens on a single wire (`rx`) and
   produces an 8-bit byte (`data_out`) plus a one-cycle pulse (`data_valid`).

2. **The double flip-flop synchronizer** (`rx_sync_0`, `rx_sync_1`) is essential for handling
   the asynchronous RX input. Always synchronize external signals before using them in your logic.

3. **Mid-bit sampling** is the key to reliable UART reception: wait 434 clocks (half a bit)
   after detecting the start bit, then sample every 868 clocks. This puts every sample point
   at the center of each bit — the most stable moment.

4. **The off-by-one pattern** (`clk_cnt == N - 1` to count N cycles) appears everywhere in
   hardware design. Counting from 0 to 867 is 868 cycles, not 867.

5. **The FSM has 4 states**: IDLE (wait for start), START (verify at mid-point), DATA (sample
   8 bits), STOP (output byte). Each state has a clear, single responsibility.

6. **`rx_shift[bit_idx] <= rx_sync_1`** directly places each bit at its correct position
   in the byte. Because UART sends LSB first, bit 0 arrives first and goes into position 0.
   No shifting or reordering is needed.

7. **`data_valid` is a one-clock-cycle pulse**, not a level signal. It fires once per received
   byte, and downstream modules must capture the data during that single cycle.

8. **The start bit verification** (checking `rx_sync_1 == 0` at the mid-point) filters out
   noise glitches that might look like a start bit but are too short to be real.

9. **The entire receive process takes about 8,247 clock cycles** (~82.5 us) per byte. At
   115,200 baud, the module can receive up to ~11,520 bytes per second.

10. **All timing is derived from two numbers**: `CLK_FREQ` and `BAUD_RATE`. Change these
    parameters and the module automatically adapts — no other code changes needed.

---

> **Next**: [Document 06 -- UART Transmitter (uart_tx.v)](06_UART_Transmitter_uart_tx.md) -- Now that you understand how bytes are received, let's see how the FPGA sends bytes back to the PC.
