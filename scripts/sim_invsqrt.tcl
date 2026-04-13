# ==============================================================================
# sim_invsqrt.tcl — Simulate invsqrt testbench
#
# Usage: vivado -mode batch -source scripts/sim_invsqrt.tcl
#   Or:  source scripts/sim_invsqrt.tcl   (from Vivado TCL console)
# ==============================================================================

set proj_dir [file dirname [file dirname [file normalize [info script]]]]

# Create sim project in memory
create_project -in_memory -part xc7a35tcpg236-1

# Add sources
add_files -fileset sources_1 "$proj_dir/include/params_pkg.vhd"
add_files -fileset sources_1 "$proj_dir/srcs/RayGenerator/invsqrt.vhd"
add_files -fileset sim_1     "$proj_dir/srcs/Tb/invsqrt_tb.vhd"

# Set all files to VHDL 2008
set_property file_type {VHDL 2008} [get_files *.vhd]

# Set top-level sim entity
set_property top invsqrt_tb [get_filesets sim_1]

# Launch simulation
launch_simulation -simset sim_1
run 500 ns

puts "\n══════════════════════════════════════════════"
puts "invsqrt simulation complete (500 ns)"
puts "Check waveform for ans output values"
puts "══════════════════════════════════════════════"
