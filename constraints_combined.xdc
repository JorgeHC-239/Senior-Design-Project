## Clock Input (100 MHz)
set_property PACKAGE_PIN R2 [get_ports {clk100}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk100}]
create_clock -period 10.0 -name clk100 -waveform {0 5} [get_ports {clk100}]

## Reset Button (Active-HIGH)
set_property PACKAGE_PIN T15 [get_ports {rst}]
set_property IOSTANDARD LVCMOS33 [get_ports {rst}]

# --------------------------------------------------------------------
# Phase-A   (Q1A - Q4A)
# --------------------------------------------------------------------
set_property PACKAGE_PIN L13     [get_ports Q1A]
set_property IOSTANDARD LVCMOS33 [get_ports Q1A]
set_property DRIVE       12      [get_ports Q1A]

set_property PACKAGE_PIN N13     [get_ports Q2A]
set_property IOSTANDARD LVCMOS33 [get_ports Q2A]
set_property DRIVE       12      [get_ports Q2A]

set_property PACKAGE_PIN L16     [get_ports Q3A]
set_property IOSTANDARD LVCMOS33 [get_ports Q3A]
set_property DRIVE       12      [get_ports Q3A]

set_property PACKAGE_PIN R14     [get_ports Q4A]
set_property IOSTANDARD LVCMOS33 [get_ports Q4A]
set_property DRIVE       12      [get_ports Q4A]

# --------------------------------------------------------------------
# Phase-B   (Q1B - Q4B)
# --------------------------------------------------------------------
set_property PACKAGE_PIN T14     [get_ports Q1B]
set_property IOSTANDARD LVCMOS33 [get_ports Q1B]
set_property DRIVE       12      [get_ports Q1B]

set_property PACKAGE_PIN R16     [get_ports Q2B]
set_property IOSTANDARD LVCMOS33 [get_ports Q2B]
set_property DRIVE       12      [get_ports Q2B]

set_property PACKAGE_PIN R17     [get_ports Q3B]
set_property IOSTANDARD LVCMOS33 [get_ports Q3B]
set_property DRIVE       12      [get_ports Q3B]

set_property PACKAGE_PIN V17     [get_ports Q4B]
set_property IOSTANDARD LVCMOS33 [get_ports Q4B]
set_property DRIVE       12      [get_ports Q4B]

# --------------------------------------------------------------------
# Phase-C   (Q1C - Q4C)
# --------------------------------------------------------------------
set_property PACKAGE_PIN U11     [get_ports Q1C]
set_property IOSTANDARD LVCMOS33 [get_ports Q1C]
set_property DRIVE       12      [get_ports Q1C]

set_property PACKAGE_PIN T11     [get_ports Q2C]
set_property IOSTANDARD LVCMOS33 [get_ports Q2C]
set_property DRIVE       12      [get_ports Q2C]

set_property PACKAGE_PIN R11     [get_ports Q3C]
set_property IOSTANDARD LVCMOS33 [get_ports Q3C]
set_property DRIVE       12      [get_ports Q3C]

set_property PACKAGE_PIN T13     [get_ports Q4C]
set_property IOSTANDARD LVCMOS33 [get_ports Q4C]
set_property DRIVE       12      [get_ports Q4C]

# ==================== UART ======================
# Pico TX  -> FPGA RX  (IO31, package pin D14)
set_property PACKAGE_PIN V13 [get_ports {uart_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx}]

# Pico RX <-  FPGA TX  (IO30, package pin D15)
set_property PACKAGE_PIN T12 [get_ports {uart_tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx}]
## Fan Outputs
set_property PACKAGE_PIN V15 [get_ports {fan_out1}]
set_property IOSTANDARD LVCMOS33 [get_ports {fan_out1}]
set_property PACKAGE_PIN U12 [get_ports {fan_out2}]
set_property IOSTANDARD LVCMOS33 [get_ports {fan_out2}]

