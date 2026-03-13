# Document 04: UART Protocol Deep Dive

> **Goal**: By the end of this document, you will fully understand the UART serial communication
> protocol — how bits are transmitted over a single wire, what baud rate means, and the exact
> timing of start bits, data bits, and stop bits. This is essential before reading the UART Verilog code.

---

## Table of Contents
1. [What is UART?](#1-what-is-uart)
2. [Why Does This Project Use UART?](#2-why-does-this-project-use-uart)
3. [UART Frame Format — Anatomy of a Byte Transfer](#3-uart-frame-format--anatomy-of-a-byte-transfer)
4. [Baud Rate — How Fast Are Bits Sent?](#4-baud-rate--how-fast-are-bits-sent)
5. [Detailed Timing: Sending the Byte 0xA3](#5-detailed-timing-sending-the-byte-0xa3)
6. [LSB-First Transmission Order](#6-lsb-first-transmission-order)
7. [Synchronization and Mid-Bit Sampling](#7-synchronization-and-mid-bit-sampling)
8. [Metastability — Why We Need a Double Flip-Flop](#8-metastability--why-we-need-a-double-flip-flop)
9. [UART on the Basys 3 Board](#9-uart-on-the-basys-3-board)
10. [Key Takeaways](#10-key-takeaways)

---

## 1. What is UART?

**UART** stands for **Universal Asynchronous Receiver-Transmitter**.

- **Universal**: Works with almost any device
- **Asynchronous**: No shared clock wire between sender and receiver
- **Receiver-Transmitter**: Can both send and receive data

### The Simplest Possible Communication

UART uses just **two wires** (plus ground):
- **TX** (Transmit): Data goes out
- **RX** (Receive): Data comes in

```
  Device A                    Device B
  ┌──────┐                    ┌──────┐
  │      │── TX ────────► RX──│      │
  │      │                    │      │
  │      │◄── RX ──────── TX──│      │
  │      │                    │      │
  │      │── GND ──────── GND─│      │
  └──────┘                    └──────┘
```

**Important**: Device A's TX connects to Device B's RX, and vice versa. They "cross" — one device's output is the other's input.

### Analogy: Two People Talking on Walkie-Talkies

Imagine two people communicating with walkie-talkies:
- They can't see each other (no shared clock)
- They agreed in advance to speak at the same speed (baud rate)
- Before saying a word, they say "starting..." (start bit)
- After saying the word, they say "done" (stop bit)
- Each person has their own channel to speak on (TX) and listen on (RX)

---

## 2. Why Does This Project Use UART?

We need to transfer image data between the PC and the FPGA. UART is used because:

1. **The Basys 3 has a built-in USB-to-UART bridge** — no extra hardware needed
2. **Simple to implement** — only needs a basic state machine in Verilog
3. **Widely supported** — Python's `pyserial` library makes PC-side communication easy
4. **Reliable** — well-established protocol, works over USB cables

**The trade-off**: UART is slow compared to other interfaces (SPI, PCIe, etc.). At 115,200 baud, we can only send ~11,520 bytes per second. For our 16 KB image, that's about 1.4 seconds. But for a demo project, this is perfectly acceptable.

---

## 3. UART Frame Format — Anatomy of a Byte Transfer

To send one byte over UART, we transmit a "frame" of **10 bits**:

```
     ┌─────────────────────── One UART Frame ───────────────────────┐
     │                                                               │
     │  IDLE   START    D0   D1   D2   D3   D4   D5   D6   D7  STOP  IDLE
     │  ‾‾‾‾‾                                                       ‾‾‾‾‾
     │                                                               │
     │   1      0     [  8 data bits, LSB first  ]     1      1     │
     │                                                               │
     └───────────────────────────────────────────────────────────────┘

  Voltage:
  HIGH (1) ‾‾‾‾‾‾‾|         |‾‾‾‾‾‾‾|         |‾‾‾‾‾|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
                    |         |         |         |     |
  LOW  (0)         |_________|         |_________|     |
                   ↑ Start bit        data bits     Stop bit
```

### The 5 Parts of a UART Frame

| Part | Duration | Logic Level | Purpose |
|------|----------|-------------|---------|
| **Idle** | Indefinite | HIGH (1) | Line is quiet — nothing being sent |
| **Start bit** | 1 bit period | LOW (0) | "Hey! A byte is coming!" — alerts the receiver |
| **Data bits** | 8 bit periods | varies | The actual byte, sent LSB (bit 0) first |
| **Stop bit** | 1 bit period | HIGH (1) | "That's the end of this byte" |
| **Idle** | Indefinite | HIGH (1) | Line goes quiet again |

**Total: 1 + 8 + 1 = 10 bit periods per byte**

### Why Start with LOW?

The line idles at HIGH (1). The start bit is LOW (0). This creates a **falling edge** (HIGH → LOW) that the receiver can detect to know "a new byte is starting!"

Without the start bit, the receiver would have no way to know when a byte begins — both devices don't share a clock.

---

## 4. Baud Rate — How Fast Are Bits Sent?

**Baud rate** = number of bits transmitted per second.

Our project uses **115,200 baud**, meaning 115,200 bits per second.

### Calculating the Timing

```
Baud rate = 115,200 bits/sec

Time per bit = 1 / 115,200 = 8.6805 μs (microseconds)

FPGA clock = 100 MHz = 100,000,000 cycles/sec
Clock period = 1 / 100,000,000 = 10 ns (nanoseconds)

Clock cycles per bit = 8.6805 μs / 10 ns = 868.05 ≈ 868 cycles
```

So **each bit lasts 868 clock cycles**. The FPGA counts to 868, then moves to the next bit.

### Why 868 and Not 869?

The calculation gives 868.05..., so we use 868. This introduces a tiny timing error:

```
Actual baud rate = 100,000,000 / 868 = 115,207.37 baud
Error = (115,207.37 - 115,200) / 115,200 = 0.0064%
```

A 0.006% error is negligible. UART can tolerate up to about **3-5% timing error** before bytes get corrupted.

### How Long Does It Take to Send One Byte?

```
10 bits × 868 cycles × 10 ns = 86,800 ns = 86.8 μs per byte
```

### How Long Does It Take to Send the Entire Image?

```
16,384 bytes × 86.8 μs = 1,422,131 μs = 1.42 seconds
```

---

## 5. Detailed Timing: Sending the Byte 0xA3

Let's trace through a complete byte transfer with a concrete example.

**Byte to send: 0xA3 = binary 1010_0011**

Remember: UART sends **LSB first**, so the bits come out in this order:
```
Bit 0 (LSB) = 1
Bit 1       = 1
Bit 2       = 0
Bit 3       = 0
Bit 4       = 0
Bit 5       = 1
Bit 6       = 0
Bit 7 (MSB) = 1
```

### Complete Timing Diagram

```
Time (clock cycles): 0    868   1736  2604  3472  4340  5208  6076  6944  7812  8680
                     |     |     |     |     |     |     |     |     |     |     |
                     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
TX line:
           ‾‾‾‾‾|_____|‾‾‾‾‾|‾‾‾‾‾|_____|_____|_____|‾‾‾‾‾|_____|‾‾‾‾‾|‾‾‾‾‾|‾‾‾‾‾
                 │     │     │     │     │     │     │     │     │     │     │
           IDLE  START  D0=1  D1=1  D2=0  D3=0  D4=0  D5=1  D6=0  D7=1  STOP  IDLE
                       (LSB)                                         (MSB)

  Byte reconstructed at receiver: D7 D6 D5 D4 D3 D2 D1 D0
                                  = 1  0  1  0  0  0  1  1
                                  = 0xA3 ✓
```

### Timing Table

| Phase | Clock Cycles | Duration | TX Level | Description |
|-------|-------------|----------|----------|-------------|
| Idle | - | - | 1 | Line quiet |
| Start | 0-867 | 8.68 μs | 0 | "Attention! Byte coming" |
| D0 | 868-1735 | 8.68 μs | 1 | Bit 0 (LSB) = 1 |
| D1 | 1736-2603 | 8.68 μs | 1 | Bit 1 = 1 |
| D2 | 2604-3471 | 8.68 μs | 0 | Bit 2 = 0 |
| D3 | 3472-4339 | 8.68 μs | 0 | Bit 3 = 0 |
| D4 | 4340-5207 | 8.68 μs | 0 | Bit 4 = 0 |
| D5 | 5208-6075 | 8.68 μs | 1 | Bit 5 = 1 |
| D6 | 6076-6943 | 8.68 μs | 0 | Bit 6 = 0 |
| D7 | 6944-7811 | 8.68 μs | 1 | Bit 7 (MSB) = 1 |
| Stop | 7812-8679 | 8.68 μs | 1 | "End of byte" |
| Idle | 8680+ | - | 1 | Line quiet again |

**Total: 10 × 868 = 8,680 clock cycles = 86.8 μs for one byte**

---

## 6. LSB-First Transmission Order

UART sends the **Least Significant Bit (LSB)** first. This might seem counterintuitive, but it's the standard.

### Why LSB First?

Historical reasons: early UART hardware processed data from the bottom bit up. Also, LSB-first transmission allows the receiver to begin storing bits directly into a shift register, which naturally fills from bit 0 upward.

### Example: How 0xA3 is Sent and Reconstructed

**Sender side:**
```
Byte: 0xA3 = 1010_0011
                        ↑ MSB    ↑ LSB

Transmission order: bit[0], bit[1], bit[2], ..., bit[7]
                    = 1, 1, 0, 0, 0, 1, 0, 1
```

**Receiver side (building up a shift register):**
```
After bit 0 received: rx_shift = xxxxxxx1  (bit[0] = 1)
After bit 1 received: rx_shift = xxxxxx11  (bit[1] = 1)
After bit 2 received: rx_shift = xxxxx011  (bit[2] = 0)
After bit 3 received: rx_shift = xxxx0011  (bit[3] = 0)
After bit 4 received: rx_shift = xxx00011  (bit[4] = 0)
After bit 5 received: rx_shift = xx100011  (bit[5] = 1)
After bit 6 received: rx_shift = x0100011  (bit[6] = 0)
After bit 7 received: rx_shift = 10100011  (bit[7] = 1)
                                = 0xA3 ✓
```

In the Verilog code, this is done with: `rx_shift[bit_idx] <= rx_sync_1;`
This directly places each received bit into the correct position.

---

## 7. Synchronization and Mid-Bit Sampling

### The Problem: No Shared Clock

In UART, the sender and receiver have **independent clocks**. They agreed to run at 115,200 baud, but their clocks might be slightly different. How does the receiver know exactly when to read each bit?

### The Solution: Edge Detection + Mid-Bit Sampling

The receiver uses a simple and elegant strategy:

1. **Detect the falling edge** of the start bit (HIGH → LOW transition)
2. **Wait half a bit period** (868/2 = 434 clock cycles) to reach the **middle** of the start bit
3. **Verify** the line is still LOW (confirming it's a real start bit, not noise)
4. **From that point, sample every 868 clocks** — this lands in the middle of each data bit

```
TX line:  ‾‾‾|____________|‾‾‾‾‾‾‾‾‾‾|______________|‾‾‾‾‾‾‾‾‾‾
               START BIT      D0=1         D1=0

Clock:    ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
          ↑                ↑              ↑              ↑
        Detect         Sample at       Sample at       Sample at
        falling edge   mid-start       mid-D0          mid-D1
                       (434 clk)       (+868 clk)      (+868 clk)

                          │                │               │
                          ▼                ▼               ▼
                      Verify 0=LOW     Read D0=1       Read D1=0
```

### Why Sample at the Middle?

Sampling at bit boundaries is risky — the signal might be transitioning (changing between 0 and 1). The **middle of the bit** is the most stable point, giving maximum tolerance for timing errors.

```
              ┌── Bit period ──┐
              │                 │
TX line:  ────┘                 └────
              ↑                 ↑
           Transition       Transition
           (unstable)       (unstable)
                    ↑
              MID-POINT
           (most stable)
```

### Numerical Example: Receiving Byte 0xA3

```
Event               Clock Count    rx_sync_1    Action
─────               ───────────    ─────────    ──────
Idle                0              1            Waiting...
Start bit detected  100            0            Start bit falling edge!
                                                (enter S_START, count to 434)
Mid-start check     100+434=534    0            Still LOW → valid start bit
                                                (enter S_DATA, count to 868)
Sample D0           534+868=1402   1            rx_shift[0]=1
Sample D1           1402+868=2270  1            rx_shift[1]=1
Sample D2           2270+868=3138  0            rx_shift[2]=0
Sample D3           3138+868=4006  0            rx_shift[3]=0
Sample D4           4006+868=4874  0            rx_shift[4]=0
Sample D5           4874+868=5742  1            rx_shift[5]=1
Sample D6           5742+868=6610  0            rx_shift[6]=0
Sample D7           6610+868=7478  1            rx_shift[7]=1
Stop bit            7478+868=8346  1            Output 0xA3, data_valid=1
```

---

## 8. Metastability — Why We Need a Double Flip-Flop

This is a critical hardware concept that has no equivalent in software programming.

### The Problem

The UART RX signal comes from the outside world (the USB-UART chip). It can change at **any time** — it has no relationship to our 100 MHz FPGA clock.

When a flip-flop's input changes **at the exact same moment** as the clock edge, the flip-flop enters an **undefined state** called **metastability** — its output might be 0, might be 1, or might oscillate before settling. This can cause unpredictable behavior.

```
        What normally happens:             What happens during metastability:

  D ─────┐                                D ─────┐
         │ ┌───┐                                  │ ┌───┐
         └►│FF │──► 0 or 1 (clean)               └►│FF │──► ???  (voltage
  CLK ────►│   │                           CLK ────►│   │      between 0 and 1)
           └───┘                                    └───┘
                                                     ▲
                                               D changes at
                                               exact clock edge!
```

### The Solution: Double Flip-Flop Synchronizer

We pass the external signal through **two flip-flops in series**. The first flip-flop might go metastable, but it will almost certainly resolve to a valid 0 or 1 before the second flip-flop reads it.

```
  External RX ──► [FF1] ──► [FF2] ──► Synchronized signal (safe to use)
       ↑              ↑          ↑
  Asynchronous    Might be    Almost certainly
  (dangerous!)    metastable  stable (99.999...%)
```

In our `uart_rx.v` code:
```verilog
always @(posedge clk) begin
    rx_sync_0 <= rx;          // FF1: might go metastable
    rx_sync_1 <= rx_sync_0;   // FF2: sees a clean signal from FF1
end
```

- `rx` = raw external signal (dangerous)
- `rx_sync_0` = output of first flip-flop (might be metastable, but resolves within one clock cycle)
- `rx_sync_1` = output of second flip-flop (safe to use in our logic)

**We always use `rx_sync_1` in the FSM, never `rx` directly.**

### Probability of Failure

The probability of metastability propagating through both flip-flops is astronomically low — on the order of once every **thousands of years** at 100 MHz. This is why the double flip-flop is considered industry-standard.

---

## 9. UART on the Basys 3 Board

### The Physical Setup

```
┌────────────────┐       USB Cable       ┌─────────────────────────┐
│   Your PC      │◄═════════════════════►│   Basys 3 Board         │
│                │                        │                         │
│  Python script │                        │  ┌─────────┐           │
│  (pyserial)    │                        │  │  FTDI   │           │
│  COM3 (Windows)│                        │  │  FT2232 │           │
│  /dev/ttyUSB0  │                        │  │  (USB ←→│           │
│  (Linux)       │                        │  │   UART) │           │
└────────────────┘                        │  └────┬────┘           │
                                          │       │                 │
                                          │   TX (A18)──► FPGA RX  │
                                          │   RX (B18)◄── FPGA TX  │
                                          │                         │
                                          │  ┌──────────────────┐  │
                                          │  │  Your Verilog    │  │
                                          │  │  Design          │  │
                                          │  │  (uart_rx.v,     │  │
                                          │  │   uart_tx.v)     │  │
                                          │  └──────────────────┘  │
                                          └─────────────────────────┘
```

### UART Configuration Used in This Project

```
┌──────────────────────────────────┐
│   UART Settings                   │
├──────────────────────────────────┤
│ Baud Rate:      115,200          │
│ Data Bits:      8                │
│ Parity:         None             │
│ Stop Bits:      1                │
│ Flow Control:   None             │
│                                  │
│ Shorthand: "115200 8N1"         │
│ (baud-databits-parity-stopbits) │
└──────────────────────────────────┘
```

This is the most common UART configuration — sometimes called "8N1" (8 data bits, No parity, 1 stop bit).

### What the Python Script Does

The `host/uart_host.py` script handles the PC side:
- Opens the serial port (e.g., COM3 on Windows)
- **Encrypt mode**: Reads a 128×128 grayscale image, sends the 16,384 raw bytes to the FPGA
- **Decrypt mode**: Reads 16,384 bytes from the FPGA, saves as a PNG image
- Uses `pyserial` library for serial port access

---

## 10. Key Takeaways

1. **UART** is a simple 2-wire serial protocol: TX (transmit) and RX (receive). No shared clock needed.

2. **One byte = 10 bits on the wire**: 1 start bit (LOW) + 8 data bits (LSB first) + 1 stop bit (HIGH).

3. **Baud rate 115,200** means 115,200 bits per second. At 100 MHz, each bit = **868 clock cycles**.

4. The receiver **detects the start bit's falling edge**, waits **434 cycles to reach mid-bit**, then samples every **868 cycles** for maximum stability.

5. **Metastability** is a real hardware problem when reading asynchronous signals. The **double flip-flop synchronizer** solves it (two flip-flops in series on the RX input).

6. UART is the **communication bottleneck** in our project — the FPGA can encrypt 1000x faster than UART can deliver data.

7. The **Basys 3's FTDI chip** converts USB to UART, so we just need a USB cable and a Python serial library.

---

> **Next**: [Document 05 — UART Receiver (uart_rx.v)](05_UART_Receiver_uart_rx.md) — Now that you understand the protocol, let's see exactly how it's implemented in Verilog hardware.
