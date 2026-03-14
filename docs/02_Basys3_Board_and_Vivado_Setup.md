# Document 02: Basys 3 Board and Vivado Setup

> **Goal**: By the end of this document, you will understand the Basys 3 FPGA board physically,
> know what each component does, understand the constraint file, and be able to create a
> complete Vivado project from scratch and program the board.

---

## Table of Contents
1. [The Basys 3 Board — Physical Overview](#1-the-basys-3-board--physical-overview)
2. [The FPGA Chip: Artix-7 XC7A35T](#2-the-fpga-chip-artix-7-xc7a35t)
3. [Board Components Used in This Project](#3-board-components-used-in-this-project)
4. [Understanding the Constraints File (basys3.xdc)](#4-understanding-the-constraints-file-basys3xdc)
5. [Vivado Design Suite — What It Is and What It Does](#5-vivado-design-suite--what-it-is-and-what-it-does)
6. [Step-by-Step: Creating the Project in Vivado](#6-step-by-step-creating-the-project-in-vivado)
7. [Step-by-Step: Running Synthesis, Implementation, and Generating Bitstream](#7-step-by-step-running-synthesis-implementation-and-generating-bitstream)
8. [Step-by-Step: Programming the Board](#8-step-by-step-programming-the-board)
9. [Common Vivado Errors and How to Fix Them](#9-common-vivado-errors-and-how-to-fix-them)
10. [Key Takeaways](#10-key-takeaways)

---

## 1. The Basys 3 Board — Physical Overview

The **Digilent Basys 3** is a beginner-friendly FPGA development board. Here's a map of the board:

```
┌─────────────────────────────────────────────────────────────────┐
│                        BASYS 3 BOARD                            │
│                                                                 │
│  ┌─────────┐                                    ┌──────────┐   │
│  │ USB     │  (Micro-USB port)                  │ 7-Segment│   │
│  │ Port    │  - Powers the board                │ Display  │   │
│  │         │  - Programs the FPGA               │ (4 digit)│   │
│  │         │  - UART communication to PC        └──────────┘   │
│  └─────────┘                                                    │
│                                                                 │
│  ┌──────────────────────────────────────┐                      │
│  │          FPGA CHIP                    │                      │
│  │    Xilinx Artix-7 XC7A35T           │                      │
│  │                                       │                      │
│  │    33,280 Logic Cells                │                      │
│  │    20,800 LUTs                       │                      │
│  │    41,600 Flip-Flops                 │                      │
│  │    50 Block RAMs (1,800 Kb)          │                      │
│  │    90 DSP Slices                     │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
│  ┌───────────────────────────────────────────┐                 │
│  │  16 Switches (SW0-SW15)                    │                 │
│  │  [0][1][2][3][4][5][6][7][8]...[15]       │                 │
│  └───────────────────────────────────────────┘                 │
│                                                                 │
│  ┌────────────────────────┐     ┌──────────────────────┐       │
│  │  16 LEDs (LD0-LD15)    │     │  5 Buttons           │       │
│  │  (●)(●)(●)(●)...(●)   │     │    [btnU]            │       │
│  └────────────────────────┘     │ [btnL][btnC][btnR]   │       │
│                                  │    [btnD]            │       │
│  100 MHz                        └──────────────────────┘       │
│  Oscillator (Crystal)                                           │
│                                                                 │
│  ┌──────────┐  ┌──────────┐                                    │
│  │ Pmod JA  │  │ Pmod JB  │  (expansion connectors)           │
│  └──────────┘  └──────────┘                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. The FPGA Chip: Artix-7 XC7A35T

The full part number is **XC7A35T-1CPG236C**. Let's decode it:

| Part | Meaning |
|------|---------|
| XC7 | Xilinx 7-series |
| A | Artix family (the "budget" 7-series — good balance of speed and cost) |
| 35T | ~33,280 logic cells |
| -1 | Speed grade 1 (slowest of 3 grades; higher = faster but more expensive) |
| CPG236 | Package type: 236-pin BGA (Ball Grid Array) |
| C | Commercial temperature range (0°C to 85°C) |

**Resources available on this chip:**

| Resource | Count | What It's Used For |
|----------|-------|-------------------|
| LUTs | 20,800 | Logic: AND, OR, XOR, muxes |
| Flip-Flops | 41,600 | Storage: counters, state registers, data registers |
| Block RAM | 50 blocks (1,800 Kb total) | Memory: our encrypted image storage |
| DSP Slices | 90 | Math: multiplication (not used in our AES project) |
| I/O Pins | Up to 106 | Interface: buttons, LEDs, UART |
| Clock Management | 5 CMTs | Clock generation (we just use the direct 100 MHz) |

**Is this chip big enough for our project?** Absolutely! AES-128 typically uses only about 2,000-3,000 LUTs. We need ~4 BRAM blocks for 16 KB of image storage. This chip has plenty of room.

---

## 3. Board Components Used in This Project

### 3.1 The 100 MHz Clock Oscillator

A quartz crystal on the board generates a precise 100 MHz clock signal. This means:
- 100,000,000 ticks per second
- Each tick = 10 nanoseconds (10 ns)
- This clock signal is connected to FPGA pin **W5**

**Every sequential circuit in our design is synchronized to this clock.** When we say `always @(posedge clk)`, we mean "do this 100 million times per second."

### 3.2 The USB-UART Bridge

The Basys 3 has an **FTDI USB-UART chip** built in. This chip converts USB data from your PC into UART serial data that the FPGA can understand, and vice versa.

```
    ┌──────┐    USB Cable    ┌────────┐   UART (2 wires)   ┌──────┐
    │  PC  │ ◄─────────────► │ FTDI   │ ◄────────────────► │ FPGA │
    │      │                 │ Chip   │   TX (pin A18)     │      │
    │      │                 │        │   RX (pin B18)     │      │
    └──────┘                 └────────┘                     └──────┘
```

- **Pin A18** (FPGA → PC): FPGA transmits data to PC
- **Pin B18** (PC → FPGA): PC transmits data to FPGA
- **Baud rate**: 115,200 bits per second (configured in our Verilog code)

When you plug in the USB cable and open a serial terminal (or our Python script), you're talking directly to the FPGA through these two pins.

### 3.3 Switches

The Basys 3 has 16 slide switches. We use only **SW0**:

| Switch | FPGA Pin | Function in Our Project |
|--------|----------|------------------------|
| SW0 | V17 | Mode select: DOWN (0) = Encrypt, UP (1) = Decrypt |

**How it works**: When you slide the switch to one position, pin V17 reads logic `1` (3.3V). In the other position, it reads logic `0` (0V). Our `top.v` module reads this as `mode_sw`.

### 3.4 Push Buttons

The Basys 3 has 5 push buttons. We use 2 of them:

| Button | FPGA Pin | Function in Our Project |
|--------|----------|------------------------|
| btnC (center) | U18 | System Reset — returns everything to initial state |
| btnR (right) | T17 | Start readback — triggers decryption and UART transmission |

**How they work**: Basys 3 buttons are **active-high** — pressing the button sends logic `1` to the FPGA pin. Releasing sends `0`.

```
  Not pressed:  FPGA pin reads 0
  Pressed:      FPGA pin reads 1

  Timeline:
  Button:  ________|‾‾‾‾‾‾‾‾‾|________
                   ↑ pressed  ↑ released
  FPGA pin: 0 0 0 1 1 1 1 1 1 0 0 0 0
```

### 3.5 LEDs

We use the first 4 LEDs to show system status:

| LED | FPGA Pin | Meaning |
|-----|----------|---------|
| LED0 | U16 | ON = Currently encrypting |
| LED1 | E19 | ON = Currently decrypting |
| LED2 | U19 | ON = Operation complete |
| LED3 | V19 | ON = Error occurred |

**How they work**: When the FPGA drives a pin to `1` (3.3V), the LED turns on. When it drives `0`, the LED turns off.

---

## 4. Understanding the Constraints File (basys3.xdc)

The constraints file is the bridge between your Verilog code and the physical FPGA board. Without it, Vivado doesn't know which physical pin to connect to which signal in your design.

**Analogy**: Your Verilog code is like a house blueprint that says "there's a front door here." The constraints file says "the front door is at 123 Main Street" — it gives the physical location.

Let's go through our `constraints/basys3.xdc` line by line:

### Clock Constraint

```tcl
set_property PACKAGE_PIN W5  [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]
```

**Line 1**: `set_property PACKAGE_PIN W5 [get_ports clk]`
- "Connect the Verilog signal named `clk` to physical pin W5 on the FPGA package"
- Pin W5 is where the 100 MHz oscillator is wired on the Basys 3 board

**Line 2**: `set_property IOSTANDARD LVCMOS33 [get_ports clk]`
- "This pin uses LVCMOS 3.3V logic levels"
- LVCMOS33 means: Logic 0 = 0V, Logic 1 = 3.3V
- The Basys 3 operates at 3.3V, so all pins use this standard

**Line 3**: `create_clock -period 10.000 -name sys_clk [get_ports clk]`
- "Tell Vivado that this is a clock signal with a period of 10 nanoseconds"
- Period = 10 ns → Frequency = 1 / 10ns = 100 MHz
- Vivado uses this information to check if your design can run fast enough (timing analysis)

### UART Pins

```tcl
set_property PACKAGE_PIN A18 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]

set_property PACKAGE_PIN B18 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]
```

- `uart_tx_pin` (Verilog signal) → Pin A18 (FPGA → PC direction)
- `uart_rx_pin` (Verilog signal) → Pin B18 (PC → FPGA direction)
- Both use 3.3V LVCMOS standard

### Switch

```tcl
set_property PACKAGE_PIN V17 [get_ports mode_sw]
set_property IOSTANDARD LVCMOS33 [get_ports mode_sw]
```

- `mode_sw` (Verilog signal) → Pin V17 (switch SW0 on the board)

### Buttons

```tcl
set_property PACKAGE_PIN U18 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

set_property PACKAGE_PIN T17 [get_ports btn_start]
set_property IOSTANDARD LVCMOS33 [get_ports btn_start]
```

- `rst_btn` → Pin U18 (center button = reset)
- `btn_start` → Pin T17 (right button = start decrypt readback)

### LEDs

```tcl
set_property PACKAGE_PIN U16 [get_ports {status_led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[0]}]

set_property PACKAGE_PIN E19 [get_ports {status_led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[1]}]

set_property PACKAGE_PIN U19 [get_ports {status_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[2]}]

set_property PACKAGE_PIN V19 [get_ports {status_led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[3]}]
```

Note the `{status_led[0]}` syntax — curly braces are needed in XDC/TCL when the signal name contains square brackets (because TCL treats `[]` as command substitution).

### Configuration Settings

```tcl
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
```

- **CFGBVS VCCO**: Configuration bank voltage source = VCCO (the I/O voltage)
- **CONFIG_VOLTAGE 3.3**: Operating voltage is 3.3V
- **BITSTREAM.GENERAL.COMPRESS TRUE**: Compress the bitstream file to make it smaller and faster to program

These are boilerplate settings required by the Artix-7 for proper operation. You'll see them in almost every Basys 3 project.

### Pin-to-Signal Summary Table

```
┌─────────────────────────────────────────────────────┐
│              Pin Assignment Map                      │
├─────────────┬──────┬────────────────────────────────┤
│ Verilog Name│ Pin  │ Physical Component             │
├─────────────┼──────┼────────────────────────────────┤
│ clk         │ W5   │ 100 MHz Crystal Oscillator     │
│ uart_tx_pin │ A18  │ USB-UART TX (FPGA → PC)       │
│ uart_rx_pin │ B18  │ USB-UART RX (PC → FPGA)       │
│ mode_sw     │ V17  │ Switch SW0                     │
│ rst_btn     │ U18  │ Center Push Button (btnC)      │
│ btn_start   │ T17  │ Right Push Button (btnR)       │
│ status_led[0]│ U16 │ LED0 (encrypting indicator)    │
│ status_led[1]│ E19 │ LED1 (decrypting indicator)    │
│ status_led[2]│ U19 │ LED2 (done indicator)          │
│ status_led[3]│ V19 │ LED3 (error indicator)         │
└─────────────┴──────┴────────────────────────────────┘
```

---

## 5. Vivado Design Suite — What It Is and What It Does

**Vivado** is Xilinx's (now AMD's) software for FPGA development. Think of it as the "IDE" for hardware design — like Visual Studio is for software, Vivado is for FPGAs.

### What Vivado Does (The FPGA Design Flow)

```
┌──────────────────────────────────────────────────────────────────────┐
│                    FPGA Design Flow in Vivado                        │
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────┐            │
│  │ 1. WRITE    │    │ 2. SIMULATE │    │ 3. SYNTHESIZE│            │
│  │   Verilog   │───►│   Test your │───►│   Convert to │            │
│  │   Code      │    │   design    │    │   logic gates│            │
│  └─────────────┘    └─────────────┘    └──────┬───────┘            │
│                                                │                     │
│  ┌─────────────┐    ┌─────────────┐    ┌──────▼───────┐            │
│  │ 6. PROGRAM  │    │ 5. GENERATE │    │ 4. IMPLEMENT │            │
│  │   Upload to │◄───│   BITSTREAM │◄───│   Place &    │            │
│  │   FPGA board│    │   (.bit file)│   │   Route      │            │
│  └─────────────┘    └─────────────┘    └──────────────┘            │
└──────────────────────────────────────────────────────────────────────┘
```

Let's understand each step:

### Step 1: Write Verilog Code
You write `.v` files that describe your hardware. (Already done in our project!)

### Step 2: Simulate (Optional but Highly Recommended)
Run your design in a virtual environment to verify it works correctly before touching the real FPGA. Vivado has a built-in simulator.

### Step 3: Synthesize
**Synthesis** converts your Verilog code into a **netlist** — a network of logic gates (LUTs, flip-flops, etc.).

**Analogy**: If your Verilog is a house blueprint drawn on paper, synthesis is like converting it into a list of specific building materials (2x4 lumber, bricks, nails) and how they connect.

```
Verilog:  assign y = a & b;
                ↓ Synthesis
Netlist:  LUT2 #(.INIT(4'b1000)) lut_instance (.I0(a), .I1(b), .O(y));
```

### Step 4: Implementation (Place & Route)
This takes the synthesized netlist and maps it onto the **actual FPGA resources**:
- **Placement**: Decide which specific LUT/FF on the chip each gate goes into
- **Routing**: Decide which physical wires on the chip connect them

**Analogy**: Synthesis told us we need 50 bricks and 200 nails. Implementation decides exactly where each brick goes on the lot and which electric wires connect the rooms.

This step also performs **timing analysis** — it checks whether signals can travel between flip-flops within one clock period (10 ns for our 100 MHz clock). If not, you get a "timing violation" and the design might not work reliably.

### Step 5: Generate Bitstream
The bitstream (`.bit` file) is the final binary file that configures the FPGA. It's a sequence of 1s and 0s that programs every LUT, every flip-flop, every routing switch in the FPGA.

**The Basys 3's XC7A35T bitstream is about 2 MB** (17.5 million configuration bits).

### Step 6: Program the Board
Upload the `.bit` file to the FPGA through the USB cable. The FPGA is configured in milliseconds, and your hardware circuit is live!

**Important**: FPGA configuration is **volatile** — when you power off the board, the design is lost. You need to reprogram it each time (or use the SPI flash for persistent programming, which is an advanced topic).

---

## 6. Step-by-Step: Creating the Project in Vivado

### Prerequisites
- **Vivado Design Suite** installed (WebPACK edition is free and supports the Artix-7)
- **Basys 3** board with USB cable
- **Basys 3 board files** installed (for easy board selection in Vivado)

### Step 6.1: Launch Vivado and Create New Project

1. Open **Vivado** from your Start Menu
2. On the welcome screen, click **Create New Project**
3. Click **Next** on the wizard
4. **Project Name**: `IMAGE_ENCRYPTION_AES_FPGA` (or any name you prefer)
5. **Project Location**: Choose a location on your disk
6. Check **"Create project subdirectory"**
7. Click **Next**

### Step 6.2: Select Project Type

1. Select **RTL Project**
2. Check **"Do not specify sources at this time"** (we'll add them manually)
3. Click **Next**

### Step 6.3: Select the FPGA Part

**Option A — If you have Basys 3 board files installed:**
1. Click the **Boards** tab at the top
2. Search for **Basys 3**
3. Select **Basys 3** from Digilent
4. Click **Next**, then **Finish**

**Option B — Manual part selection:**
1. Stay on the **Parts** tab
2. Set the filters:
   - Family: **Artix-7**
   - Package: **cpg236**
   - Speed: **-1**
3. Find and select: **xc7a35tcpg236-1**
4. Click **Next**, then **Finish**

### Step 6.4: Add Source Files (RTL)

1. In the **Sources** panel (left side), click the **+** button (Add Sources)
2. Select **"Add or create design sources"** → Click **Next**
3. Click **"Add Files"**
4. Navigate to your project's `src/rtl/` folder
5. Select **ALL** `.v` files:
   ```
   aes.v
   aes_core.v
   aes_ctrl.v
   aes_decipher_block.v
   aes_encipher_block.v
   aes_inv_sbox.v
   aes_key_mem.v
   aes_sbox.v
   bram_ctrl.v
   pixel_buffer.v
   top.v
   uart_rx.v
   uart_tx.v
   ```
6. **Important**: Check **"Copy sources into project"** (this copies files into the Vivado project directory, keeping your original files untouched)
7. Click **Finish**

### Step 6.5: Add Constraint File

1. Click the **+** button again
2. Select **"Add or create constraints"** → Click **Next**
3. Click **"Add Files"**
4. Navigate to `constraints/` folder and select **basys3.xdc**
5. Check **"Copy constraints files into project"**
6. Click **Finish**

### Step 6.6: Add Testbench Files (for Simulation)

1. Click the **+** button again
2. Select **"Add or create simulation sources"** → Click **Next**
3. Click **"Add Files"**
4. Navigate to `src/tb/` folder and select all `tb_*.v` files
5. Check **"Copy sources into project"**
6. Click **Finish**

### Step 6.7: Set the Top Module

1. In the **Sources** panel, expand **Design Sources**
2. You should see all your `.v` files listed
3. Vivado usually auto-detects the top module, but verify:
   - Right-click on **`top`** (the `top.v` module)
   - Select **"Set as Top"**
   - It should now show a hierarchy icon (a little chip symbol)

**You should see a hierarchy like this in the Sources panel:**
```
Design Sources
  └── top (top.v)
       ├── u_uart_rx : uart_rx (uart_rx.v)
       ├── u_uart_tx : uart_tx (uart_tx.v)
       ├── u_pixel_buffer : pixel_buffer (pixel_buffer.v)
       ├── u_aes_ctrl : aes_ctrl (aes_ctrl.v)
       │    └── aes_inst : aes_core (aes_core.v)
       │         ├── enc_block : aes_encipher_block
       │         ├── dec_block : aes_decipher_block
       │         │    └── inv_sbox_inst : aes_inv_sbox
       │         ├── keymem : aes_key_mem
       │         └── sbox_inst : aes_sbox
       └── u_bram_ctrl : bram_ctrl (bram_ctrl.v)
```

**Note**: `aes.v` will appear as an un-instantiated module (not part of the hierarchy) — this is normal. It's the Secworks register-mapped wrapper that our project doesn't use directly.

---

## 7. Step-by-Step: Running Synthesis, Implementation, and Generating Bitstream

### Step 7.1: Run Synthesis

1. In the **Flow Navigator** (left panel), under "SYNTHESIS", click **Run Synthesis**
2. A dialog appears — click **OK** (use default settings)
3. Wait for synthesis to complete (~1-3 minutes)
4. When it finishes, a dialog asks what to do next:
   - Select **"Run Implementation"** and click **OK**

**What to check after synthesis:**
- Look at the **Messages** tab at the bottom — any red "ERROR" messages means something is wrong
- Yellow "WARNING" messages are usually okay but should be reviewed
- Click **"Open Synthesized Design"** → **"Schematic"** to see the gate-level circuit (interesting to explore!)

**What might go wrong:**
- **Syntax errors**: Typos in Verilog code → Fix the code and re-run
- **Missing module**: A module is instantiated but its file isn't added → Add the missing `.v` file
- **Port width mismatch**: Connecting an 8-bit wire to a 16-bit port → Fix the widths

### Step 7.2: Run Implementation

1. After synthesis, select **"Run Implementation"** (or find it in Flow Navigator)
2. Click **OK** on the dialog
3. Wait (~2-5 minutes)

**What to check after implementation:**
- **Timing Summary**: In the Flow Navigator, click **"Open Implemented Design"** → **"Timing Summary"**
- Look for **WNS (Worst Negative Slack)**:
  - Positive WNS (e.g., +2.5 ns) = **GOOD** — design meets timing with 2.5 ns to spare
  - Negative WNS (e.g., -0.3 ns) = **BAD** — design is too slow for 100 MHz
- **Utilization Report**: Shows how much of the FPGA you're using

**Expected utilization for our AES project (approximate):**
```
┌─────────────────────────────────────────────┐
│ Resource     │ Used  │ Available │ Util %   │
├──────────────┼───────┼───────────┼──────────┤
│ LUTs         │ ~3000 │ 20,800   │ ~14%     │
│ Flip-Flops   │ ~1500 │ 41,600   │ ~4%      │
│ Block RAM    │ ~4    │ 50       │ ~8%      │
│ I/O Pins     │ 10    │ 106      │ ~9%      │
└──────────────┴───────┴───────────┴──────────┘
```

Our design uses a small fraction of the FPGA — plenty of room!

### Step 7.3: Generate Bitstream

1. After implementation, select **"Generate Bitstream"**
2. Click **OK** on the dialog
3. Wait (~1-2 minutes)
4. When done, you'll have a `.bit` file (usually in `<project>.runs/impl_1/top.bit`)

---

## 8. Step-by-Step: Programming the Board

### Step 8.1: Connect the Board

1. Plug the Basys 3 into your PC via the **micro-USB** cable
2. Make sure the **power switch** on the board is ON
3. Set the **JP1 jumper** to **USB** (to power from USB — it should be there by default)

### Step 8.2: Open Hardware Manager

1. In Vivado, go to Flow Navigator → **"Open Hardware Manager"**
2. Click **"Open Target"** → **"Auto Connect"**
3. Vivado should detect your Basys 3 board and show the FPGA device (xc7a35t)

**If the board is not detected:**
- Make sure the USB cable is firmly connected
- Install the **Digilent USB drivers** (comes with the Basys 3 support package)
- Try a different USB port
- Restart Vivado

### Step 8.3: Program the FPGA

1. Click **"Program Device"** → Select your device (xc7a35t)
2. In the dialog, browse to your bitstream file (`top.bit`)
3. Click **"Program"**
4. The FPGA is configured in about 1 second
5. **Your hardware is now alive!**

### Step 8.4: Verify It's Working

After programming:
- **No buttons pressed, SW0 = 0**: LED0-3 should be off (system idle, encrypt mode)
- **Press btnC (center)**: System resets
- **Run the Python script to send an image**: LED0 should light up (encrypting)
- **When encryption completes**: LED2 lights up (done)
- **Flip SW0 to 1, press btnR**: LED1 lights up (decrypting and transmitting)

---

## 9. Common Vivado Errors and How to Fix Them

### Error: "Synthesis failed — undeclared module"
**Cause**: A module is instantiated but its `.v` file wasn't added to the project.
**Fix**: Add the missing source file (Step 6.4).

### Error: "CRITICAL WARNING: No clock constraint"
**Cause**: The `.xdc` constraint file isn't added or the clock pin name doesn't match.
**Fix**: Ensure `basys3.xdc` is added as a constraint file, and the port name in `.xdc` matches the port name in `top.v`.

### Error: "Port width mismatch"
**Cause**: In a module instantiation, a 4-bit signal is connected to an 8-bit port (or similar).
**Fix**: Check the port declaration in the module definition and match widths.

### Warning: "Timing not met (WNS is negative)"
**Cause**: Some signals can't reach their destination within one clock period (10 ns).
**Fix**: For our project at 100 MHz, this shouldn't happen. If it does, try:
- Re-running implementation (it's somewhat random and may succeed on a second try)
- Reducing clock frequency by changing the constraint to a larger period

### Error: "No valid device found"
**Cause**: Vivado can't find the FPGA board.
**Fix**: Check USB connection, install drivers, try different USB port.

### Warning: "Unconnected port"
**Cause**: A module port isn't connected to anything.
**Fix**: Either connect it or intentionally leave it unconnected (Vivado handles this, but it's good to review).

---

## 10. Key Takeaways

1. **The Basys 3** is an FPGA development board with a Xilinx Artix-7 chip, 16 switches, 16 LEDs, 5 buttons, and a USB-UART bridge.

2. **The constraint file (.xdc)** maps Verilog signal names to physical FPGA pins. Without it, Vivado doesn't know which pin is which.

3. **The Vivado flow** is: Write Code → Simulate → Synthesize → Implement → Generate Bitstream → Program Board.

4. **Synthesis** converts Verilog to logic gates. **Implementation** places and routes those gates onto the actual FPGA chip. **Bitstream** is the final binary that configures the FPGA.

5. **Timing analysis** checks if your design can run at the target clock speed. Positive WNS = good. Negative WNS = redesign needed.

6. **FPGA configuration is volatile** — power off means the design is gone. You reprogram each time you power on (or set up SPI flash boot for persistence).

---

> **Next**: [Document 03 — Project Architecture Overview](03_Project_Architecture_Overview.md) — Understand the big picture: what this project does, how data flows, and how all modules connect.
