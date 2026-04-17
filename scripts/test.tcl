# ==============================================================================
# test.tcl — Non-project mode build for Raymarching GPU (ZedBoard)
#
# Usage: vivado -mode batch -source scripts/test.tcl
#
# Generates clk_wiz_0 IP (100MHz → 25MHz), synthesizes, implements,
# and writes bitstream in one shot.
# ==============================================================================

# --- Configuration & Cleanup ---
set output_dir "./build_out"
file delete -force $output_dir
file mkdir $output_dir
file mkdir $output_dir/ip

# Set the target FPGA part for the ZedBoard
set_part xc7z020clg484-1

# --- 1. Read Design Sources (VHDL 2008 for ieee.fixed_pkg) ---
read_vhdl -vhdl2008 ./include/params_pkg.vhd

read_vhdl -vhdl2008 ./srcs/RayGenerator/invsqrt.vhd
read_vhdl -vhdl2008 ./srcs/RayGenerator/raygen.vhd
read_vhdl -vhdl2008 ./srcs/Raymarcher/raymarch.vhd
read_vhdl -vhdl2008 ./srcs/Shaders/shader.vhd
read_vhdl -vhdl2008 ./srcs/VGA/vga_controller.vhd
read_vhdl -vhdl2008 ./srcs/Top/debouncer.vhd
read_vhdl -vhdl2008 ./srcs/Top/camera_controller.vhd
read_vhdl -vhdl2008 ./srcs/Top/framebuffer.vhd
read_vhdl -vhdl2008 ./srcs/Top/render_controller.vhd
read_vhdl -vhdl2008 ./srcs/Top/top.vhd

# --- 2. Read Constraints ---
read_xdc ./constraints/zedboard.xdc

# --- 3. In-Memory IP Generation (Clock Wizard: 100 MHz → 25 MHz) ---
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
    -module_name clk_wiz_0 -dir $output_dir/ip

set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] [get_ips clk_wiz_0]

# Synthesize the IP Out-Of-Context
generate_target {synthesis} [get_ips clk_wiz_0]
synth_ip [get_ips clk_wiz_0]

# --- 4. Top-Level Synthesis ---
synth_design -top top -part xc7z020clg484-1
write_checkpoint -force $output_dir/post_synth.dcp
report_utilization -file $output_dir/utilization_synth.txt

# --- 5. Implementation ---
opt_design
place_design
route_design

# --- 6. Reports ---
report_utilization -file $output_dir/utilization_impl.txt
report_timing_summary -file $output_dir/timing_summary.txt

# --- 7. Bitstream ---
write_bitstream -force $output_dir/raymarcher.bit

puts "\n══════════════════════════════════════════════"
puts "Build complete!"
puts "Bitstream: $output_dir/raymarcher.bit"
puts "Reports:   $output_dir/utilization_impl.txt"
puts "           $output_dir/timing_summary.txt"
puts "══════════════════════════════════════════════"