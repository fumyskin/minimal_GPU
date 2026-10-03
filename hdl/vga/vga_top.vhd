-- Step-1 board bring-up: eight vertical colour bars on the VGA output.
-- Proves the 100 MHz clock, the /4 pixel enable, the timing generator, the
-- .xdc pin mapping and the physical VGA connector -- with no compute logic.
-- Once this shows on a monitor, the board-level risk is retired.

-- Step-2 bring-up: display the preloaded framebuffer on VGA.
-- Pipeline (all advanced by the 25 MHz pixel enable):
--   tick n   : timing gen -> px, py, hs, vs, von ; raddr = (py>>2)*160 + (px>>2)
--   tick n+1 : framebuffer returns the pixel (1-cycle BRAM read);
--              hs/vs/von delayed one tick to stay aligned with it
--   tick n+2 : palette (combinational) -> RGB; outputs registered, all aligned
-- The whole frame is delayed a uniform 2 pixels (invisible); sync and colour
-- stay mutually aligned, which is what prevents edge tearing.
-- Same ports / same .xdc as vga_top -- just set this as the top module.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_fb_top is
  generic (
    FB_W : integer := 160                 -- framebuffer width (for the row stride)
  );
  port (
    clk_100 : in  std_logic;
    rst     : in  std_logic;
    vga_hs  : out std_logic;
    vga_vs  : out std_logic;
    vga_r   : out std_logic_vector(3 downto 0);
    vga_g   : out std_logic_vector(3 downto 0);
    vga_b   : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of vga_fb_top is
  signal ce_cnt            : unsigned(1 downto 0) := (others => '0');
  signal pix_ce            : std_logic;
  signal hs, vs, von       : std_logic;
  signal px, py            : unsigned(9 downto 0);
  signal raddr             : unsigned(14 downto 0);
  signal fb_data           : std_logic_vector(7 downto 0);
  signal hs_d, vs_d, von_d : std_logic;
  signal rgb               : std_logic_vector(11 downto 0);
begin
  -- 25 MHz pixel enable = 100 MHz / 4
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if rst = '1' then ce_cnt <= (others => '0'); else ce_cnt <= ce_cnt + 1; end if;
    end if;
  end process;
  pix_ce <= '1' when ce_cnt = 3 else '0';

  u_timing : entity work.vga_timing
    port map (clk => clk_100, rst => rst, pix_ce => pix_ce,
              hsync => hs, vsync => vs, video_on => von,
              px => px, py => py, frame_start => open);

  -- 4x upscale: divide by 4 is a right-shift by 2 (power of two). Row stride FB_W.
  raddr <= to_unsigned(to_integer(shift_right(py, 2)) * FB_W
                       + to_integer(shift_right(px, 2)), 15);

  u_fb : entity work.framebuffer
    generic map (DATA_W => 8, DEPTH => 19200, ADDR_W => 15, INIT_FILE => "C:/fpga/minimal_GPU/data/fb_160.mem")
    port map (clk => clk_100,
              we => '0', waddr => (others => '0'), wdata => (others => '0'),
              rce => pix_ce, raddr => raddr, rdata => fb_data);

  -- delay control signals one tick to match the BRAM read latency
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if pix_ce = '1' then
        hs_d <= hs; vs_d <= vs; von_d <= von;
      end if;
    end if;
  end process;

  u_pal : entity work.palette_rom
    port map (index => fb_data, rgb => rgb);

  -- registered, aligned VGA outputs
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if pix_ce = '1' then
        vga_hs <= hs_d;
        vga_vs <= vs_d;
        if von_d = '1' then
          vga_r <= rgb(11 downto 8);
          vga_g <= rgb(7 downto 4);
          vga_b <= rgb(3 downto 0);
        else
          vga_r <= (others => '0');
          vga_g <= (others => '0');
          vga_b <= (others => '0');
        end if;
      end if;
    end if;
  end process;
end architecture;