-- Top level: the whole GPU, running on a single 25 MHz clock divided from the
-- 100 MHz board oscillator. The display already produced 25 MHz pixels via a /4
-- enable, so VGA output is unchanged -- but the compute core now gets 40 ns per
-- cycle instead of 10 ns, so its long fetch->imem->regread->multiply->saturate
-- ->writeback path closes with large margin. No datapath changes: image is
-- bit-identical, render just takes ~4x longer (~240 ms, imperceptible).
--
-- 25 MHz is exactly the pixel rate, so pix_ce is tied high (every cycle = pixel).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;

entity mandelbrot_top is
  generic (
    FB_W : integer := 160;
    N    : integer := 4
  );
  port (
    clk_100       : in  std_logic;        -- 100 MHz board oscillator (Y9)
    rst           : in  std_logic;
    btn_zoom_in   : in  std_logic;
    btn_zoom_reset: in  std_logic;
    vga_hs  : out std_logic;
    vga_vs  : out std_logic;
    vga_r   : out std_logic_vector(3 downto 0);
    vga_g   : out std_logic_vector(3 downto 0);
    vga_b   : out std_logic_vector(3 downto 0);
    done_led : out std_logic
  );
end entity;

architecture rtl of mandelbrot_top is
  -- clock divider 100 -> 25 MHz
  signal div   : unsigned(1 downto 0) := (others => '0');
  signal clk   : std_logic;                 -- 25 MHz system clock (everything runs here)
  constant pix_ce : std_logic := '1';       -- every 25 MHz cycle is a pixel

  -- VGA timing / scan-out
  signal hs, vs, von       : std_logic;
  signal px, py            : unsigned(9 downto 0);
  signal raddr             : unsigned(14 downto 0);
  signal fb_rdata          : std_logic_vector(7 downto 0);
  signal hs_d, vs_d, von_d : std_logic;
  signal rgb               : std_logic_vector(11 downto 0);

  -- compute core <-> framebuffer write
  signal core_fb_we        : std_logic;
  signal core_fb_addr      : unsigned(21 downto 0);
  signal core_fb_data      : std_logic_vector(7 downto 0);

  -- sequencer <-> core
  signal core_start, core_done : std_logic;
  signal imem_we           : std_logic;
  signal imem_waddr        : natural;
  signal imem_wdata        : std_logic_vector(31 downto 0);

  -- debounced zoom pulses
  signal zoom_in_p, zoom_reset_p : std_logic;
begin
  ---------------------------------------------------------------- clock: 100 -> 25 MHz
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      div <= div + 1;                       -- div(1) is a 25 MHz, 50%-duty clock
    end if;
  end process;
  u_clkbuf : BUFG port map (I => div(1), O => clk);   -- route it on a global buffer

  ---------------------------------------------------------------- zoom buttons
  u_db_in : entity work.debouncer
    port map (clk => clk, din => btn_zoom_in, pulse => zoom_in_p);
  u_db_rst : entity work.debouncer
    port map (clk => clk, din => btn_zoom_reset, pulse => zoom_reset_p);

  ---------------------------------------------------------------- compute side
  u_seq : entity work.strip_sequencer
    generic map (N => N, IMG_W => FB_W, IMG_H => 120,
                 X0 => -40846, Y0 => -19629, DXF => 358, DYF => 358, DXN => 1432,
                 CXC => -12206, CYC => 1851,
                 P_CX0 => 2, P_DX => 3, P_CY0 => 6, P_FB => 26)
    port map (clk => clk, rst => rst,
              core_done => core_done, core_start => core_start,
              zoom_in => zoom_in_p, zoom_reset => zoom_reset_p,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata,
              rendering_done => done_led);

  u_core : entity work.compute_core
    generic map (N => N, INIT_FILE => "C:\fpga\minimal_GPU\data\imem_template.mem")
    port map (clk => clk, rst => rst, start => core_start, done => core_done,
              fb_we => core_fb_we, fb_addr => core_fb_addr, fb_data => core_fb_data,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata);

  ---------------------------------------------------------------- framebuffer (dual port, one clock)
  u_fb : entity work.framebuffer
    generic map (DATA_W => 8, DEPTH => FB_W * 120, ADDR_W => 15,
                 INIT_FILE => "C:\fpga\minimal_GPU\data\fb_zeros.mem")
    port map (clk => clk,
              we    => core_fb_we,
              waddr => core_fb_addr(14 downto 0),
              wdata => core_fb_data,
              rce   => pix_ce,
              raddr => raddr,
              rdata => fb_rdata);

  ---------------------------------------------------------------- VGA scan-out
  u_timing : entity work.vga_timing
    port map (clk => clk, rst => rst, pix_ce => pix_ce,
              hsync => hs, vsync => vs, video_on => von,
              px => px, py => py, frame_start => open);

  raddr <= to_unsigned(to_integer(shift_right(py, 2)) * FB_W
                       + to_integer(shift_right(px, 2)), 15);

  process (clk)                             -- match 1-cycle BRAM read latency
  begin
    if rising_edge(clk) then
      hs_d <= hs; vs_d <= vs; von_d <= von;
    end if;
  end process;

  u_pal : entity work.palette_rom
    generic map (INIT_FILE => "C:\fpga\minimal_GPU\data\palette.mem") 
    port map (index => fb_rdata, rgb => rgb);

  process (clk)                             -- registered, aligned VGA outputs
  begin
    if rising_edge(clk) then
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
  end process;
end architecture;