# ==============================================================================
# analyze_all.tcl — Vivado syntax analysis for all VHDL source files
#
# Usage: Open Vivado TCL console, then:
#   source scripts/analyze_all.tcl
#
# Or from command line:
#   vivado -mode batch -source scripts/analyze_all.tcl
# ==============================================================================

# Set project root (adjust if running from a different directory)
set proj_dir [file dirname [file dirname [file normalize [info script]]]]
puts "Project root: $proj_dir"

# VHDL-2008 for ieee.fixed_pkg support
set vhdl_ver "VHDL 2008"

# ──────────────────────────────────────────────────────────
# Step 1: Analyze the global package first (everything depends on it)
# ──────────────────────────────────────────────────────────
puts "\n══════════════════════════════════════════════"
puts "Analyzing: params_pkg.vhd"
puts "══════════════════════════════════════════════"
read_vhdl -vhdl2008 "$proj_dir/include/params_pkg.vhd"

# ──────────────────────────────────────────────────────────
# Step 2: Analyze all source files (order matters for dependencies)
# ──────────────────────────────────────────────────────────
set src_files [list \
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

set error_count 0

foreach f $src_files {
    set fname [file tail $f]
    puts "\n──────────────────────────────────────────────"
    puts "Analyzing: $fname"
    puts "──────────────────────────────────────────────"
    if {[catch {read_vhdl -vhdl2008 $f} err]} {
        puts "ERROR in $fname: $err"
        incr error_count
    } else {
        puts "  OK"
    }
}

# ──────────────────────────────────────────────────────────
# Step 3: Run synth_design check (elaboration only, no implementation)
# ──────────────────────────────────────────────────────────
puts "\n══════════════════════════════════════════════"
puts "Running elaboration check (synth_design -rtl)"
puts "══════════════════════════════════════════════"

if {[catch {synth_design -top top -part xc7a35tcpg236-1 -rtl} err]} {
    puts "ELABORATION FAILED: $err"
    incr error_count
} else {
    puts "Elaboration passed!"
}

puts "\n══════════════════════════════════════════════"
if {$error_count > 0} {
    puts "RESULT: $error_count file(s) had errors"
} else {
    puts "RESULT: All files passed analysis"
}
puts "══════════════════════════════════════════════"
