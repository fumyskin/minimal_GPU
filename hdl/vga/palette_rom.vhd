-- Palette ROM: 256 x 12-bit (4-4-4 RGB), combinational read so it adds no
-- latency. 256*12 bits fits comfortably in LUT/distributed ROM. Initialized
-- from palette.mem (one decimal 12-bit value per line) -- add it to the project.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity palette_rom is
  generic (
    INIT_FILE : string := "C:/fpga/minimal_GPU/data/palette.mem"
  );
  port (
    index : in  std_logic_vector(7 downto 0);   -- iteration count from framebuffer
    rgb   : out std_logic_vector(11 downto 0)    -- [11:8]=R [7:4]=G [3:0]=B
  );
end entity;

architecture rtl of palette_rom is
  type rom_t is array(0 to 255) of std_logic_vector(11 downto 0);

  impure function init_from_file(fn : string) return rom_t is
    file     f : text open read_mode is fn;
    variable l : line;
    variable v : integer;
    variable r : rom_t := (others => (others => '0'));
  begin
    for i in 0 to 255 loop
      exit when endfile(f);
      readline(f, l);
      read(l, v);
      r(i) := std_logic_vector(to_unsigned(v, 12));
    end loop;
    return r;
  end function;

  constant ROM : rom_t := init_from_file(INIT_FILE);
begin
  rgb <= ROM(to_integer(unsigned(index)));       -- combinational lookup
end architecture;