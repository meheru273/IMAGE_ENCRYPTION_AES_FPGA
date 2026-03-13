# Document 16: Drawbacks, Bottlenecks, and Future Research Directions

> **Goal**: By the end of this document, you will understand the current limitations of this project,
> where performance bottlenecks exist, and what improvements could be made to turn this into a
> publishable research contribution.

---

## Table of Contents
1. [Current Project Strengths](#1-current-project-strengths)
2. [Drawback 1: ECB Mode — Pattern Leakage](#2-drawback-1-ecb-mode--pattern-leakage)
3. [Drawback 2: UART Bottleneck](#3-drawback-2-uart-bottleneck)
4. [Drawback 3: Hardcoded Key](#4-drawback-3-hardcoded-key)
5. [Drawback 4: No Authentication (Integrity Check)](#5-drawback-4-no-authentication-integrity-check)
6. [Drawback 5: Small Image Size](#6-drawback-5-small-image-size)
7. [Drawback 6: Word-Serial AES Architecture](#7-drawback-6-word-serial-aes-architecture)
8. [Bottleneck Analysis with Numbers](#8-bottleneck-analysis-with-numbers)
9. [Future Research Direction 1: CBC/CTR/GCM Mode Implementation](#9-future-research-direction-1-cbcctrgcm-mode-implementation)
10. [Future Research Direction 2: Pipelined AES for High Throughput](#10-future-research-direction-2-pipelined-aes-for-high-throughput)
11. [Future Research Direction 3: Chaos-Based Image Encryption + AES Hybrid](#11-future-research-direction-3-chaos-based-image-encryption--aes-hybrid)
12. [Future Research Direction 4: Side-Channel Attack Resistance](#12-future-research-direction-4-side-channel-attack-resistance)
13. [Future Research Direction 5: Real-Time Video Encryption](#13-future-research-direction-5-real-time-video-encryption)
14. [Future Research Direction 6: High-Speed Interface (Ethernet/PCIe)](#14-future-research-direction-6-high-speed-interface-ethernetpcie)
15. [Future Research Direction 7: Multi-Algorithm Comparison](#15-future-research-direction-7-multi-algorithm-comparison)
16. [Paper-Worthy Research Ideas — Summary Table](#16-paper-worthy-research-ideas--summary-table)
17. [Suggested Paper Structure](#17-suggested-paper-structure)
18. [Relevant Conferences and Journals](#18-relevant-conferences-and-journals)
19. [Key Takeaways](#19-key-takeaways)

---

## 1. Current Project Strengths

Before discussing drawbacks, let's acknowledge what's done well:

| Strength | Why It Matters |
|----------|----------------|
| Full working system | End-to-end: PC → UART → FPGA (encrypt) → BRAM → FPGA (decrypt) → UART → PC |
| Verified with NIST vectors | Correctness is proven against the official standard |
| Modular design | Each module is independently tested and reusable |
| Open-source AES core | Built on the well-respected Secworks implementation |
| Complete testbench suite | 11 testbenches covering every module |
| PC host software | Python script for easy demonstration |
| Detailed documentation | (That you're reading right now!) |

This is a **solid educational project** and a strong base for research extensions.

---

## 2. Drawback 1: ECB Mode — Pattern Leakage

### The Problem

ECB (Electronic Codebook) mode encrypts each 16-byte block independently with the same key. **Identical plaintext blocks produce identical ciphertext blocks.** This leaks structural information about the image.

### Visual Demonstration

```
Original Image (128×128)        ECB Encrypted              What an attacker sees
┌──────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│ █████████████████████│    │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│    │ Uniform regions map  │
│ █                   █│    │ ▒ ░░░░░░░░░░░░░░░░ ▒│    │ to same cipher block │
│ █   HELLO WORLD     █│    │ ▒ ▓▓▓▓▓ ░░░░░      ▒│    │ → silhouette visible │
│ █                   █│    │ ▒ ░░░░░░░░░░░░░░░░ ▒│    │                      │
│ █████████████████████│    │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│    │ The outline is leaked│
└──────────────────────┘    └──────────────────────┘    └──────────────────────┘
```

This is the famous **"ECB Penguin"** problem. The background pixels (all the same value) encrypt to the same ciphertext, preserving the pattern.

### Severity: HIGH for image encryption

For random data (like network packets), ECB's weakness is less critical because blocks are unlikely to repeat. But for images — which have large uniform regions (sky, background, etc.) — ECB is fundamentally insecure.

### Solution: Use CBC, CTR, or GCM mode (see Future Research Direction 1)

---

## 3. Drawback 2: UART Bottleneck

### The Problem

The FPGA can encrypt at hundreds of megabits per second, but UART limits us to ~115 Kbps.

### Bottleneck Analysis

```
Component              Throughput            Time for 16 KB image
──────────            ──────────            ────────────────────
AES-128 (FPGA)        ~3 Gbps theoretical   ~0.00005 seconds  (0.05 ms)
AES-128 (this design) ~237 Mbps             ~0.00055 seconds  (0.55 ms)
UART at 115200        ~0.092 Mbps           ~1.42 seconds
                      ^^^^^^^^^^^
                       BOTTLENECK (2,500× slower than AES!)
```

The FPGA spends 99.96% of its time **waiting for UART data**. This is like using a Ferrari to deliver letters at walking speed.

### Severity: MEDIUM (acceptable for a demo, but limits practical use)

### Solutions
- Use higher baud rate (up to ~3 Mbps on Basys 3's FTDI chip)
- Switch to SPI (up to ~50 Mbps)
- Use Ethernet (100 Mbps built into some dev boards)
- Use PCIe (Gbps speeds, requires advanced FPGA boards)

---

## 4. Drawback 3: Hardcoded Key

### The Problem

```verilog
localparam [127:0] AES_KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
```

The encryption key is **hardcoded in the Verilog source code**. Anyone who can read the bitstream or source code knows the key.

### Severity: HIGH for any real-world application

### Why It Was Done This Way

For a demo/educational project, a hardcoded NIST test key makes verification easy — you can compare against known NIST outputs.

### Solutions

| Approach | Complexity | Security |
|----------|-----------|----------|
| Load key via UART before encrypting | Low | Medium (key visible on serial link) |
| Load key via DIP switches/jumpers | Low | Low (physically visible) |
| Store key in FPGA's eFUSE (one-time programable) | Medium | High |
| Use secure key exchange protocol (e.g., Diffie-Hellman) | High | Very High |
| Hardware Security Module (HSM) integration | Very High | Military-grade |

---

## 5. Drawback 4: No Authentication (Integrity Check)

### The Problem

AES provides **confidentiality** (nobody can read your data) but NOT **integrity** (nobody can tell if the data was modified).

An attacker could:
1. Intercept the encrypted image in BRAM
2. Modify some ciphertext blocks (flip bits randomly)
3. The decryption would succeed but produce corrupted data
4. The system would NOT detect the tampering

### Severity: HIGH for security-critical applications

### Solution: Use Authenticated Encryption (AES-GCM)

AES-GCM (Galois/Counter Mode) provides both encryption AND authentication. It produces a **TAG** alongside the ciphertext. If anyone modifies the ciphertext, the tag check fails, and the system rejects the data.

---

## 6. Drawback 5: Small Image Size

### The Problem

The current design supports only 128×128 pixels (16 KB). This is tiny by modern standards.

```
Our image:     128 × 128  = 16,384 pixels      = 16 KB
VGA image:     640 × 480  = 307,200 pixels      = 300 KB
HD image:    1920 × 1080  = 2,073,600 pixels    = ~2 MB
4K image:    3840 × 2160  = 8,294,400 pixels    = ~8 MB
```

### Why This Limit?

BRAM storage: 1024 × 128 bits = 16 KB. The Artix-7 has only 225 KB of BRAM total.

### Solutions

| Image Size | Storage Needed | Approach |
|------------|---------------|----------|
| 256×256 | 64 KB | Use more BRAM (26% of available) |
| 512×512 | 256 KB | Exceeds BRAM → use external SRAM or DDR |
| 1024×1024 | 1 MB | External DDR3 memory required |
| 1920×1080 | ~2 MB | External DDR3 + high-speed interface |

The Basys 3 doesn't have external DDR memory, but boards like the Nexys A7 or Arty A7 do.

---

## 7. Drawback 6: Word-Serial AES Architecture

### The Problem

The Secworks AES core processes the S-box substitution **one 32-bit word at a time** (4 cycles per SubBytes, because only one S-box is shared). This means:

```
SubBytes for one round:
  - 128 bits ÷ 32 bits = 4 words
  - 4 cycles for S-box lookups
  - × 10 rounds = 40 S-box cycles
  Plus other operations ≈ ~54 cycles per block total

Throughput: 128 bits / 54 cycles × 100 MHz = ~237 Mbps
```

### Alternative: Fully Pipelined AES

A fully pipelined AES-128 can process one block per clock cycle:

```
Throughput: 128 bits × 100 MHz = 12.8 Gbps
```

That's **54× faster** than our current implementation!

### Trade-off

| Approach | LUT Usage | Throughput | Latency |
|----------|----------|-----------|---------|
| Word-serial (our design) | ~3,000 LUTs | ~237 Mbps | ~54 cycles |
| Fully unrolled pipelined | ~20,000+ LUTs | ~12.8 Gbps | 10 cycles (pipelined) |
| Loop-unrolled (2 rounds/cycle) | ~8,000 LUTs | ~2.5 Gbps | ~5 cycles |

The word-serial approach uses fewer resources (important for the small Artix-7), while pipelining uses more resources but achieves much higher throughput.

---

## 8. Bottleneck Analysis with Numbers

### Where Time is Spent (Encrypting Full 128×128 Image)

```
┌───────────────────────────────────────────────────────────┐
│            Time Breakdown (Encryption)                     │
├──────────────────────────┬──────────┬─────────────────────┤
│ Activity                 │ Time     │ % of Total          │
├──────────────────────────┼──────────┼─────────────────────┤
│ UART Transfer (16384 B)  │ 1,420 ms │ 99.96%             │
│ AES Key Expansion (once) │ 0.005 ms │ 0.0004%            │
│ AES Encryption (1024 blk)│ 0.55 ms  │ 0.039%             │
│ BRAM Write (1024 writes) │ 0.01 ms  │ 0.001%             │
├──────────────────────────┼──────────┼─────────────────────┤
│ TOTAL                    │ ~1,421 ms│ 100%               │
└──────────────────────────┴──────────┴─────────────────────┘

UART dominates at 99.96% of total time!
```

### If We Used Faster Interfaces

```
Interface        Speed         Transfer Time    AES % of Total
─────────       ─────         ─────────────    ──────────────
UART 115200     0.092 Mbps    1,420 ms         0.04%
UART 3M baud    2.4 Mbps      54 ms            1.0%
SPI             50 Mbps       2.6 ms           17%
Ethernet        100 Mbps      1.3 ms           30%
Gigabit ETH     1 Gbps        0.13 ms          80%  ← AES becomes bottleneck!
```

At Gigabit Ethernet speeds, the FPGA's AES throughput (~237 Mbps) becomes the bottleneck, not the interface. This is where pipelined AES becomes important.

---

## 9. Future Research Direction 1: CBC/CTR/GCM Mode Implementation

### What to Implement

Replace ECB with a more secure mode of operation:

**CBC (Cipher Block Chaining):**
```
Ciphertext[i] = AES_Encrypt(Plaintext[i] ⊕ Ciphertext[i-1])
```
Each block depends on the previous ciphertext, so identical plaintext blocks produce different ciphertext. Requires an Initialization Vector (IV).

**CTR (Counter Mode):**
```
Ciphertext[i] = Plaintext[i] ⊕ AES_Encrypt(Nonce || Counter_i)
```
Encrypts a counter, then XORs with plaintext. **Fully parallelizable** (great for FPGA!) and acts as a stream cipher. Each block can be processed independently if you know the counter value.

**GCM (Galois/Counter Mode):**
```
CTR mode encryption + Galois field authentication tag
```
Provides both encryption AND authentication. The gold standard for modern encryption.

### Research Value

**Paper title idea**: *"FPGA Implementation and Comparison of AES Block Cipher Modes for Real-Time Image Encryption"*

**What to compare**: ECB vs CBC vs CTR vs GCM on the same Artix-7 platform:
- Resource utilization (LUTs, FFs, BRAM)
- Throughput (Mbps)
- Latency (clock cycles per block)
- Visual security analysis (show the "ECB Penguin" effect vs. proper randomization in CBC/CTR)
- Power consumption

### Novelty

While AES implementations on FPGA are well-studied, systematic mode comparisons specifically for **image encryption** on low-cost FPGAs (Artix-7) with visual security analysis are less common and publishable.

---

## 10. Future Research Direction 2: Pipelined AES for High Throughput

### What to Implement

Replace the word-serial AES with a **fully pipelined** design:

```
Standard (current):
  Block 1: ────[Round1]──[Round2]──...──[Round10]────
  Block 2:                                            ────[Round1]──...
  One block every ~54 cycles

Pipelined:
  Block 1:  ─[R1]─[R2]─[R3]─[R4]─[R5]─[R6]─[R7]─[R8]─[R9]─[R10]─
  Block 2:       ─[R1]─[R2]─[R3]─[R4]─[R5]─[R6]─[R7]─[R8]─[R9]─[R10]─
  Block 3:            ─[R1]─[R2]─...
  One NEW result every 1 cycle (after initial 10-cycle delay)!
```

### Research Value

Each pipeline stage has its own hardware for one AES round. After the pipeline is filled, you get one encrypted block **every clock cycle**:

```
Throughput = 128 bits × 100 MHz = 12.8 Gbps
```

**Paper title idea**: *"Area-Throughput Trade-offs in Pipelined vs. Iterative AES-128 for FPGA-Based Image Encryption"*

### Challenge

A fully pipelined AES-128 needs 10× the S-box hardware (one per round). On the XC7A35T:
- 10 rounds × 16 S-box lookups = 160 parallel S-box instances
- Each S-box is a 256-entry ROM → significant LUT usage
- May need partial pipelining (e.g., 2 or 5 rounds in parallel)

This trade-off study is itself publishable.

---

## 11. Future Research Direction 3: Chaos-Based Image Encryption + AES Hybrid

### What to Implement

Combine AES with a **chaotic map** for image-specific encryption:

1. **Pixel Scrambling**: Use a chaotic map (Logistic, Arnold Cat, Henon, Baker's) to permute pixel positions
2. **AES Encryption**: Encrypt the scrambled pixels with AES-128/256

```
Original Image → Chaotic Scrambling → AES Encryption → Double-Encrypted Image
                 (pixel positions     (pixel values
                  shuffled)            encrypted)
```

### Why This is Novel

- Pure AES in ECB mode leaks patterns (we've seen the ECB Penguin)
- Chaotic maps scramble pixel positions, breaking spatial correlations BEFORE encryption
- The combination provides much stronger security than either alone
- FPGA implementation of chaotic maps is itself an active research area

### Research Value

**Paper title idea**: *"Hardware Implementation of Hybrid Chaos-AES Image Encryption on Low-Cost FPGA"*

**Metrics to report:**
- Key space analysis (show it's astronomically large)
- Correlation coefficient analysis (horizontal, vertical, diagonal — should be near 0)
- Information entropy (should be near 8.0 for 8-bit grayscale)
- NPCR and UACI (Number of Pixels Change Rate, Unified Average Changing Intensity)
- Histogram analysis (encrypted image should have flat/uniform histogram)
- Speed comparison: software (Python) vs. FPGA implementation

This direction is **highly publishable** — it's an active research area with dozens of papers published annually.

---

## 12. Future Research Direction 4: Side-Channel Attack Resistance

### What to Implement

Standard AES implementations are vulnerable to **side-channel attacks** — attacks that don't break the math but exploit physical characteristics:

| Attack Type | What It Exploits | How |
|------------|-----------------|-----|
| **Power Analysis** (DPA/CPA) | Power consumption varies based on data being processed | Measure current draw during encryption, statistically correlate with key bits |
| **Timing Analysis** | Some operations take different amounts of time based on data | Measure encryption time for many inputs, deduce key information |
| **Electromagnetic** | EM radiation patterns reveal internal operations | Place antenna near FPGA, capture EM emissions |

### Countermeasures to Implement

1. **Masking**: XOR all intermediate values with random data (masks) that are removed at the end
2. **Shuffling**: Randomize the order of S-box lookups each round
3. **Constant-Power**: Use dual-rail logic that consumes the same power regardless of data
4. **Clock Jitter**: Add random variations to clock timing

### Research Value

**Paper title idea**: *"Power Analysis Resistant AES-128 Implementation on FPGA: Area and Performance Overhead Analysis"*

**What to measure:**
- Area overhead (additional LUTs/FFs needed for countermeasures)
- Throughput reduction
- Effectiveness against CPA attacks (correlation values before and after countermeasures)
- Number of traces needed to extract the key (without protection: ~1000; with protection: >1 million)

This is a well-funded research area with defense and security applications.

---

## 13. Future Research Direction 5: Real-Time Video Encryption

### What to Implement

Scale up from a single 128×128 image to **real-time video encryption**:

```
Camera (30 fps, 640×480) → FPGA → AES Encrypt → Encrypted Stream → Decrypt → Display
```

### Technical Challenges

```
Video data rate: 640 × 480 × 8 bits × 30 fps = 73.7 Mbps
AES throughput needed: >73.7 Mbps (our word-serial design: 237 Mbps ✓)
```

Our current AES core (237 Mbps) can actually handle standard-definition video! But we'd need:
- A camera interface (OV7670 camera module → 8-bit parallel input)
- VGA/HDMI output
- Frame buffer in external memory
- Much higher-bandwidth interface than UART

### Research Value

**Paper title idea**: *"FPGA-Based Real-Time AES Video Encryption with Camera Interface and Display Output"*

---

## 14. Future Research Direction 6: High-Speed Interface (Ethernet/PCIe)

### What to Implement

Replace UART with a high-speed interface to actually utilize the FPGA's encryption throughput:

| Interface | Speed | Improvement over UART |
|-----------|-------|-----------------------|
| SPI | ~50 Mbps | ~544× |
| Ethernet (10/100) | 100 Mbps | ~1,087× |
| Gigabit Ethernet | 1 Gbps | ~10,870× |
| USB 3.0 | 5 Gbps | ~54,350× |
| PCIe Gen2 x4 | 20 Gbps | ~217,000× |

### Research Value

Building an Ethernet-based encryption system is a practical real-world application (VPN hardware acceleration, secure image transmission over networks).

**Paper title idea**: *"Ethernet-Interfaced FPGA Encryption Accelerator for Secure Network Image Transmission"*

---

## 15. Future Research Direction 7: Multi-Algorithm Comparison

### What to Implement

Implement multiple encryption algorithms on the same FPGA and compare:

| Algorithm | Key Size | Block Size | Rounds | Expected LUTs |
|-----------|---------|-----------|--------|---------------|
| AES-128 | 128 bits | 128 bits | 10 | ~3,000 |
| AES-256 | 256 bits | 128 bits | 14 | ~3,500 |
| ChaCha20 | 256 bits | 512 bits | 20 | ~2,000 |
| PRESENT | 80 bits | 64 bits | 31 | ~500 |
| SIMON | 128 bits | 128 bits | 68 | ~800 |
| SPECK | 128 bits | 128 bits | 32 | ~600 |

PRESENT, SIMON, and SPECK are **lightweight ciphers** designed for IoT and constrained environments. Comparing them against AES on the same platform is valuable.

### Research Value

**Paper title idea**: *"Comparative Analysis of Lightweight and Standard Ciphers for FPGA-Based Image Encryption: AES vs. SIMON vs. SPECK vs. ChaCha20"*

**What to compare:**
- LUT/FF utilization
- Throughput (Mbps)
- Energy per byte encrypted (nJ/byte)
- Security margin
- Image quality metrics (PSNR, entropy, correlation)

---

## 16. Paper-Worthy Research Ideas — Summary Table

| # | Research Direction | Novelty Level | Implementation Difficulty | Publication Potential |
|---|-------------------|--------------|--------------------------|---------------------|
| 1 | AES Mode Comparison (ECB/CBC/CTR/GCM) | Medium | Medium | Good — Conference paper |
| 2 | Pipelined AES Trade-off Study | Medium | High | Good — Conference paper |
| 3 | Chaos + AES Hybrid | High | Medium | Excellent — Journal paper |
| 4 | Side-Channel Resistance | High | Very High | Excellent — Top conference |
| 5 | Real-Time Video Encryption | Medium | High | Good — Conference paper |
| 6 | High-Speed Interface | Medium | Medium-High | Good — Conference paper |
| 7 | Multi-Algorithm Comparison | Medium-High | High | Very Good — Journal paper |

### Recommended for First Paper: #1 or #3

- **Direction 1** (Mode Comparison) is the easiest to build upon your existing project
- **Direction 3** (Chaos + AES) has the highest novelty potential and is actively published in IEEE, Springer, and Elsevier journals

---

## 17. Suggested Paper Structure

For a typical IEEE-format paper:

```
1. Abstract (150-250 words)
2. Introduction
   - Importance of image encryption
   - Limitations of software-only approaches
   - Motivation for FPGA implementation
3. Related Work
   - Previous FPGA AES implementations
   - Image encryption techniques
   - (Cite 15-25 papers)
4. Proposed System Architecture
   - Block diagram
   - Module descriptions
   - Mode of operation (CBC/CTR/GCM or Chaos+AES)
5. Implementation Details
   - Target device (Artix-7)
   - RTL design decisions
   - Optimization techniques
6. Results and Analysis
   - Resource utilization (LUT, FF, BRAM)
   - Timing and throughput
   - Security analysis (entropy, correlation, histogram, NPCR, UACI)
   - Comparison with related work
7. Conclusion and Future Work
8. References
```

### Key Metrics to Report

**Performance metrics:**
- Maximum clock frequency (Fmax)
- Throughput (Mbps or Gbps)
- Latency (clock cycles, microseconds)
- Efficiency = Throughput / Area (Mbps per slice)

**Resource metrics:**
- LUT utilization
- FF utilization
- BRAM usage
- DSP usage (should be 0 for AES)
- Total power consumption (reported by Vivado)

**Security metrics (for image encryption):**
- Information Entropy (ideal: 8.0 for 8-bit images)
- Correlation Coefficients — horizontal, vertical, diagonal (ideal: near 0.0)
- NPCR — Number of Pixels Change Rate (ideal: >99.6%)
- UACI — Unified Average Changing Intensity (ideal: ~33.46%)
- Key Sensitivity (change 1 bit of key → completely different ciphertext)
- Histogram Analysis (encrypted image should have flat histogram)

---

## 18. Relevant Conferences and Journals

### Conferences

| Conference | Publisher | Focus |
|-----------|----------|-------|
| IEEE International Conference on VLSI Design | IEEE | FPGA/VLSI |
| IEEE International Symposium on Circuits and Systems (ISCAS) | IEEE | Circuits |
| ACM/SIGDA International Symposium on FPGAs (FPGA) | ACM | FPGA-specific |
| International Conference on Field-Programmable Technology (FPT) | IEEE | FPGA |
| Design Automation Conference (DAC) | ACM/IEEE | EDA/Design |
| IEEE International Conference on Multimedia & Expo (ICME) | IEEE | Multimedia |

### Journals

| Journal | Publisher | Impact |
|---------|----------|--------|
| IEEE Transactions on VLSI Systems | IEEE | High |
| IEEE Access | IEEE | Open access, good for first publication |
| Journal of Cryptographic Engineering | Springer | Crypto hardware |
| Multimedia Tools and Applications | Springer | Image/Video processing |
| IEEE Transactions on Information Forensics and Security | IEEE | Very High |
| Journal of Real-Time Image Processing | Springer | Real-time focus |
| Microprocessors and Microsystems | Elsevier | Embedded systems |

### Recommended Starting Point

For your **first publication**, target:
1. **IEEE Access** — open access, moderate acceptance rate, good visibility
2. **A regional IEEE conference** — faster review, easier acceptance, builds experience
3. **Multimedia Tools and Applications** — good for image encryption + FPGA papers

---

## 19. Key Takeaways

1. **ECB mode is the biggest security weakness** — identical blocks produce identical ciphertext, leaking image patterns. This must be addressed for any security-critical application.

2. **UART is the performance bottleneck** (99.96% of time). Faster interfaces (SPI, Ethernet, PCIe) would unleash the FPGA's actual encryption throughput.

3. **The hardcoded key** is fine for a demo but unacceptable for real-world use. Dynamic key loading is essential.

4. **No integrity protection** — an attacker can modify ciphertext without detection. AES-GCM solves this.

5. **The most publishable extensions** are:
   - Chaos + AES hybrid encryption (Direction 3) — highest novelty
   - Block cipher mode comparison (Direction 1) — easiest to build on
   - Multi-algorithm comparison (Direction 7) — broad impact

6. **For a paper**, you need: performance metrics (throughput, latency, area), security metrics (entropy, correlation, NPCR/UACI), and comparison with existing work.

7. **Start with the conference/journal that matches your research focus**: IEEE Access for broad FPGA topics, Multimedia Tools and Applications for image encryption, Journal of Cryptographic Engineering for crypto hardware.

---

> **Congratulations!** You've completed all 16 documents of this tutorial series. You now have a comprehensive understanding of:
> - FPGA fundamentals and Verilog syntax
> - The Basys 3 board and Vivado workflow
> - UART serial communication
> - AES-128 encryption algorithm
> - Every module in the project
> - Simulation and testing
> - Where to go next for research
>
> Go build something amazing!
