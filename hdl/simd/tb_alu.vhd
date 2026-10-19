library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;   -- uniform() for random tests, floor() for the reference model

-- Self-checking testbench for the minimal_GPU ALU.
-- Idea: drive inputs, wait, compare DUT outputs against an INDEPENDENT
-- reference model (written with real numbers, not the same signed ops as the DUT),
-- count errors, print a PASS/FAIL summary at the end.

entity tb_alu is
end entity;

architecture sim of tb_alu is
    constant W : integer := 18;
    constant F: integer := 14;
    constant MAXV: integer := 2**(W-1) -1;  -- 131071 (~+7.99994)
    constant MINV: integer := -(2**(W-1));  -- -131072 (-8.0)
    constant ONE: integer := 2**F;          -- 16384 (1.0)  this is useful to have for tests


    type op_t is (OP_ADD_T, OP_SUB_T, OP_MUL_T);

    signal a, b : signed(W-1 downto 0) := (others => '0');
    signal op_add, op_sub, op_mul: std_logic := '0';
    signal result: signed(W-1 downto 0);
    signal gt: std_logic;

    -- real() function converts an integer value into a floating-point number 
    -- (the VHDL real type, which simulators typically represent as 
    -- a 64-bit double-precision float).

    -- saturation function
    function sat_ref(x: real) return integer is
    begin
        if x > real(MAXV) then return MAXV;
        elsif x < real(MINV) then return MINV;
        else return integer(x);
        end if;
    end function;


    function model(x, y: integer; op: op_t) return integer is
    begin
        case op is
            when OP_ADD_T => return sat_ref(real(x) + real(y));
            when OP_SUB_T => return sat_ref(real(x) - real(y));
            when OP_MUL_T => return sat_ref(floor(real(x)*real(y)/real(ONE)));
        end case;
    end function;

    -- pretty print
    function q(x: integer) return string is
    begin
        return integer'image(x) & " (" & real'image(real(x)/ real(ONE)) & ")";
    end function;
    

    function op_name(op: op_t) return string is
    begin 
        case op is
            when OP_ADD_T => return "ADD";
            when OP_SUB_T => return "SUB";
            when OP_MUL_T => return "MUL";
        end case;
    end function;
        


begin
    dut: entity work.alu
        generic map( 
            W => W, 
            F => F
        )
        port map(
            a => a,
            b => b,
            op_add => op_add,
            op_sub => op_sub,
            op_mul => op_mul,
            result => result,
            gt => gt
        );

    stim: process

        variable errors: natural := 0;
        variable tests: natural := 0;
        variable seed1: positive := 42;
        variable seed2: positive := 7;
        variable r: real;
        variable ra, rb: integer;

        -- apply one vector, wait, check result AND gt at the same time
        -- check: take x, y , operation -> 
        procedure check(x, y: integer; op: op_t) is
            variable expected: integer;
            variable exp_gt: std_logic;
        begin
            a <= to_signed(x, W);
            b <= to_signed(y, W);
            op_add <= '0';
            op_sub <= '0';
            op_mul <= '0';
            case op is
                when OP_ADD_T => op_add <= '1';
                when OP_SUB_T => op_sub <= '1';
                when OP_MUL_T => op_mul <= '1';
            end case;
            wait for 10 ns; -- let combinational logic settle for good 

            expected := model(x, y, op); -- model uses exact model floating point math, not vhdl arithmetic; helps calculate results
            if x>y then 
                exp_gt := '1';
            else 
                exp_gt := '0';
            end if;
            tests := tests + 1;


            if to_integer(result) /= expected then
                errors := errors + 1;
                report op_name(op) & " FAIL: a=" & q(x) & " b=" & q(y) &
                       " got=" & q(to_integer(result)) &
                       " expected=" & q(expected) severity error;
            end if;
            if gt /= exp_gt then
                errors := errors + 1;
                report "GT FAIL: a=" & q(x) & " b=" & q(y) &
                       " got=" & std_logic'image(gt) severity error;
            end if;
        end procedure;

        procedure check_all_ops(x, y: integer) is
        begin
            check(x, y, OP_ADD_T);
            check(x, y, OP_SUB_T);
            check(x, y, OP_MUL_T);
        end procedure;

    begin
        -- direct tests (easy)
        check_all_ops(0, 0);
        check_all_ops(ONE, ONE);                 -- 1.0 , 1.0
        check_all_ops(ONE, -ONE);                -- 1.0 , -1.0
        check_all_ops(2*ONE, 3*ONE/2);           -- 2.0 , 1.5   -> mul = 3.0
        check_all_ops(ONE/2, ONE/2);             -- 0.5 * 0.5 = 0.25
        check_all_ops(-2*ONE, -2*ONE);           -- -2 * -2 = 4

        -- saturation corners 
        check(MAXV, 1,    OP_ADD_T);             -- positive overflow -> MAXV
        check(MAXV, MAXV, OP_ADD_T);
        check(MINV, -1,   OP_ADD_T);             -- negative overflow -> MINV
        check(MINV, MINV, OP_ADD_T);
        check(MINV, 1,    OP_SUB_T);             -- MINV - 1 -> MINV
        check(MAXV, MINV, OP_SUB_T);             -- huge positive -> MAXV
        check(0,    MINV, OP_SUB_T);             -- -(-8.0) = +8.0 not representable -> MAXV
        check(MINV, MINV, OP_MUL_T);             -- -8 * -8 = 64 -> MAXV
        check(MAXV, MAXV, OP_MUL_T);
        check(MAXV, MINV, OP_MUL_T);             -- -> MINV
        check(4*ONE, 2*ONE, OP_MUL_T);           -- exactly 8.0 -> just over MAXV
        check(-4*ONE, 2*ONE, OP_MUL_T);          -- exactly -8.0 = MINV, must NOT saturate wrong
        check(MAXV, 0,    OP_ADD_T);             -- edge without overflow
        check(MINV, 0,    OP_SUB_T);

        -- gt comparator
        check(5, 5, OP_ADD_T);                   -- equal -> gt = '0'
        check(-1, 0, OP_ADD_T);                  -- signed compare: -1 < 0
        check(MAXV, MINV, OP_ADD_T);
        check(MINV, MAXV, OP_ADD_T);

        -- rounding of the fixed point multiply
        check(1, 1,   OP_MUL_T);                 -- tiny*tiny -> 0
        check(-1, 1,  OP_MUL_T);                 -- floor -> -1, not 0 (arithmetic shift)
        check(ONE + 1, ONE + 1, OP_MUL_T);

        -- op priority /default !!!!
        -- mul > sub > add, and "no op" falls through to add.
        a <= to_signed(3*ONE, W); b <= to_signed(ONE, W);
        op_add <= '1'; op_sub <= '1'; op_mul <= '1';
        wait for 10 ns;
        tests := tests + 1;
        if to_integer(result) /= model(3*ONE, ONE, OP_MUL_T) then
            errors := errors + 1;
            report "PRIORITY FAIL: all ops high should give MUL" severity error;
        end if;
        op_add <= '0'; op_sub <= '0'; op_mul <= '0';
        wait for 10 ns;
        tests := tests + 1;
        if to_integer(result) /= model(3*ONE, ONE, OP_ADD_T) then
            errors := errors + 1;
            report "DEFAULT FAIL: no op should give ADD" severity error;
        end if;

        -- random tests
        for i in 1 to 5000 loop
            uniform(seed1, seed2, r);
            ra := integer(floor(r * real(2**W))) + MINV;   -- uniform in [MINV, MAXV]
            uniform(seed1, seed2, r);
            rb := integer(floor(r * real(2**W))) + MINV;
            check_all_ops(ra, rb);
        end loop;

        -- Random in Mandelbrot's useful range |x| < 2.0, where saturation is rare
        -- (so the non-saturated arithmetic gets exercised a lot)
        for i in 1 to 5000 loop
            uniform(seed1, seed2, r);
            ra := integer(floor((r * 4.0 - 2.0) * real(ONE)));
            uniform(seed1, seed2, r);
            rb := integer(floor((r * 4.0 - 2.0) * real(ONE)));
            check_all_ops(ra, rb);
        end loop;

        -- print results
        if errors = 0 then
            report "ALL " & integer'image(tests) & " TESTS PASSED" severity note;
        else
            report integer'image(errors) & " ERRORS in " & integer'image(tests) &
                   " tests" severity failure;
        end if;
        std.env.finish;   -- VHDL-2008; with VHDL-93 use a final "wait;" instead
    end process;

end architecture;


-- to compile : 
-- ghdl -a --std=08 alu.vhd tb_alu.vhd
-- ghdl -e --std=08 tb_alu
-- ghdl -r --std=08 tb_alu        