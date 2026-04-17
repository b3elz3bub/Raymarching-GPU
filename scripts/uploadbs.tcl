# ==============================================================================
# uploadbs.tcl — Program ZedBoard with raymarcher bitstream
#
# Usage: vivado -mode batch -source scripts/uploadbs.tcl
#
# Connects to the ZedBoard via JTAG and programs the FPGA.
# The scene renders and displays on VGA immediately after programming.
# ==============================================================================

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices xc7z020_1] 0]
set_property PROGRAM.FILE "./build_out/raymarcher.bit" $dev
program_hw_devices $dev

puts "\n══════════════════════════════════════════════"
puts "ZedBoard programmed successfully!"
puts "Connect VGA monitor — scene should appear."
puts "Use buttons: L/R = move X, U/D = move Z"
puts "══════════════════════════════════════════════"

close_hw_manager