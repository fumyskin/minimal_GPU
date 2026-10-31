-- Pushbutton debouncer + single-cycle press pulse.
-- Two-FF synchronizer, then requires the input to hold steady for STABLE cycles
-- before accepting a new level; emits a one-cycle pulse on each clean 0->1 press.
-- At 100 MHz, STABLE = 1_000_000 is ~10 ms (well above mechanical bounce).

library ieee;
use ieee.std_logic_1164.all;

entity debouncer is
  generic (STABLE : integer := 1000000);
  port (
    clk   : in  std_logic;
    din   : in  std_logic;
    pulse : out std_logic            -- 1-cycle pulse on a debounced press
  );
end entity;

architecture rtl of debouncer is
  signal s0, s1 : std_logic := '0';
  signal level  : std_logic := '0';
  signal cnt    : integer range 0 to STABLE := 0;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      s0 <= din; s1 <= s0;           -- synchronize to clk
      pulse <= '0';
      if s1 = level then
        cnt <= 0;                    -- stable at current level
      else
        if cnt = STABLE - 1 then
          level <= s1;               -- accept the new, debounced level
          cnt <= 0;
          if s1 = '1' then
            pulse <= '1';            -- fire on press (0 -> 1)
          end if;
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;