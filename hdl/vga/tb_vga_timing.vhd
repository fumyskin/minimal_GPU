-- Self-checking testbench for vga_timing.
-- Counts, over exactly one frame, the total pixels, visible pixels, and the
-- number of pixel-times HSYNC/VSYNC spend low, then asserts them against the
-- VESA 640x480@60 spec. Run with GHDL or Vivado xsim:
--   ghdl -a rtl/vga_timing.vhd sim/tb_vga_timing.vhd
--   ghdl -e tb_vga_timing && ghdl -r tb_vga_timing

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga_timing is
end entity;

architecture sim of tb_vga_timing is
  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal pix_ce      : std_logic := '0';
  signal ce_cnt      : unsigned(1 downto 0) := (others => '0');
  signal hsync,vsync : std_logic;
  signal video_on    : std_logic;
  signal frame_start : std_logic;
  signal px, py      : unsigned(9 downto 0);
begin
  clk <= not clk after 5 ns;  -- 100 MHz

  process (clk)
  begin
    if rising_edge(clk) and rst = '0' then
      ce_cnt <= ce_cnt + 1;
    end if;
  end process;
  pix_ce <= '1' when (ce_cnt = 3 and rst = '0') else '0';

  dut : entity work.vga_timing
    port map (clk => clk, rst => rst, pix_ce => pix_ce,
              hsync => hsync, vsync => vsync, video_on => video_on,
              px => px, py => py, frame_start => frame_start);

  process
    variable total, active, hs_low, vs_low : integer := 0;
    procedure tally is
    begin
      total := total + 1;
      if video_on = '1' then active := active + 1; end if;
      if hsync = '0'    then hs_low := hs_low + 1; end if;
      if vsync = '0'    then vs_low := vs_low + 1; end if;
    end procedure;
  begin
    wait for 100 ns;
    rst <= '0';
    -- align to the first pixel (0,0) of a frame, count it
    wait until rising_edge(clk) and frame_start = '1';
    tally;
    -- count the rest of the frame until the next (0,0)
    loop
      wait until rising_edge(clk) and pix_ce = '1';
      exit when frame_start = '1';
      tally;
    end loop;

    assert total  = 800 * 525 report "total pixels wrong"   severity failure;
    assert active = 640 * 480 report "visible pixels wrong"  severity failure;
    assert hs_low = 96 * 525  report "hsync low count wrong" severity failure;
    assert vs_low = 2 * 800   report "vsync low count wrong" severity failure;
    report "VGA timing checks PASSED (total/visible/hsync/vsync all match spec)"
      severity note;
    wait;
  end process;
end architecture;