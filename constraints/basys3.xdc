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
## Configuration
## ============================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
