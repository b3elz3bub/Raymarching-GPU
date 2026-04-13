# ==============================================================================
# sim_vga.tcl — Simulate VGA controller testbench
#
# Usage: vivado -mode batch -source scripts/sim_vga.tcl
#   Or:  source scripts/sim_vga.tcl   (from Vivado TCL console)
# ==============================================================================

set proj_dir [file dirname [file dirname [file normalize [info script]]]]

create_project -in_memory -part xc7a35tcpg236-1

add_files -fileset sources_1 "$proj_dir/include/params_pkg.vhd"
add_files -fileset sources_1 "$proj_dir/srcs/VGA/vga_controller.vhd"
add_files -fileset sim_1     "$proj_dir/srcs/VGA/tb_vga.vhd"

set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top tb_vga [get_filesets sim_1]

launch_simulation -simset sim_1

# Run for 2 full frames (2 × 525 × 800 × 40ns ≈ 33.6ms)
run 34 ms

puts "\n══════════════════════════════════════════════"
puts "VGA simulation complete (34 ms = ~2 frames)"
puts "Verify: hsync period = 31.78 us, vsync period = 16.68 ms"
puts "══════════════════════════════════════════════"
