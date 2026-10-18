library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- draft of alu for minimal_gpu

entity alu is
    generic(
        W: integer := 18;
        F: integer := 14
    );
    port(
        a: in signed(W-1 downto 0);  -- use signed to make sure you can use resize() functions
        b: in signed(W-1 downto 0);  -- this way the compiler knows they are bit that are to be interpreted as numbers
        op_add: in std_logic;
        op_sub: in std_logic;
        op_mul: in std_logic;
        result: out signed(W-1 downto 0);
        gt: out std_logic
    );
end entity;

architecture rtl of alu is
    constant MAXV: integer := 2**(W-1) -1; -- base**exponent (simbolo dell'esponente)
    constant MINV: integer := -(2**(W-1));

    function sat(v: signed) return signed is
    begin 
        if v>MAXV then
            return to_signed(MAXV, W); -- convert from integer to signed
        elsif v<MINV then
            return to_signed(MINV, W);
        else 
            return resize(v, W);  -- pads if v too short, cuts if v too long (truncating msb)
        end if;
    end function;
begin 
    process (a, b, op_add, op_sub, op_mul)
        variable sum : signed(W downto 0); -- why W+1 in size ? guard bit?
        variable dif : signed(W downto 0);
        variable prod: signed(2*W -1 downto 0); -- 18*2 length
        variable shf: signed(2*W - 1 downto 0);
    begin
        -- se abbiamo op_add -> a + b
        -- se abbiamo op_sub -> a - b
        -- se abbiamo op_mul -> a*b però resized quindi tip sat(a*b)
        sum := resize(a, W+1) + resize(b, W + 1);  --guard bit here too?
        dif := resize(a, W+1) - resize(b, W+1);
        prod := a*b;
        shf := shift_right(prod, F);

        if op_mul = '1' then
            result <= sat(shf);
        elsif op_sub = '1' then
            result <= sat(dif);
        else
            result <= sat(sum);
        end if;
    end process;

    gt <='1' when a>b else '0';

end architecture;