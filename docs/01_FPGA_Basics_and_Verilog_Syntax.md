# Document 01: FPGA Basics and Verilog Syntax

> **Goal**: By the end of this document, you will understand what an FPGA is, how it fundamentally
> differs from a microprocessor, and be comfortable reading and writing basic Verilog code.

---

## Table of Contents
1. [What is an FPGA?](#1-what-is-an-fpga)
2. [FPGA vs CPU — The Key Difference](#2-fpga-vs-cpu--the-key-difference)
3. [Inside an FPGA — The Building Blocks](#3-inside-an-fpga--the-building-blocks)
4. [What is Verilog?](#4-what-is-verilog)
5. [Verilog Syntax — Complete Beginner Tutorial](#5-verilog-syntax--complete-beginner-tutorial)
6. [Key Takeaways](#6-key-takeaways)

---

## 1. What is an FPGA?

**FPGA** stands for **Field-Programmable Gate Array**.

Let's break that name down:
- **Field-Programmable**: You can program (configure) it after manufacturing — "in the field" (i.e., at your desk, in a lab, wherever).
- **Gate Array**: It's an array (grid) of logic gates that can be connected in any way you want.

### Analogy: LEGO Bricks

Think of an FPGA like a giant box of LEGO bricks:

```
┌─────────────────────────────────────────────────────┐
│                    FPGA Chip                         │
│                                                     │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ │
│  │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ │
│  │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │CLB│ │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ │
│  ┌───┐ ┌───┐ ┌─────────┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ │
│  │CLB│ │CLB│ │  BRAM   │ │CLB│ │CLB│ │CLB│ │CLB│ │
│  └───┘ └───┘ │ (Memory)│ └───┘ └───┘ └───┘ └───┘ │
│  ┌───┐ ┌───┐ └─────────┘ ┌───┐ ┌───┐ ┌───┐ ┌───┐ │
│  │CLB│ │CLB│ ┌───┐ ┌───┐ │CLB│ │CLB│ │DSP│ │CLB│ │
│  └───┘ └───┘ │CLB│ │CLB│ └───┘ └───┘ └───┘ └───┘ │
│              └───┘ └───┘                           │
│  CLB = Configurable Logic Block                    │
│  BRAM = Block RAM (embedded memory)                │
│  DSP = Digital Signal Processing block             │
└─────────────────────────────────────────────────────┘
```

- Each **CLB** (Configurable Logic Block) is like a small LEGO brick. On its own, it can do simple things (AND, OR, XOR, flip-flop).
- The **wires** between them are like the connectors between LEGO bricks.
- You "program" the FPGA by telling it how to connect these bricks together.

**The result?** You create actual hardware circuits — not software instructions. When you "run" your design, you're not executing code line by line. Instead, electricity flows through the circuit you've created, and everything happens simultaneously (in parallel).

---

## 2. FPGA vs CPU — The Key Difference

This is the most important concept to understand:

| | CPU (e.g., your laptop's Intel/AMD chip) | FPGA |
|---|---|---|
| **What it does** | Executes instructions one by one (or a few at a time) | Creates actual hardware circuits |
| **Analogy** | A chef following a recipe step by step | An entire kitchen with many specialized stations working simultaneously |
| **Speed** | Fast clock (3-5 GHz), but sequential | Slower clock (100 MHz typical), but massively parallel |
| **Flexibility** | Run any program by changing software | Change hardware by reprogramming |
| **Programming** | C, Python, Java (software) | Verilog, VHDL (hardware description) |

### Numerical Example: Adding 100 Numbers

**CPU approach** (sequential):
```
Step 1: Load number[0]
Step 2: Add number[1]
Step 3: Add number[2]
...
Step 100: Add number[99]
→ Takes ~100 clock cycles
```

**FPGA approach** (parallel — simplified):
```
Clock 1: Add pairs → (0+1), (2+3), (4+5), ... (98+99)  → 50 results
Clock 2: Add pairs → (result0+result1), ...              → 25 results
Clock 3: Add pairs →                                     → 13 results
Clock 4: Add pairs →                                     → 7 results
Clock 5: Add pairs →                                     → 4 results
Clock 6: Add pairs →                                     → 2 results
Clock 7: Final add →                                     → 1 result
→ Takes ~7 clock cycles (log2 of 100)
```

Even though the FPGA's clock is 30x slower than a CPU, it finishes faster because it does many operations **at the same time**.

### Why FPGA for AES Encryption?

AES encryption involves a lot of operations that can happen in parallel:
- 16 S-box lookups can happen simultaneously
- XOR operations on multiple bytes at once
- Multiple rounds can be pipelined

This makes FPGAs excellent for cryptographic operations — they can encrypt data much faster than a CPU running AES in software.

---

## 3. Inside an FPGA — The Building Blocks

The Basys 3 board uses a Xilinx Artix-7 (XC7A35T) FPGA. Here's what's inside:

### 3.1 Look-Up Tables (LUTs)

A LUT is the most basic building block. It's essentially a small truth table stored in memory.

**Example: A 2-input LUT implementing AND gate**

```
Inputs → LUT → Output
A  B        Y
0  0   →    0
0  1   →    0
1  0   →    0
1  1   →    1
```

The LUT stores these 4 output values in memory. When you apply inputs, it looks up the answer. The Artix-7 has **6-input LUTs** — each can implement ANY function of 6 inputs (that's 2^6 = 64 possible input combinations).

The XC7A35T has **20,800 LUTs**.

### 3.2 Flip-Flops (FFs)

A flip-flop stores exactly **1 bit** of data. It captures the input value on the rising edge of the clock signal and holds it until the next rising edge.

```
        ┌─────┐
  D ───►│     │
        │ FF  ├──► Q (stored value)
  CLK ─►│     │
        └─────┘

Clock:  _____|‾‾‾‾‾|_____|‾‾‾‾‾|_____|‾‾‾‾‾|_____
D:      =====< 1 >========< 0 >==========< 1 >====
Q:      _____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_________________
              ↑                   ↑            ↑
         Q captures D=1     Q captures D=0  Q captures D=1
```

The XC7A35T has **41,600 flip-flops**.

### 3.3 Block RAM (BRAM)

Block RAM is embedded memory inside the FPGA. Instead of building memory from flip-flops (expensive!), FPGAs have dedicated memory blocks.

The XC7A35T has **50 BRAM blocks**, each 36 Kbit (= 4.5 KB). In our project, we use BRAM to store the encrypted image (1024 blocks × 128 bits = 16 KB, needing ~4 BRAM blocks).

### 3.4 Clock Management

FPGAs have special **clock management tiles (CMTs)** that can multiply, divide, and phase-shift clock signals. Our Basys 3 provides a 100 MHz clock, which we use directly.

### 3.5 I/O Pins

The FPGA has physical pins that connect to the outside world — buttons, switches, LEDs, and the UART USB port on the Basys 3 board.

---

## 4. What is Verilog?

Verilog is a **Hardware Description Language (HDL)**. It's not a programming language in the traditional sense — it doesn't give instructions to a processor. Instead, it **describes hardware circuits**.

### Analogy: Blueprint vs Recipe

- **C/Python** = A recipe: "First do this, then do that" (sequential instructions)
- **Verilog** = A blueprint: "There is a wall here, a door there, a window over there" (describing structure)

When you write Verilog, you're describing:
1. What **wires** exist
2. What **registers** (memory elements) exist
3. How they're **connected**
4. What **logic** determines their values

The Vivado tool then takes your Verilog description and figures out how to configure the FPGA's LUTs, flip-flops, and wiring to create that circuit.

---

## 5. Verilog Syntax — Complete Beginner Tutorial

### 5.1 Modules — The Basic Building Block

Everything in Verilog is a **module**. A module is like a chip — it has inputs, outputs, and internal logic.

```verilog
module my_and_gate (
    input  wire a,      // Input pin 'a'
    input  wire b,      // Input pin 'b'
    output wire y       // Output pin 'y'
);
    assign y = a & b;   // y is always a AND b
endmodule
```

**Anatomy:**
```
module <name> (          ← Module declaration and name
    <port list>          ← Inputs and outputs
);
    <internal logic>     ← What the module does
endmodule                ← End of module
```

**Key rules:**
- Every design starts and ends with `module` / `endmodule`
- Port names are case-sensitive (`Reset` ≠ `reset`)
- Statements end with a semicolon `;`
- Comments use `//` for single line, `/* */` for multi-line

### 5.2 Data Types: `wire` vs `reg`

These are the two most important types in Verilog:

#### `wire` — A physical connection

A wire is just that — a wire. It has no memory. Its value is determined by whatever drives it.

```verilog
wire a;          // Single wire (1 bit)
wire [7:0] data; // 8 wires bundled together (a "bus"), bits 7 down to 0
wire [3:0] nibble; // 4-bit bus
```

```
  [7] [6] [5] [4] [3] [2] [1] [0]    ← Bit positions
   │   │   │   │   │   │   │   │
   └───┴───┴───┴───┴───┴───┴───┘
          wire [7:0] data              ← 8-bit bus
```

#### `reg` — A storage element

A `reg` holds a value until it's explicitly changed. **Important**: `reg` doesn't always become a flip-flop in hardware! The name is misleading.

```verilog
reg        flag;           // 1-bit register
reg [7:0]  counter;        // 8-bit register (values 0-255)
reg [127:0] aes_block;     // 128-bit register (used for AES data)
```

**When does `reg` become real hardware?**
- If assigned in an `always @(posedge clk)` block → becomes a **flip-flop** (real memory)
- If assigned in an `always @(*)` block → becomes **combinational logic** (no memory, just wires and gates)

### 5.3 Number Formats

Verilog has a specific way to write numbers:

```
Format: <size>'<base><value>

Size  = number of bits
Base  = b (binary), h (hex), d (decimal), o (octal)
Value = the number
```

**Examples:**
```verilog
8'hFF         // 8-bit hex FF = binary 11111111 = decimal 255
8'b1010_0011  // 8-bit binary (underscores for readability) = 0xA3 = 163
4'd10         // 4-bit decimal 10 = binary 1010
128'h2b7e1516_28aed2a6_abf71588_09cf4f3c  // 128-bit hex (our AES key!)
32'd0         // 32-bit zero
1'b1          // Single bit, value 1
```

**In our project**, you'll see numbers like:
```verilog
128'h2b7e151628aed2a6abf7158809cf4f3c   // The AES-128 encryption key
10'd1023                                  // 10-bit value 1023 (BRAM address)
8'h63                                     // S-box entry: input 0x00 → output 0x63
```

### 5.4 The `assign` Statement — Continuous Assignment

`assign` creates a permanent wire connection. The output updates **instantly** whenever the input changes (like real wires — no delay).

```verilog
wire [7:0] a, b, sum;
assign sum = a + b;   // sum is ALWAYS a+b, continuously
```

**Analogy**: Think of `assign` as gluing two LEGO pieces together permanently. Whenever `a` or `b` changes, `sum` changes immediately.

**Common operators used with assign:**

```verilog
assign y = a & b;     // AND  (bitwise)
assign y = a | b;     // OR   (bitwise)
assign y = a ^ b;     // XOR  (bitwise) — very important for AES!
assign y = ~a;        // NOT  (bitwise)
assign y = a + b;     // Addition
assign y = a - b;     // Subtraction
assign y = a == b;    // Equality (result is 1 or 0)
assign y = a > b;     // Greater than
assign y = {a, b};    // Concatenation — join a and b side by side
assign y = a[3:0];    // Bit selection — pick bits 3 down to 0
```

**Numerical XOR example (crucial for AES):**
```
  a = 8'b1010_0011 (0xA3)
  b = 8'b1111_0000 (0xF0)
  ────────────────────────
  a ^ b = 8'b0101_0011 (0x53)

  Rule: XOR = 1 when bits are DIFFERENT, 0 when SAME
    1⊕1=0, 0⊕1=1, 1⊕1=0, 0⊕0=0, 0⊕0=0, 0⊕0=0, 1⊕0=1, 1⊕0=1
```

### 5.5 The `always` Block — Where Logic Lives

The `always` block is where you describe sequential and combinational behavior.

#### Combinational Logic: `always @(*)`

This triggers whenever **any** input changes (like `assign`, but allows if-else/case):

```verilog
reg [1:0] result;

always @(*) begin
    if (sel == 1'b0)
        result = a;      // Use '=' for combinational
    else
        result = b;
end
```

**This creates a multiplexer (MUX):**
```
        ┌──────┐
  a ───►│      │
        │ MUX  ├──► result
  b ───►│      │
        └──┬───┘
           │
          sel
  sel=0 → result=a
  sel=1 → result=b
```

#### Sequential Logic: `always @(posedge clk)`

This triggers only on the **rising edge** of the clock. This is what creates flip-flops:

```verilog
reg [7:0] counter;

always @(posedge clk) begin
    if (reset)
        counter <= 8'd0;       // Use '<=' for sequential
    else
        counter <= counter + 1; // Increment every clock cycle
end
```

```
Clock:    __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
Counter:  == 0 == 1 == 2 == 3 == 4 == 5 == 6 ==
               ↑    ↑    ↑    ↑    ↑    ↑
          (increments on every rising edge)
```

### 5.6 Blocking (`=`) vs Non-Blocking (`<=`) Assignment

This is one of the most confusing topics for beginners. Here's the rule:

| Context | Use | Symbol | Think of it as |
|---------|-----|--------|----------------|
| `always @(*)` (combinational) | Blocking | `=` | "happens immediately" |
| `always @(posedge clk)` (sequential) | Non-blocking | `<=` | "scheduled for next clock edge" |

**Why does this matter?** In sequential blocks, non-blocking ensures all flip-flops update **simultaneously** at the clock edge, not one after another.

**Example — WHY non-blocking matters:**

```verilog
// CORRECT — swap works!
always @(posedge clk) begin
    a <= b;   // At next clock edge: a gets current b
    b <= a;   // At next clock edge: b gets current a
end
// Both read the OLD values, then update simultaneously → swap works

// WRONG — swap fails!
always @(posedge clk) begin
    a = b;    // a immediately gets b
    b = a;    // b gets the NEW a (which is already b) → both become b!
end
```

**Golden Rule**: Always use `<=` inside `always @(posedge clk)`. Always use `=` inside `always @(*)`.

### 5.7 `if-else` and `case` Statements

These work much like other languages but can only be used inside `always` blocks:

```verilog
// if-else
always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        count <= 0;
    end
    else if (start) begin
        state <= RUNNING;
    end
    else begin
        count <= count + 1;
    end
end

// case (like switch in C)
always @(posedge clk) begin
    case (state)
        2'b00: next_state <= IDLE;
        2'b01: next_state <= RUNNING;
        2'b10: next_state <= DONE;
        default: next_state <= IDLE;  // Always include default!
    endcase
end
```

**Note the `begin` / `end` blocks** — these are like `{` `}` in C. You need them when there are multiple statements inside an if/else/case branch.

### 5.8 Parameters and Local Parameters

Parameters are like constants. They make your code flexible and readable:

```verilog
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,  // 100 MHz
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rx,
    output reg [7:0] data
);
    // Calculate at compile time:
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // = 868

    // Use it in logic:
    if (counter == CLKS_PER_BIT - 1) ...
endmodule
```

- `parameter`: Can be overridden when instantiating the module
- `localparam`: Cannot be overridden — internal constant only

**Numerical example from our project:**
```
CLK_FREQ  = 100,000,000 Hz (100 MHz clock)
BAUD_RATE = 115,200 bits per second
CLKS_PER_BIT = 100,000,000 / 115,200 = 868.05... ≈ 868

This means: to transmit one bit, we wait 868 clock cycles
At 100 MHz, each cycle = 10 ns
So 868 × 10 ns = 8,680 ns = 8.68 μs per bit
1 / 8.68 μs ≈ 115,207 baud (close enough to 115,200!)
```

### 5.9 Module Instantiation — Connecting Modules Together

This is how you build larger designs from smaller ones. It's like plugging a chip into a circuit board:

```verilog
module top (
    input wire clk,
    input wire reset,
    input wire rx_pin
);
    // Internal wires to connect modules
    wire [7:0] received_byte;
    wire       byte_valid;

    // Instantiate a UART receiver
    uart_rx #(
        .CLK_FREQ(100_000_000),     // Override parameter
        .BAUD_RATE(115200)
    ) u_uart_rx (                    // Instance name
        .clk(clk),                   // Connect port 'clk' to our 'clk'
        .reset(reset),               // Connect port 'reset' to our 'reset'
        .rx(rx_pin),                 // Connect port 'rx' to our 'rx_pin'
        .data(received_byte),        // Connect port 'data' to our wire
        .data_valid(byte_valid)      // Connect port 'data_valid' to our wire
    );
endmodule
```

**Syntax:**
```
<module_name> #(
    .PARAM1(value1),
    .PARAM2(value2)
) <instance_name> (
    .port_name1(wire_or_reg_name1),
    .port_name2(wire_or_reg_name2)
);
```

The `.port_name(connection)` syntax is called **named port connection**. The name before the dot is the port name defined in the module's port list; the name in parentheses is the signal in the current module you're connecting to.

### 5.10 Finite State Machines (FSMs) — The Heart of Digital Design

FSMs are the cornerstone of this project. Almost every module uses one. An FSM has:
- **States**: Named conditions (like IDLE, RUNNING, DONE)
- **Transitions**: Rules for moving between states
- **Outputs**: What happens in each state

```
         ┌──────────┐  start=1   ┌──────────┐
    ────►│  IDLE    ├───────────►│ RUNNING  │
         │ (LED off)│            │ (LED on) │
         └──────────┘            └────┬─────┘
              ▲                       │ done=1
              │    ┌──────────┐       │
              └────┤  DONE    │◄──────┘
                   │ (LED blink)│
                   └──────────┘
```

**Verilog implementation pattern:**

```verilog
// Step 1: Define states using localparam
localparam S_IDLE    = 2'b00;
localparam S_RUNNING = 2'b01;
localparam S_DONE    = 2'b10;

// Step 2: State register
reg [1:0] state;

// Step 3: State transitions
always @(posedge clk) begin
    if (reset) begin
        state <= S_IDLE;
    end
    else begin
        case (state)
            S_IDLE: begin
                if (start)
                    state <= S_RUNNING;
            end

            S_RUNNING: begin
                if (done)
                    state <= S_DONE;
            end

            S_DONE: begin
                state <= S_IDLE;  // Go back to idle
            end

            default: state <= S_IDLE;
        endcase
    end
end

// Step 4: Outputs based on state
assign led = (state == S_RUNNING);  // LED on only when running
```

**This pattern appears in EVERY module of our project:**
- `uart_rx.v`: 4 states (IDLE, START, DATA, STOP)
- `uart_tx.v`: 4 states (IDLE, START, DATA, STOP)
- `aes_ctrl.v`: 8 states (IDLE, KEY_INIT, WAIT_KEY_LOW, ...)
- `top.v`: 7 states (SYS_IDLE, SYS_ENCRYPT_WAIT, ...)
- `aes_core.v`: 3 states (CTRL_IDLE, CTRL_INIT, CTRL_NEXT)

### 5.11 Concatenation and Bit Manipulation

Verilog makes it easy to manipulate individual bits and combine signals:

```verilog
wire [7:0] a = 8'hA3;    // 1010_0011
wire [7:0] b = 8'hF0;    // 1111_0000

// Concatenation: join signals
wire [15:0] combined = {a, b};  // 16'hA3F0 = 1010_0011_1111_0000

// Bit selection
wire [3:0] upper = a[7:4];  // 4'hA = 1010
wire [3:0] lower = a[3:0];  // 4'h3 = 0011

// Replication
wire [31:0] replicated = {4{a}};  // Repeat a four times: A3A3A3A3

// Shift left by 8 and insert byte (used in pixel_buffer.v!)
reg [127:0] block;
always @(posedge clk)
    block <= {block[119:0], new_byte};  // Shift left 8 bits, insert new byte at LSB
```

**Numerical example (from pixel_buffer):**
```
Start:   block = 128'h00000000_00000000_00000000_00000000
Byte 1 (0xAB): block = {block[119:0], 8'hAB}
         block = 128'h00000000_00000000_00000000_000000AB
Byte 2 (0xCD): block = {block[119:0], 8'hCD}
         block = 128'h00000000_00000000_00000000_0000ABCD
...
Byte 16 (0x10):
         block = 128'hABCD.... (all 16 bytes packed)
```

### 5.12 Memory Declaration

You can create arrays of registers to represent memory:

```verilog
// 1024 entries, each 128 bits wide
reg [127:0] mem [0:1023];

// Read:
data_out = mem[addr];

// Write:
mem[addr] = data_in;
```

This is exactly what `bram_ctrl.v` does. Vivado sees this pattern and automatically uses the FPGA's dedicated BRAM blocks instead of flip-flops (which would be too expensive).

### 5.13 Ternary Operator

The `? :` operator works like in C — useful for simple multiplexing:

```verilog
assign output = (condition) ? value_if_true : value_if_false;

// Example from our project — choose encrypt or decrypt result:
assign result = (encdec) ? decrypt_result : encrypt_result;
```

### 5.14 Reset Patterns

Most modules use synchronous active-high reset:

```verilog
always @(posedge clk) begin
    if (reset) begin
        // Initialize everything
        state   <= S_IDLE;
        counter <= 0;
        data    <= 0;
    end
    else begin
        // Normal operation
        ...
    end
end
```

Some modules (the Secworks AES modules) use **asynchronous active-low reset**:

```verilog
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin        // reset_n=0 means "reset is active"
        // Initialize
    end
    else begin
        // Normal operation
    end
end
```

- **Synchronous reset**: Reset only happens at the clock edge (cleaner, recommended)
- **Asynchronous reset**: Reset happens immediately, even without a clock (used in some IP cores)
- **Active-high**: `reset = 1` means "reset now" (our custom modules)
- **Active-low**: `reset_n = 0` means "reset now" (Secworks modules, the `_n` suffix means "active-low")

---

## 6. Key Takeaways

1. **FPGA ≠ CPU**: An FPGA creates actual hardware circuits. Everything you describe runs in parallel, simultaneously.

2. **Verilog describes structure, not steps**: You're drawing a circuit blueprint, not writing a recipe.

3. **Two types of logic**:
   - **Combinational** (wire/assign/always@(*)): Output changes instantly with input. No memory.
   - **Sequential** (always@(posedge clk)): Output changes only at clock edge. Has memory (flip-flops).

4. **The golden rules**:
   - Use `<=` in sequential blocks, `=` in combinational blocks
   - Always have a `default` in `case` statements
   - Always have a reset condition in sequential blocks

5. **FSMs are everywhere**: Almost every module in this project is an FSM — learn the pattern well.

6. **Bit manipulation is fundamental**: Concatenation `{}`, bit selection `[7:0]`, and XOR `^` are used constantly in AES.

---

> **Next**: [Document 02 — Basys 3 Board and Vivado Setup](02_Basys3_Board_and_Vivado_Setup.md) — Learn about the physical board and how to set up the project in Vivado.
