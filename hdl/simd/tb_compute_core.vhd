-- Self-checking testbench for compute_core.
-- Loads imem.mem (one divergent strip, FB_BASE=0), launches the kernel, captures
-- the framebuffer writes, and asserts them against core_expected.mem ([7,9,12,10]).
-- Run (VHDL-2008):
--   ghdl -a --std=08 hdl/core/alu.vhd hdl/core/compute_core.vhd sim/tb_compute_core.vhd
--   ghdl -e --std=08 tb_compute_core && ghdl -r --std=08 tb_compute_core

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_compute_core is
end entity;

architecture sim of tb_compute_core is
  constant N : integer := 4;
  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal start   : std_logic := '0';
  signal done    : std_logic;
  signal fb_we   : std_logic;
  signal fb_addr : unsigned(21 downto 0);
  signal fb_data : std_logic_vector(7 downto 0);

  type cap_t is array(0 to N - 1) of integer;
  signal captured : cap_t := (others => -1);
begin
  clk <= not clk after 5 ns;   -- 100 MHz

  dut : entity work.compute_core
    generic map (N => N, INIT_FILE => "data/imem.mem")
    port map (clk => clk, rst => rst, start => start, done => done,
              fb_we => fb_we, fb_addr => fb_addr, fb_data => fb_data);

  -- capture framebuffer writes (addresses 0..N-1 in this test)
  process (clk)
  begin
    if rising_edge(clk) and fb_we = '1' then
      if to_integer(fb_addr) <= N - 1 then
        captured(to_integer(fb_addr)) <= to_integer(unsigned(fb_data));
      end if;
    end if;
  end process;

  process
    file     f   : text open read_mode is "data/core_expected.mem";
    variable l   : line;
    variable exp : integer;
    variable errs : integer := 0;
  begin
    wait for 50 ns;
    rst <= '0';
    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- wait for HALT (with a generous timeout)
    for t in 0 to 2000000 loop
      wait until rising_edge(clk);
      exit when done = '1';
    end loop;
    assert done = '1' report "core never reached HALT" severity failure;
    wait until rising_edge(clk);   -- let the last capture settle

    for k in 0 to N - 1 loop
      readline(f, l);
      read(l, exp);
      assert captured(k) = exp
        report "lane " & integer'image(k) & " fb=" & integer'image(captured(k))
             & " expected " & integer'image(exp) severity error;
      if captured(k) /= exp then errs := errs + 1; end if;
    end loop;

    if errs = 0 then
      report "compute_core PASSED: framebuffer [7,9,12,10] matches the simulator"
        severity note;
    else
      report integer'image(errs) & " lane mismatch(es)" severity failure;
    end if;
    wait;
  end process;
end architecture;