-- Framebuffer: simple dual-port BRAM, 19200 x 8 (160x120, 8 bpp).
--   write port (we/waddr/wdata) -- idle during preloaded bring-up, driven by
--                                   the compute core's STORE path at integration
--   read  port (rce/raddr/rdata) -- the scan-out, synchronous (1-cycle latency)
-- Both ports are on the same clock (single-clock design), so there is no
-- clock-domain crossing. Initialized from a decimal .mem (one value per line),
-- which Vivado reads during synthesis -- add fb_160.mem to the project sources.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity framebuffer is
  generic (
    DATA_W    : integer := 8;
    DEPTH     : integer := 19200;        -- 160*120
    ADDR_W    : integer := 15;           -- ceil(log2(19200)) = 15
    INIT_FILE : string  := "fb_160.mem"
  );
  port (
    clk   : in  std_logic;
    -- write port (compute core side)
    we    : in  std_logic;
    waddr : in  unsigned(ADDR_W - 1 downto 0);
    wdata : in  std_logic_vector(DATA_W - 1 downto 0);
    -- read port (scan-out side)
    rce   : in  std_logic;               -- read enable = pixel enable
    raddr : in  unsigned(ADDR_W - 1 downto 0);
    rdata : out std_logic_vector(DATA_W - 1 downto 0)
  );
end entity;

architecture rtl of framebuffer is
  type mem_t is array(0 to DEPTH - 1) of std_logic_vector(DATA_W - 1 downto 0);

  impure function init_from_file(fn : string) return mem_t is
    file     f : text open read_mode is fn;
    variable l : line;
    variable v : integer;
    variable m : mem_t := (others => (others => '0'));
  begin
    for i in 0 to DEPTH - 1 loop
      exit when endfile(f);
      readline(f, l);
      read(l, v);
      m(i) := std_logic_vector(to_unsigned(v, DATA_W));
    end loop;
    return m;
  end function;

  signal mem : mem_t := init_from_file(INIT_FILE);
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        mem(to_integer(waddr)) <= wdata;
      end if;
      if rce = '1' then
        rdata <= mem(to_integer(raddr));     -- synchronous read, 1-cycle latency
      end if;
    end if;
  end process;
end architecture;