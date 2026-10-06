-- Integration testbench: strip_sequencer + compute_core + framebuffer rendering
-- a divergent 8x8 window. Waits for the sequencer to finish, then reads back the
-- framebuffer and checks all 64 pixels against golden_small.mem ([..31..40..100]).
-- Proves patching, the start/done handshake, strip/row advance, and FB addressing.
--
-- Run from the project root (files opened relative to CWD):
--   ghdl -a hdl/core/alu.vhd hdl/core/compute_core.vhd hdl/core/strip_sequencer.vhd \
--           hdl/vga/framebuffer.vhd sim/tb_integration.vhd
--   ghdl -e tb_integration && ghdl -r tb_integration

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_integration is
end entity;

architecture sim of tb_integration is
  constant N  : integer := 4;
  constant SW : integer := 8;
  constant SH : integer := 8;

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';

  signal core_start, core_done     : std_logic;
  signal imem_we                   : std_logic;
  signal imem_waddr                : natural;
  signal imem_wdata                : std_logic_vector(31 downto 0);
  signal rendering_done            : std_logic;

  signal fb_we                     : std_logic;
  signal fb_addr                   : unsigned(21 downto 0);
  signal fb_data                   : std_logic_vector(7 downto 0);

  signal raddr                     : unsigned(14 downto 0) := (others => '0');
  signal fb_rdata                  : std_logic_vector(7 downto 0);
begin
  clk <= not clk after 5 ns;

  u_seq : entity work.strip_sequencer
    generic map (N => N, IMG_W => SW, IMG_H => SH,
                 X0 => -13107, Y0 => -1638, DXF => 358, DYF => 358, DXN => 1432,
                 P_CX0 => 2, P_CY0 => 6, P_FB => 26)
    port map (clk => clk, rst => rst, core_done => core_done, core_start => core_start,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata,
              rendering_done => rendering_done);

  u_core : entity work.compute_core
    generic map (N => N, INIT_FILE => "data/imem_template.mem")
    port map (clk => clk, rst => rst, start => core_start, done => core_done,
              fb_we => fb_we, fb_addr => fb_addr, fb_data => fb_data,
              imem_we => imem_we, imem_waddr => imem_waddr, imem_wdata => imem_wdata);

  u_fb : entity work.framebuffer
    generic map (DATA_W => 8, DEPTH => SW * SH, ADDR_W => 15,
                 INIT_FILE => "data/fb_zeros.mem")
    port map (clk => clk, we => fb_we, waddr => fb_addr(14 downto 0), wdata => fb_data,
              rce => '1', raddr => raddr, rdata => fb_rdata);

  process
    file     g    : text open read_mode is "data/golden_small.mem";
    variable l    : line;
    variable exp  : integer;
    variable errs : integer := 0;
  begin
    wait for 50 ns;
    rst <= '0';

    -- wait for the full render (bounded)
    for t in 0 to 5000000 loop
      wait until rising_edge(clk);
      exit when rendering_done = '1';
    end loop;
    assert rendering_done = '1' report "render never completed" severity failure;

    -- read back the framebuffer (synchronous read: allow 2 edges of latency)
    for k in 0 to SW * SH - 1 loop
      raddr <= to_unsigned(k, 15);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      readline(g, l);
      read(l, exp);
      assert to_integer(unsigned(fb_rdata)) = exp
        report "pixel " & integer'image(k) & " = " & integer'image(to_integer(unsigned(fb_rdata)))
             & " expected " & integer'image(exp) severity error;
      if to_integer(unsigned(fb_rdata)) /= exp then errs := errs + 1; end if;
    end loop;

    if errs = 0 then
      report "integration PASSED: 8x8 render matches the golden model" severity note;
    else
      report integer'image(errs) & " pixel mismatch(es)" severity failure;
    end if;
    wait;
  end process;
end architecture;