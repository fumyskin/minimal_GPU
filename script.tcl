# this is the sample to study and correctly use TCL scripting for the project

# 1. Create the project and set the FPGA part
create_project my_project ./vivado_proj -part xc7a35tcpg236-1 -force

# 2. Add source files and constraints
add_files ./src/top_level.v
add_files ./src/alu.v
add_files ./constraints/pins.xdc

# 3. Run Synthesis
synth_design -top top_level -part xc7a35tcpg236-1

# 4. Run Implementation (Place and Route)
place_design
route_design

# 5. Generate Reports
report_timing_summary -file ./reports/timing.txt
report_utilization -file ./reports/utilization.txt

# 6. Generate the Bitstream to program the board
write_bitstream -force ./output/my_project.bit