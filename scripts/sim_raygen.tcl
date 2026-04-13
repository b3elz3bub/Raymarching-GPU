# ==============================================================================
# sim_raygen.tcl — Simulate raygen testbench
#
# Usage: vivado -mode batch -source scripts/sim_raygen.tcl
#   Or:  source scripts/sim_raygen.tcl   (from Vivado TCL console)
#
# NOTE: The raygen_tb.vhd testbench may need updating — it was written for
#       the old 'gen' entity with 32-bit generics. You may need to adjust
#       the testbench to match the new 'raygen' entity (18-bit, sfixed ports).
# ==============================================================================

set proj_dir [file dirname [file dirname [file normalize [info script]]]]

create_project -in_memory -part xc7a35tcpg236-1

add_files -fileset sources_1 "$proj_dir/include/params_pkg.vhd"
add_files -fileset sources_1 "$proj_dir/srcs/RayGenerator/invsqrt.vhd"
add_files -fileset sources_1 "$proj_dir/srcs/RayGenerator/raygen.vhd"
add_files -fileset sim_1     "$proj_dir/srcs/Tb/raygen_tb.vhd"

set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top gen_tb [get_filesets sim_1]

launch_simulation -simset sim_1
run 1 us

puts "\n══════════════════════════════════════════════"
puts "raygen simulation complete (1 us)"
puts "Check waveform for direction outputs"
puts "══════════════════════════════════════════════"
