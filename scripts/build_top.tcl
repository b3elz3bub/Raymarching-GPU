# ==============================================================================
# build_top.tcl — Full synthesis + implementation of the top module
#
# Usage: vivado -mode batch -source scripts/build_top.tcl
#   Or:  source scripts/build_top.tcl   (from Vivado TCL console)
#
# Target: Artix-7 (xc7a35tcpg236-1) — change -part as needed
# ==============================================================================

set proj_dir [file dirname [file dirname [file normalize [info script]]]]
set out_dir  "$proj_dir/output"
file mkdir $out_dir

# ──────────────────────────────────────────────────────────
# Create project
# ──────────────────────────────────────────────────────────
create_project raymarcher_build "$out_dir/build" -part xc7a35tcpg236-1 -force

# ──────────────────────────────────────────────────────────
# Add all source files
# ──────────────────────────────────────────────────────────
add_files -fileset sources_1 [list \
    "$proj_dir/include/params_pkg.vhd" \
    "$proj_dir/srcs/RayGenerator/invsqrt.vhd" \
    "$proj_dir/srcs/RayGenerator/raygen.vhd" \
    "$proj_dir/srcs/Raymarcher/raymarch.vhd" \
    "$proj_dir/srcs/Shaders/shader.vhd" \
    "$proj_dir/srcs/VGA/vga_controller.vhd" \
    "$proj_dir/srcs/Top/debouncer.vhd" \
    "$proj_dir/srcs/Top/camera_controller.vhd" \
    "$proj_dir/srcs/Top/framebuffer.vhd" \
    "$proj_dir/srcs/Top/render_controller.vhd" \
    "$proj_dir/srcs/Top/top.vhd" \
]

# Set all to VHDL 2008
set_property file_type {VHDL 2008} [get_files *.vhd]

# Add constraints (if any exist)
set xdc_files [glob -nocomplain "$proj_dir/constraints/*.xdc"]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
}

# ──────────────────────────────────────────────────────────
# Set top module
# ──────────────────────────────────────────────────────────
set_property top top [current_fileset]

# ──────────────────────────────────────────────────────────
# Synthesize
# ──────────────────────────────────────────────────────────
puts "\n══════════════════════════════════════════════"
puts "Running Synthesis..."
puts "══════════════════════════════════════════════"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    puts "SYNTHESIS FAILED"
    puts [get_property STATUS [get_runs synth_1]]
    exit 1
}
puts "Synthesis complete!"

# ──────────────────────────────────────────────────────────
# Report utilization
# ──────────────────────────────────────────────────────────
open_run synth_1
report_utilization -file "$out_dir/utilization_report.txt"
report_timing_summary -file "$out_dir/timing_report.txt"

puts "\n══════════════════════════════════════════════"
puts "Reports saved to: $out_dir/"
puts "  - utilization_report.txt"
puts "  - timing_report.txt"
puts "══════════════════════════════════════════════"

close_project
