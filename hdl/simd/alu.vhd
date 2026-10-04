-- Per-lane ALU, purely combinational. One of these per SIMD lane.
-- Mirrors fixedpoint.py exactly:
--   ADD: sat(a+b)   SUB: sat(a-b)   MUL: sat((a*b) >> 14)   (Q4.14, saturating)
-- Also emits gt = (a > b) signed, used by ESCAPE for the |z|^2 > 4 test.
-- The multiply is an 18x18 signed product -> one DSP48E1; shift_right on a
-- signed value is arithmetic (truncates toward -inf), matching Python's >>.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
  generic (
    W : integer := 18;
    F : integer := 14
  );
  port (
    a      : in  signed(W - 1 downto 0);
    b      : in  signed(W - 1 downto 0);
    op_add : in  std_logic;                 -- select add
    op_sub : in  std_logic;                 -- select sub
    op_mul : in  std_logic;                 -- select mul (else result = add)
    result : out signed(W - 1 downto 0);
    gt     : out std_logic                  -- a > b, signed
  );
end entity;

architecture rtl of alu is
  constant MAXV : integer := 2 ** (W - 1) - 1;   --  131071 for W=18
  constant MINV : integer := -(2 ** (W - 1));    -- -131072

  -- clamp a wider signed value into W bits (saturate)
  function sat(v : signed) return signed is
  begin
    if v > MAXV then
      return to_signed(MAXV, W);
    elsif v < MINV then
      return to_signed(MINV, W);
    else
      return resize(v, W);
    end if;
  end function;
begin
  process (a, b, op_add, op_sub, op_mul)
    variable sum  : signed(W downto 0);              -- 1 guard bit
    variable dif  : signed(W downto 0);
    variable prod : signed(2 * W - 1 downto 0);      -- full 36-bit product
    variable shf  : signed(2 * W - 1 downto 0);
  begin
    sum  := resize(a, W + 1) + resize(b, W + 1);
    dif  := resize(a, W + 1) - resize(b, W + 1);
    prod := a * b;
    shf  := shift_right(prod, F);                    -- arithmetic (toward -inf)

    if op_mul = '1' then
      result <= sat(shf);
    elsif op_sub = '1' then
      result <= sat(dif);
    else                                             -- op_add or default
      result <= sat(sum);
    end if;
  end process;

  gt <= '1' when a > b else '0';
end architecture;