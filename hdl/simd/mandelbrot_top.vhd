-- Top level: the whole GPU. The strip sequencer drives the SIMD core to render
-- the full 160x120 image into the framebuffer; the VGA scan-out (5->4x upscale
-- via >>2) displays it continuously. Single 100 MHz clock + /4 pixel enable, so
-- the dual-port framebuffer is the only crossing (write=core, read=scan-out) and
-- needs no arbitration. One static render after reset; no double buffer needed.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mandelbrot_top is
  generic (
    FB_W : integer := 160;
    N    : integer := 4
  );
  port (
    clk_100 : in  std_logic;
    rst     : in  std_logic;
    vga_hs  : out std_logic;
    vga_vs  : out std_logic;
    vga_r   : out std_logic_vector(3 downto 0);
    vga_g   : out std_logic_vector(3 downto 0);
    vga_b   : out std_logic_vector(3 downto 0);
    done_led : out std_logic              -- lights when the render is complete
  );
end entity;

architecture rtl of mandelbrot_top is
  signal ce_cnt            : unsigned(1 downto 0) := (others => '0');
  signal pix_ce            : std_logic;

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
begin
  -- 25 MHz pixel enable = 100 MHz / 4
  process (clk_100)
  begin
    if rising_edge(clk_100) then
      if rst = '1' then ce_cnt <= (others => '0'); else ce_cnt <= ce_cnt + 1; end if;
    end if;
  end process;
  pix_ce <= '1' when ce_cnt = 3 else '0';

  ---------------------------------------------------------------- compute side
  u_seq : entity work.strip_sequencer
    generic map (N => N, IMG_W => FB_W, IMG_H => 120,
                 X0 => -40960, Y0 => -21504, DXF => 358, DYF => 358, DXN => 1432,
                 P_CX0 => 2, P_CY0 => 6, P_FB => 26)
    port map (clk => clk_100, rst => rst,
              core_done => core_done, core_start => core_start,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata,
              rendering_done => done_led);

  u_core : entity work.compute_core
    generic map (N => N, INIT_FILE => "imem_template.mem")
    port map (clk => clk_100, rst => rst, start => core_start, done => core_done,
              fb_we => core_fb_we, fb_addr => core_fb_addr, fb_data => core_fb_data,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata);

  ---------------------------------------------------------------- framebuffer (dual port)
  u_fb : entity work.framebuffer
    generic map (DATA_W => 8, DEPTH => FB_W * 120, ADDR_W => 15,
                 INIT_FILE => "fb_zeros.mem")
    port map (clk => clk_100,
              we    => core_fb_we,
              waddr => core_fb_addr(14 downto 0),
              wdata => core_fb_data,
              rce   => pix_ce,
              raddr => raddr,
              rdata => fb_rdata);

  ---------------------------------------------------------------- VGA scan-out
  u_timing : entity work.vga_timing
    port map (clk => clk_100, rst => rst, pix_ce => pix_ce,
              hsync => hs, vsync => vs, video_on => von,
              px => px, py => py, frame_start => open);

  -- 4x upscale: framebuffer pixel (px>>2, py>>2), row stride FB_W
  raddr <= to_unsigned(to_integer(shift_right(py, 2)) * FB_W
                       + to_integer(shift_right(px, 2)), 15);

  process (clk_100)                         -- match 1-cycle BRAM read latency
  begin
    if rising_edge(clk_100) then
      if pix_ce = '1' then
        hs_d <= hs; vs_d <= vs; von_d <= von;
      end if;
    end if;
  end process;

  u_pal : entity work.palette_rom
    port map (index => fb_rdata, rgb => rgb);

  process (clk_100)                         -- registered, aligned VGA outputs
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