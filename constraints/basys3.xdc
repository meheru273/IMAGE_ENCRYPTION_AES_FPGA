## Basys 3 XDC Constraints
## AES-128 Transparent Memory Encryption
## Board: Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C)

## ============================================================
## Clock — 100 MHz oscillator
## ============================================================
set_property PACKAGE_PIN W5  [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]


## ============================================================
## UART — USB-UART bridge (directly on Basys 3)
## ============================================================
## TX: FPGA -> PC (directly, active driver; directly on board layout)
set_property PACKAGE_PIN A18 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]

## RX: PC -> FPGA
set_property PACKAGE_PIN B18 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]

## ============================================================
## Switches
## ============================================================
## SW0: mode select (0=encrypt, 1=decrypt)
set_property PACKAGE_PIN V17 [get_ports mode_sw]
set_property IOSTANDARD LVCMOS33 [get_ports mode_sw]

## SW1: mode modifier (0=full image, 1=key-only)
set_property PACKAGE_PIN V16 [get_ports mode_sw1]
set_property IOSTANDARD LVCMOS33 [get_ports mode_sw1]

## ============================================================
## Buttons (active-high on Basys 3)
## ============================================================
## btnC: system reset
set_property PACKAGE_PIN U18 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

## btnR: trigger decrypt readback
set_property PACKAGE_PIN T17 [get_ports btn_start]
set_property IOSTANDARD LVCMOS33 [get_ports btn_start]

## ============================================================
## LEDs — status indicators
## ============================================================
## LED0: encrypting
set_property PACKAGE_PIN U16 [get_ports {status_led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[0]}]

## LED1: decrypting
set_property PACKAGE_PIN E19 [get_ports {status_led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[1]}]

## LED2: done
set_property PACKAGE_PIN U19 [get_ports {status_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[2]}]

## LED3: error
set_property PACKAGE_PIN V19 [get_ports {status_led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {status_led[3]}]

## ============================================================
## Seven-Segment Display — Cathodes (active-low)
## seg = {CA, CB, CC, CD, CE, CF, CG}
## ============================================================
set_property PACKAGE_PIN W7 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[6]}]

set_property PACKAGE_PIN W6 [get_ports {seg[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[5]}]

set_property PACKAGE_PIN U8 [get_ports {seg[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[4]}]

set_property PACKAGE_PIN V8 [get_ports {seg[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[3]}]

set_property PACKAGE_PIN U5 [get_ports {seg[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[2]}]

set_property PACKAGE_PIN V5 [get_ports {seg[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[1]}]

set_property PACKAGE_PIN U7 [get_ports {seg[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[0]}]

## ============================================================
## Seven-Segment Display — Anodes (active-low)
## ============================================================
set_property PACKAGE_PIN U2 [get_ports {an[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[0]}]

set_property PACKAGE_PIN U4 [get_ports {an[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[1]}]

set_property PACKAGE_PIN V4 [get_ports {an[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[2]}]

set_property PACKAGE_PIN W4 [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[3]}]

## ============================================================
## Configuration
## ============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
