## ZedBoard constraints for vga_top (hdl/vga/vga_top.vhd)
## Part: xc7z020clg484-1

## 100 MHz clock (GCLK, bank 13)
set_property PACKAGE_PIN Y9 [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]
create_clock -period 10.000 -name clk_100 [get_ports clk_100]

## Reset on BTNC (centre push button, bank 34)
## Bank 34 voltage is set by jumper J18 (VADJ). Use LVCMOS18 for 1.8 V,
## LVCMOS25 if J18 is on 2.5 V.
set_property PACKAGE_PIN P16 [get_ports rst]
set_property IOSTANDARD LVCMOS25 [get_ports rst]

## VGA connector (bank 33, 3.3 V)
set_property PACKAGE_PIN V20  [get_ports {vga_r[0]}]
set_property PACKAGE_PIN U20  [get_ports {vga_r[1]}]
set_property PACKAGE_PIN V19  [get_ports {vga_r[2]}]
set_property PACKAGE_PIN V18  [get_ports {vga_r[3]}]

set_property PACKAGE_PIN AB22 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN AA22 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN AB21 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN AA21 [get_ports {vga_g[3]}]

set_property PACKAGE_PIN Y21  [get_ports {vga_b[0]}]
set_property PACKAGE_PIN Y20  [get_ports {vga_b[1]}]
set_property PACKAGE_PIN AB20 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN AB19 [get_ports {vga_b[3]}]

set_property PACKAGE_PIN AA19 [get_ports vga_hs]
set_property PACKAGE_PIN Y19  [get_ports vga_vs]

set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]
