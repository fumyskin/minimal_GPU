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
        -- apply one vector, wait, check result AND gt at the same time
        -- check: take x, y , operation -> 
        procedure check(x, y: integer; op: op_t) is
            variable expected: integer;
            variable exp_gt: std_logic;
        begin
            a <= to_signed(x, W);
            b <= to_signed(x, W);


