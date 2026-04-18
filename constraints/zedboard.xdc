# ==============================================================================
# zedboard.xdc — Pin constraints for ZedBoard Zynq-7000 SoC Development Kit
#
# Part: xc7z020clg484-1
# Board: Avnet ZedBoard
#
# The design renders the scene on power-up automatically (dirty_latch = '1').
# Simply program the FPGA and connect VGA — the scene appears immediately.
# ==============================================================================

# ──────────────────────────────────────────────────────────
# CLOCK — 100 MHz oscillator (Y9)
# ──────────────────────────────────────────────────────────
set_property PACKAGE_PIN Y9 [get_ports clk_100MHz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100MHz]
create_clock -period 10.000 -name sys_clk [get_ports clk_100MHz]

# ──────────────────────────────────────────────────────────
# RESET — Center push button (active-high)
# ──────────────────────────────────────────────────────────
set_property PACKAGE_PIN P16 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS18 [get_ports rst_btn]

# ──────────────────────────────────────────────────────────
# CAMERA CONTROL — Push buttons (active-high)
#   BTNL = move camera left  (X−)
#   BTNR = move camera right (X+)
#   BTNU = move camera forward (Z+)
#   BTND = move camera backward (Z−)
# ──────────────────────────────────────────────────────────
set_property PACKAGE_PIN N15 [get_ports btn_left]
set_property IOSTANDARD LVCMOS18 [get_ports btn_left]

set_property PACKAGE_PIN R18 [get_ports btn_right]
set_property IOSTANDARD LVCMOS18 [get_ports btn_right]

set_property PACKAGE_PIN T18 [get_ports btn_forward]
set_property IOSTANDARD LVCMOS18 [get_ports btn_forward]

set_property PACKAGE_PIN R16 [get_ports btn_back]
set_property IOSTANDARD LVCMOS18 [get_ports btn_back]

# ──────────────────────────────────────────────────────────
# VGA — RGB444 (4 bits per channel, resistor DAC on ZedBoard)
# ──────────────────────────────────────────────────────────
# Red channel [3:0]  (vga_rgb[11:8])
# vga_rgb[11] = R MSB → VGA_R[3], vga_rgb[8] = R LSB → VGA_R[0]
set_property PACKAGE_PIN V18  [get_ports {vga_rgb[11]}]
set_property PACKAGE_PIN V19  [get_ports {vga_rgb[10]}]
set_property PACKAGE_PIN U20  [get_ports {vga_rgb[9]}]
set_property PACKAGE_PIN V20  [get_ports {vga_rgb[8]}]

# Green channel [3:0]  (vga_rgb[7:4])
# vga_rgb[7] = G MSB → VGA_G[3], vga_rgb[4] = G LSB → VGA_G[0]
set_property PACKAGE_PIN AA21 [get_ports {vga_rgb[7]}]
set_property PACKAGE_PIN AB21 [get_ports {vga_rgb[6]}]
set_property PACKAGE_PIN AA22 [get_ports {vga_rgb[5]}]
set_property PACKAGE_PIN AB22 [get_ports {vga_rgb[4]}]

# Blue channel [3:0]  (vga_rgb[3:0])
# vga_rgb[3] = B MSB → VGA_B[3], vga_rgb[0] = B LSB → VGA_B[0]
set_property PACKAGE_PIN AB19 [get_ports {vga_rgb[3]}]
set_property PACKAGE_PIN AB20 [get_ports {vga_rgb[2]}]
set_property PACKAGE_PIN Y20  [get_ports {vga_rgb[1]}]
set_property PACKAGE_PIN Y21  [get_ports {vga_rgb[0]}]

# VGA sync signals
set_property PACKAGE_PIN AA19 [get_ports vga_hsync]
set_property PACKAGE_PIN Y19  [get_ports vga_vsync]

# All VGA pins use LVCMOS33
set_property IOSTANDARD LVCMOS33 [get_ports {vga_rgb[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

# ──────────────────────────────────────────────────────────
# TIMING CONSTRAINTS
# ──────────────────────────────────────────────────────────
# Generated 25 MHz clock from clock wizard
create_generated_clock -name clk_25MHz -source [get_ports clk_100MHz] \
    -divide_by 4 [get_pins CLK_GEN/clk_out1]

# Clock domain crossing — framebuffer is true dual-port BRAM,
# no additional synchronization needed, but tell Vivado not to
# report paths between the two domains as timing violations
set_false_path -from [get_clocks sys_clk] -to [get_clocks clk_25MHz]
set_false_path -from [get_clocks clk_25MHz] -to [get_clocks sys_clk]

# ──────────────────────────────────────────────────────────
# DRIVE STRENGTH & SLEW RATE for VGA outputs
# ──────────────────────────────────────────────────────────
set_property DRIVE 8 [get_ports {vga_rgb[*]}]
set_property DRIVE 8 [get_ports vga_hsync]
set_property DRIVE 8 [get_ports vga_vsync]
set_property SLEW FAST [get_ports {vga_rgb[*]}]
set_property SLEW FAST [get_ports vga_hsync]
set_property SLEW FAST [get_ports vga_vsync]

# ──────────────────────────────────────────────────────────
# BITSTREAM CONFIGURATION
# ──────────────────────────────────────────────────────────
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]