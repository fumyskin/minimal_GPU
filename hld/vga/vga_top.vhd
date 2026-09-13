-- Step-1 board bring-up: eight vertical colour bars on the VGA output.
-- Proves the 100 MHz clock, the /4 pixel enable, the timing generator, the
-- .xdc pin mapping and the physical VGA connector -- with no compute logic.
-- Once this shows on a monitor, the board-level risk is retired.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_top is
  port (
    clk_100 : in  std_logic;                    -- Zedboard 100 MHz oscillator
    rst     : in  std_logic;
    vga_hs  : out std_logic;
    vga_vs  : out std_logic;
    vga_r   : out std_logic_vector(3 downto 0); -- Zedboard VGA is 4 bits/channel
    vga_g   : out std_logic_vector(3 downto 0);
    vga_b   : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of vga_top is
  signal ce_cnt   : unsigned(1 downto 0) := (others => '0');
  signal pix_ce   : std_logic;
  signal video_on : std_logic;
  signal hs, vs   : std_logic;
  signal px, py   : unsigned(9 downto 0);
  signal bar      : integer range 0 to 7;
begin
  -- 25 MHz pixel enable = 100 MHz / 4
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if rst = '1' then
        ce_cnt <= (others => '0');
      else
        ce_cnt <= ce_cnt + 1;
      end if;
    end if;
  end process;
  pix_ce <= '1' when ce_cnt = 3 else '0';

  u_timing : entity work.vga_timing
    port map (
      clk => clk_100, rst => rst, pix_ce => pix_ce,
      hsync => hs, vsync => vs, video_on => video_on,
      px => px, py => py, frame_start => open
    );

  bar <= to_integer(px) / 80;   -- 640 / 8 = 80 px per bar (test pattern only)

  -- Register sync + colour on the pixel enable for a glitch-free output.
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if pix_ce = '1' then
        vga_hs <= hs;
        vga_vs <= vs;
        if video_on = '0' then
          vga_r <= (others => '0');
          vga_g <= (others => '0');
          vga_b <= (others => '0');
        else
          case bar is
            when 0      => vga_r <= "1111"; vga_g <= "1111"; vga_b <= "1111"; -- white
            when 1      => vga_r <= "1111"; vga_g <= "1111"; vga_b <= "0000"; -- yellow
            when 2      => vga_r <= "0000"; vga_g <= "1111"; vga_b <= "1111"; -- cyan
            when 3      => vga_r <= "0000"; vga_g <= "1111"; vga_b <= "0000"; -- green
            when 4      => vga_r <= "1111"; vga_g <= "0000"; vga_b <= "1111"; -- magenta
            when 5      => vga_r <= "1111"; vga_g <= "0000"; vga_b <= "0000"; -- red
            when 6      => vga_r <= "0000"; vga_g <= "0000"; vga_b <= "1111"; -- blue
            when others => vga_r <= "0000"; vga_g <= "0000"; vga_b <= "0000"; -- black
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;