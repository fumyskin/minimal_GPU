#=============================================================================
# build_project.tcl -- recreate the minimal_GPU Vivado project from sources.
#
# Run it one of two ways:
#   (a) batch, from a terminal in the repo root:
#         vivado -mode batch -source build_project.tcl
#   (b) GUI Tcl console:
#         cd <repo root> ; source build_project.tcl
#
# Edit the SETTINGS and the source lists below to match your folder layout.
#=============================================================================

# ---------- SETTINGS ----------------------------------------------------------
set proj_name  "minimal_GPU"
set part       "xc7z020clg484-1"            ;# Zedboard
set origin_dir [file normalize [file dirname [info script]]]   ;# this script's folder
set proj_dir   "$origin_dir/vivado"         ;# project is created here

# ---------- SOURCE FILES (edit paths to match your repo) ----------------------
# Order does not matter; update_compile_order sorts out dependencies.
set hdl_files [list \
  "$origin_dir/hdl/core/alu.vhd" \
  "$origin_dir/hdl/core/compute_core.vhd" \
  "$origin_dir/hdl/core/strip_sequencer.vhd" \
  "$origin_dir/hdl/core/debouncer.vhd" \
  "$origin_dir/hdl/vga/framebuffer.vhd" \
  "$origin_dir/hdl/vga/palette_rom.vhd" \
  "$origin_dir/hdl/vga/vga_timing.vhd" \
  "$origin_dir/hdl/mandelbrot_top.vhd" \
]

set mem_files [list \
  "$origin_dir/data/imem_template.mem" \
  "$origin_dir/data/fb_zeros.mem" \
  "$origin_dir/data/palette.mem" \
]

set xdc_file "$origin_dir/xdc/zedboard.xdc"

# ---------- (RE)CREATE PROJECT ------------------------------------------------
create_project $proj_name $proj_dir -part $part -force

# ---------- ADD SOURCES -------------------------------------------------------
add_files -norecurse $hdl_files
add_files -norecurse $mem_files
set_property file_type {Memory Initialization Files} [get_files *.mem]

add_files -fileset constrs_1 -norecurse $xdc_file

# ---------- TOP + COMPILE ORDER ----------------------------------------------
set_property top mandelbrot_top [current_fileset]
update_compile_order -fileset sources_1

# ---------- MAKE THE .mem FILES RESOLVE DURING SYNTHESIS ----------------------
# The RTL opens the .mem files by bare name (INIT_FILE => "imem_template.mem").
# Vivado runs synthesis from its own run directory, so a pre-synthesis hook
# stages the three files there -- portable, no absolute paths in the RTL.
set hook "$origin_dir/_copy_mems.tcl"
set fh [open $hook w]
puts $fh "foreach f {imem_template.mem fb_zeros.mem palette.mem} {"
puts $fh "  file copy -force \"$origin_dir/data/\$f\" \[pwd\]"
puts $fh "}"
close $fh
set_property STEPS.SYNTH_DESIGN.TCL.PRE $hook [get_runs synth_1]

puts "=============================================================="
puts " Project '$proj_name' created at: $proj_dir"
puts " Part: $part    Top: mandelbrot_top"
puts " To build:  launch_runs impl_1 -to_step write_bitstream ; wait_on_run impl_1"
puts "=============================================================="

# ---------- OPTIONAL: build all the way to a bitstream ------------------------
# Uncomment to synthesize, implement, and write the bitstream in one go:
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1
# puts "Bitstream: [glob -nocomplain $proj_dir/${proj_name}.runs/impl_1/*.bit]"