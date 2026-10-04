-- SIMD compute core: non-pipelined multi-cycle FSM driving N parallel lanes.
-- Executes the instruction ROM once per start pulse (one kernel launch = one
-- strip), writing results to the framebuffer port, then pulses done.
--
-- Decode matches isa.py exactly:
--   word = opcode(31:26) rd(25:22) ra(21:18) rb(17:14) imm(13:0)
--   LI    raw18  = word(17:0)                      (rb|imm are contiguous)
--   STORE base22 = word(25:22) & word(17:14) & word(13:0)   (ra skipped)
--
-- One instruction per RUN cycle (ROM read is combinational); STORE takes N
-- cycles, one framebuffer write per lane through the single write port.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity compute_core is
  generic (
    N         : integer := 4;             -- SIMD lanes
    W         : integer := 18;
    F         : integer := 14;
    ROM_DEPTH : integer := 256;
    INIT_FILE : string  := "imem.mem"     -- 8 hex digits per line
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;              -- pulse to launch at PC=0
    done    : out std_logic;              -- 1-cycle pulse at HALT
    fb_we   : out std_logic;
    fb_addr : out unsigned(21 downto 0);
    fb_data : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of compute_core is
  -- opcodes (mirror isa.py OPCODES)
  constant OP_NOP:integer:=0;  constant OP_LI:integer:=1;   constant OP_LANEID:integer:=2;
  constant OP_MOV:integer:=3;  constant OP_ADD:integer:=4;  constant OP_SUB:integer:=5;
  constant OP_MUL:integer:=6;  constant OP_ESC:integer:=7;  constant OP_MASKALL:integer:=8;
  constant OP_SETLOOP:integer:=9; constant OP_ENDLOOP:integer:=10;
  constant OP_STORE:integer:=11;  constant OP_HALT:integer:=12;

  -- instruction ROM, initialized from a hex .mem
  type rom_t is array(0 to ROM_DEPTH - 1) of std_logic_vector(31 downto 0);

  impure function init_rom(fn : string) return rom_t is
    file     fh  : text open read_mode is fn;
    variable l   : line;
    variable c   : character;
    variable ok  : boolean;
    variable nyb : integer;
    variable wd  : std_logic_vector(31 downto 0);
    variable m   : rom_t := (others => (others => '0'));
    variable idx : integer := 0;
  begin
    while not endfile(fh) and idx < ROM_DEPTH loop
      readline(fh, l);
      wd := (others => '0');
      for i in 0 to 7 loop
        read(l, c, ok);
        exit when not ok;
        case c is
          when '0' to '9' => nyb := character'pos(c) - character'pos('0');
          when 'a' to 'f' => nyb := character'pos(c) - character'pos('a') + 10;
          when 'A' to 'F' => nyb := character'pos(c) - character'pos('A') + 10;
          when others     => nyb := 0;
        end case;
        wd := wd(27 downto 0) & std_logic_vector(to_unsigned(nyb, 4));
      end loop;
      m(idx) := wd;
      idx := idx + 1;
    end loop;
    return m;
  end function;

  constant ROM : rom_t := init_rom(INIT_FILE);

  -- register file: N lanes x 16 x W bits
  type bank_t  is array(0 to 15) of signed(W - 1 downto 0);
  type lanes_t is array(0 to N - 1) of bank_t;
  signal regs : lanes_t := (others => (others => (others => '0')));
  signal mask : std_logic_vector(N - 1 downto 0) := (others => '1');

  -- control state
  type state_t is (IDLE, RUN, DO_STORE, DO_DONE);
  signal state   : state_t := IDLE;
  signal pc      : integer range 0 to ROM_DEPTH - 1 := 0;
  signal lc      : unsigned(13 downto 0) := (others => '0');
  signal store_k : integer range 0 to N - 1 := 0;

  -- combinational decode of ROM(pc)
  signal instr  : std_logic_vector(31 downto 0);
  signal opcode : integer range 0 to 63;
  signal rd_i, ra_i, rb_i : integer range 0 to 15;
  signal imm14  : unsigned(13 downto 0);
  signal li_val : signed(W - 1 downto 0);
  signal base22 : unsigned(21 downto 0);
  signal is_add, is_sub, is_mul : std_logic;

  -- per-lane ALU operands (selected by the dynamic ra/rb indices) and outputs
  type   warr_t is array(0 to N - 1) of signed(W - 1 downto 0);
  signal opa, opb : warr_t;
  signal alu_res  : warr_t;
  signal alu_gt   : std_logic_vector(N - 1 downto 0);

  signal any_active : std_logic;
begin
  ------------------------------------------------------------------ decode
  instr  <= ROM(pc);
  opcode <= to_integer(unsigned(instr(31 downto 26)));
  rd_i   <= to_integer(unsigned(instr(25 downto 22)));
  ra_i   <= to_integer(unsigned(instr(21 downto 18)));
  rb_i   <= to_integer(unsigned(instr(17 downto 14)));
  imm14  <= unsigned(instr(13 downto 0));
  li_val <= signed(instr(17 downto 0));                         -- LI raw18
  base22 <= unsigned(instr(25 downto 22)) & unsigned(instr(17 downto 14)) & unsigned(instr(13 downto 0));

  any_active <= '1' when mask /= (mask'range => '0') else '0';

  -- op selects: shared across lanes (opcode is one signal). A conditional
  -- expression is not a legal port-map actual, so drive these as signals first.
  is_add <= '1' when opcode = OP_ADD else '0';
  is_sub <= '1' when opcode = OP_SUB else '0';
  is_mul <= '1' when opcode = OP_MUL else '0';

  ------------------------------------------------------------------ lanes
  gen_lanes : for i in 0 to N - 1 generate
    -- dynamic register selection happens here (legal in a concurrent assignment);
    -- the ALU port then receives the static name opa(i)/opb(i).
    opa(i) <= regs(i)(ra_i);
    opb(i) <= regs(i)(rb_i);
    u_alu : entity work.alu
      generic map (W => W, F => F)
      port map (
        a      => opa(i),
        b      => opb(i),
        op_add => is_add,
        op_sub => is_sub,
        op_mul => is_mul,
        result => alu_res(i),
        gt     => alu_gt(i)
      );
  end generate;

  ------------------------------------------------------------------ framebuffer write (combinational, during DO_STORE)
  fb_we   <= '1' when state = DO_STORE else '0';
  fb_addr <= base22 + to_unsigned(store_k, 22) when state = DO_STORE else (others => '0');
  fb_data <= std_logic_vector(regs(store_k)(ra_i)(7 downto 0)) when state = DO_STORE
             else (others => '0');

  ------------------------------------------------------------------ control + datapath update
  process (clk)
  begin
    if rising_edge(clk) then
      done <= '0';
      if rst = '1' then
        state <= IDLE;
        pc <= 0; lc <= (others => '0'); store_k <= 0;
        mask <= (others => '1');
      else
        case state is
          ----------------------------------------------------------------
          when IDLE =>
            if start = '1' then
              pc <= 0;
              mask <= (others => '1');       -- reset mask each launch
              state <= RUN;
            end if;

          ----------------------------------------------------------------
          when RUN =>
            case opcode is
              when OP_NOP =>
                pc <= pc + 1;

              when OP_LI =>                    -- broadcast, unmasked
                for i in 0 to N - 1 loop
                  regs(i)(rd_i) <= li_val;
                end loop;
                pc <= pc + 1;

              when OP_LANEID =>                -- lane index as Q4.14 integer, unmasked
                for i in 0 to N - 1 loop
                  regs(i)(rd_i) <= to_signed(i * (2 ** F), W);
                end loop;
                pc <= pc + 1;

              when OP_MOV =>                   -- masked
                for i in 0 to N - 1 loop
                  if mask(i) = '1' then regs(i)(rd_i) <= regs(i)(ra_i); end if;
                end loop;
                pc <= pc + 1;

              when OP_ADD | OP_SUB | OP_MUL => -- masked
                for i in 0 to N - 1 loop
                  if mask(i) = '1' then regs(i)(rd_i) <= alu_res(i); end if;
                end loop;
                pc <= pc + 1;

              when OP_ESC =>                   -- clear mask of active lanes where a > b
                for i in 0 to N - 1 loop
                  if mask(i) = '1' and alu_gt(i) = '1' then mask(i) <= '0'; end if;
                end loop;
                pc <= pc + 1;

              when OP_MASKALL =>
                mask <= (others => '1');
                pc <= pc + 1;

              when OP_SETLOOP =>
                lc <= imm14;
                pc <= pc + 1;

              when OP_ENDLOOP =>               -- decrement, branch if LC/=0 and any active
                lc <= lc - 1;
                if (lc - 1) /= 0 and any_active = '1' then
                  pc <= to_integer(imm14);
                else
                  pc <= pc + 1;
                end if;

              when OP_STORE =>
                store_k <= 0;
                state <= DO_STORE;             -- PC held; advances after last lane

              when OP_HALT =>
                state <= DO_DONE;

              when others =>
                pc <= pc + 1;
            end case;

          ----------------------------------------------------------------
          when DO_STORE =>
            if store_k = N - 1 then
              pc <= pc + 1;
              state <= RUN;
            else
              store_k <= store_k + 1;
            end if;

          ----------------------------------------------------------------
          when DO_DONE =>
            done <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;