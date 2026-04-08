from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image,
                                PageBreak, Table, TableStyle)
from reportlab.lib import colors

doc = SimpleDocTemplate("AES_Image_Encryption_Report.pdf", pagesize=A4,
                        leftMargin=2*cm, rightMargin=2*cm,
                        topMargin=2*cm, bottomMargin=2*cm)
styles = getSampleStyleSheet()
h1 = styles['Heading1']; h2 = styles['Heading2']; body = styles['BodyText']
body.alignment = 4  # justify
title = ParagraphStyle('t', parent=styles['Title'], fontSize=20, spaceAfter=12)

S = []
def P(t): S.append(Paragraph(t, body)); S.append(Spacer(1,6))
def H1(t): S.append(Paragraph(t, h1)); S.append(Spacer(1,4))
def H2(t): S.append(Paragraph(t, h2)); S.append(Spacer(1,4))

S.append(Paragraph("AES-128 Image Encryption on FPGA", title))
P("<b>Project Report</b><br/>Hardware Implementation of AES-128 for "
  "Grayscale Image Encryption on the Digilent Basys 3 (Artix-7) FPGA")
S.append(Spacer(1,12))

H1("1. Objective")
P("The objective of this project is to design, implement and verify a "
  "hardware-based AES-128 image encryption and decryption system on the "
  "Digilent Basys 3 FPGA board. A 128x128 grayscale image is transferred "
  "from a host PC to the FPGA over UART, encrypted block-by-block using "
  "the secworks AES core, stored in on-chip Block RAM, and on demand "
  "decrypted and streamed back to the PC for verification. The aim is to "
  "demonstrate transparent memory encryption in hardware and validate the "
  "correctness of the AES pipeline by comparing the original and "
  "decrypted images.")

H1("2. Introduction")
P("Data security has become a critical requirement in modern embedded "
  "systems. Software based encryption is often too slow or too power "
  "hungry for real-time applications such as secure cameras, IoT sensors "
  "and edge devices. Implementing cryptographic primitives directly in "
  "hardware on an FPGA provides higher throughput, deterministic latency "
  "and resistance against software side-channel attacks.")
P("This project implements the Advanced Encryption Standard (AES) with a "
  "128-bit key on a low cost Artix-7 FPGA. The system communicates with a "
  "Python host program over a 115200 baud UART link. The image is "
  "partitioned into 1024 blocks of 128 bits, each of which is encrypted "
  "by the AES core and written into a 16 KB BRAM. Decryption is "
  "triggered through a push button and the resulting plaintext is "
  "streamed back to the PC where the original image is reconstructed.")

H1("3. Theory")
H2("3.1 AES Algorithm")
P("AES is a symmetric block cipher standardised by NIST in FIPS-197. It "
  "operates on a 4x4 byte state matrix and supports 128, 192 and 256 bit "
  "keys. AES-128 uses ten rounds, each consisting of four "
  "transformations: <b>SubBytes</b> (non-linear byte substitution using a "
  "fixed S-Box), <b>ShiftRows</b> (cyclic shift of rows), <b>MixColumns</b> "
  "(linear mixing in GF(2^8)) and <b>AddRoundKey</b> (XOR with the round "
  "key). The final round omits MixColumns. Decryption uses the inverse "
  "transformations in reverse order.")
H2("3.2 Key Expansion")
P("The 128-bit cipher key is expanded into eleven 128-bit round keys "
  "through the AES key schedule, which uses the S-Box, a round constant "
  "and word-wise XORs. In this implementation key expansion is performed "
  "only once per session and the resulting round keys are stored inside "
  "the secworks aes_key_mem module.")
H2("3.3 UART Protocol")
P("The Universal Asynchronous Receiver Transmitter is a simple serial "
  "protocol consisting of a start bit, 8 data bits (LSB first), and a "
  "stop bit at 115200 bps (8N1). The receiver synchronises incoming data "
  "with a double flip-flop and samples each bit at its midpoint for noise "
  "immunity.")
H2("3.4 Block RAM Storage")
P("The Artix-7 BRAM blocks are configured as 1024 entries of 128 bits "
  "(16 KB total) using a single BRAM36 tile. Ciphertext is written during "
  "encryption and read back during decryption.")

H1("4. System Architecture and Diagram")
P("The system is composed of six custom RTL modules wrapped around the "
  "secworks AES core, plus a Python host script:")
P("<b>uart_rx.v</b> &mdash; deserialises bytes from the PC.<br/>"
  "<b>pixel_buffer.v</b> &mdash; assembles 16 bytes into a 128-bit block.<br/>"
  "<b>aes_ctrl.v</b> &mdash; FSM that drives the secworks aes_core handshake "
  "(init, next, ready, done).<br/>"
  "<b>bram_ctrl.v</b> &mdash; 1024x128 BRAM wrapper for cipher storage.<br/>"
  "<b>uart_tx.v</b> &mdash; serialises decrypted bytes back to the PC.<br/>"
  "<b>top.v</b> &mdash; system level FSM selecting encrypt or decrypt mode.")
P("The figure below shows the data flow through the system:")
S.append(Image("diagram.png", width=15*cm, height=9*cm))
S.append(Spacer(1,6))
_unused = (
"<font face='Courier' size='8'>"
"PC (Python) ──UART──&gt; uart_rx.v<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;pixel_buffer.v  (16 bytes → 128-bit block)<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;aes_ctrl.v FSM (drives secworks aes_core)<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;&nbsp;&nbsp;[ENCRYPT]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[DECRYPT]<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;&nbsp;bram_ctrl.v&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;bram_ctrl.v<br/>"
"&nbsp;(write cipher)&nbsp;&nbsp;(read cipher)<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;BRAM (16 KB)&nbsp;&nbsp;aes_ctrl → uart_tx.v<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;│<br/>"
"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;PC reconstructs image"
"</font>")

H2("4.1 Hardware Specifications")
data = [["Parameter","Value"],
 ["Board","Digilent Basys 3"],
 ["FPGA","Artix-7 XC7A35T-1CPG236C"],
 ["Tool","Vivado 2023.1"],
 ["Clock","100 MHz"],
 ["UART baud","115200 (8N1)"],
 ["AES key size","128-bit"],
 ["Image size","128 x 128 grayscale"],
 ["Total data","16384 bytes"],
 ["AES blocks","1024 x 128 bits"],
 ["BRAM","1 x BRAM36 tile"]]
t = Table(data, hAlign='LEFT', colWidths=[5*cm,8*cm])
t.setStyle(TableStyle([('GRID',(0,0),(-1,-1),0.4,colors.grey),
                       ('BACKGROUND',(0,0),(-1,0),colors.lightgrey),
                       ('FONTNAME',(0,0),(-1,0),'Helvetica-Bold')]))
S.append(t); S.append(Spacer(1,10))

H1("5. Input and Output Images")
P("The standard <i>Lena</i> 128x128 grayscale test image was used as the "
  "input. It was sent to the FPGA over UART, encrypted block by block, "
  "stored in BRAM, then decrypted and streamed back to the host. The "
  "decrypted image is bit-identical to the original, confirming correct "
  "operation of the encrypt and decrypt pipelines.")

img1 = Image("lena.png", width=5*cm, height=5*cm)
img2 = Image("lena_decprepted.png", width=5*cm, height=5*cm)
imgtab = Table([[img1, img2],
                ["Fig. 1: Input image (lena.png)",
                 "Fig. 2: Decrypted output image"]],
               colWidths=[7*cm,7*cm])
imgtab.setStyle(TableStyle([('ALIGN',(0,0),(-1,-1),'CENTER'),
                            ('FONTSIZE',(0,1),(-1,1),9)]))
S.append(imgtab); S.append(Spacer(1,10))

H1("6. Discussion")
P("The hardware implementation successfully encrypts and decrypts the "
  "image with full bitwise correctness. The AES controller FSM correctly "
  "follows the secworks aes_core handshake by asserting <i>init</i> for "
  "key expansion and <i>next</i> for each block, while monitoring the "
  "<i>ready</i> and <i>done</i> signals. Performing key expansion only "
  "once per session reduces per-block latency.")
P("UART throughput is the dominant bottleneck. At 115200 baud, "
  "transferring all 16384 bytes takes roughly 1.4 seconds in each "
  "direction, while the AES core itself processes a 128-bit block in "
  "tens of clock cycles at 100 MHz, which is several orders of magnitude "
  "faster than the serial link. Replacing UART with USB-FIFO or Ethernet "
  "would expose the true throughput of the cipher.")
P("The current implementation uses the Electronic Codebook (ECB) mode of "
  "operation, which encrypts each block independently. ECB does not hide "
  "spatial patterns in images and is not recommended for confidential "
  "data; using CBC, CTR or GCM modes would be more secure. The 128-bit "
  "key is also hard-coded inside <i>top.v</i> for demonstration "
  "purposes and should be loaded from a secure source in any real "
  "deployment. Resource utilisation remains very low: a single BRAM36 "
  "tile and a small portion of the available LUTs and flip-flops, "
  "leaving room for additional features such as larger images, multiple "
  "key slots or hardware acceleration of other primitives.")

H1("7. Conclusion")
P("A complete AES-128 image encryption and decryption system has been "
  "designed, simulated and deployed on the Digilent Basys 3 FPGA. The "
  "design integrates a UART receiver and transmitter, a pixel buffer, a "
  "BRAM controller and a custom AES FSM around the secworks AES core, "
  "all coordinated by a top level state machine. End-to-end testing with "
  "the standard Lena image confirms that the decrypted output is "
  "identical to the original input, validating the correctness of both "
  "the cryptographic pipeline and the surrounding data path. The "
  "project demonstrates how cryptographic primitives can be efficiently "
  "implemented in low cost reconfigurable hardware and provides a solid "
  "foundation for future work on secure modes of operation, higher "
  "throughput interfaces, and side-channel resistant designs.")

H1("8. References")
refs = [
 "1. NIST FIPS-197, <i>Advanced Encryption Standard (AES)</i>, 2001.",
 "2. J. Strömbergson, <i>secworks/aes</i> Verilog AES core, "
 "https://github.com/secworks/aes",
 "3. Digilent Inc., <i>Basys 3 FPGA Board Reference Manual</i>.",
 "4. Xilinx, <i>7 Series FPGAs Memory Resources User Guide (UG473)</i>.",
 "5. Xilinx, <i>Vivado Design Suite User Guide</i>, 2023.1.",
 "6. W. Stallings, <i>Cryptography and Network Security: Principles and "
 "Practice</i>, 7th ed., Pearson, 2017.",
 "7. Project repository documentation (docs/01..16, README.md)."]
for r in refs: P(r)

doc.build(S)
print("PDF written")
