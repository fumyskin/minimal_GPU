-- Strip sequencer: the hardware "host". Walks every (row, strip-column),
-- computes CX0/CY0/FB_BASE by ACCUMULATION (adders only, no multipliers),
-- patches those three words into the core's instruction memory, pulses start,
-- waits for done, and advances -- until the whole image is rendered.
--
-- Coordinate grid (matches the golden model exactly):
--   cx0 = X0 + col0*DXF   (reset to X0 each row, += DXN each strip)
--   cy  = Y0 + row*DYF    (+= DYF each row)
--   fb_base                (+= N every strip, so it naturally reaches row*W)
-- DXN = N*DXF is an exact multiple of the per-lane step, so there is no
-- fixed-point rounding drift versus the simulator.
--
-- Patch words mirror isa.encode_li / isa.encode_store (verified in Python):
--   LI V0, cx0   = x"04000000" or cx0[17:0]
--   LI V1, cy    = x"04400000" or cy[17:0]
--   STORE V7, b  = x"2C1C0000" or b[21:18]<<22 or b[17:14]<<14 or b[13:0]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity strip_sequencer is
  generic (
    N     : integer := 4;
    IMG_W : integer := 160;
    IMG_H : integer := 120;
    X0    : integer := -40960;    -- to_fixed(-2.5)
    Y0    : integer := -21504;    -- to_fixed(y0)
    DXF   : integer := 358;       -- to_fixed(dx)   (per-lane / per-column step)
    DYF   : integer := 358;       -- to_fixed(dy)
    DXN   : integer := 1432;      -- N*DXF          (per-strip step)
    P_CX0 : integer := 2;         -- instruction index of  LI V0, CX0
    P_CY0 : integer := 6;         -- instruction index of  LI V1, CY0
    P_FB  : integer := 26         -- instruction index of  STORE V7, FB_BASE
  );
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    core_done      : in  std_logic;
    core_start     : out std_logic;
    imem_we        : out std_logic;
    imem_waddr     : out natural;
    imem_wdata     : out std_logic_vector(31 downto 0);
    rendering_done : out std_logic
  );
end entity;

architecture rtl of strip_sequencer is
  type state_t is (S_PATCH, S_START, S_WAIT, S_NEXT, S_DONE);
  signal state : state_t := S_PATCH;

  signal row     : integer range 0 to IMG_H := 0;
  signal col0    : integer range 0 to IMG_W := 0;
  signal cx0     : signed(17 downto 0) := to_signed(X0, 18);
  signal cy      : signed(17 downto 0) := to_signed(Y0, 18);
  signal fb_base : unsigned(21 downto 0) := (others => '0');
  signal pcnt    : integer range 0 to 2 := 0;

  -- instruction-word templates (opcode + register fields already in place)
  constant LI_V0 : unsigned(31 downto 0) := x"04000000";
  constant LI_V1 : unsigned(31 downto 0) := x"04400000";
  constant ST_V7 : unsigned(31 downto 0) := x"2C1C0000";

  function hw_li(tmpl : unsigned(31 downto 0); v : signed(17 downto 0))
    return std_logic_vector is
  begin
    return std_logic_vector(tmpl or resize(unsigned(v), 32));     -- raw18 -> bits 17:0
  end function;

  function hw_store(b : unsigned(21 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(
      ST_V7
      or (resize(b(21 downto 18), 32) sll 22)
      or (resize(b(17 downto 14), 32) sll 14)
      or  resize(b(13 downto 0), 32));
  end function;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      -- defaults (overridden below per state)
      core_start     <= '0';
      imem_we        <= '0';
      rendering_done <= '0';

      if rst = '1' then
        state <= S_PATCH;
        row <= 0; col0 <= 0; pcnt <= 0;
        cx0 <= to_signed(X0, 18);
        cy  <= to_signed(Y0, 18);
        fb_base <= (others => '0');
      else
        case state is
          ----------------------------------------------------------------
          when S_PATCH =>                 -- write the 3 param words, one per cycle
            imem_we <= '1';
            case pcnt is
              when 0 => imem_waddr <= P_CX0; imem_wdata <= hw_li(LI_V0, cx0);
              when 1 => imem_waddr <= P_CY0; imem_wdata <= hw_li(LI_V1, cy);
              when others => imem_waddr <= P_FB; imem_wdata <= hw_store(fb_base);
            end case;
            if pcnt = 2 then
              pcnt <= 0;
              state <= S_START;
            else
              pcnt <= pcnt + 1;
            end if;

          ----------------------------------------------------------------
          when S_START =>                 -- launch the kernel for this strip
            core_start <= '1';
            state <= S_WAIT;

          ----------------------------------------------------------------
          when S_WAIT =>
            if core_done = '1' then
              state <= S_NEXT;
            end if;

          ----------------------------------------------------------------
          when S_NEXT =>
            fb_base <= fb_base + to_unsigned(N, 22);     -- base advances every strip
            if col0 + N < IMG_W then
              col0  <= col0 + N;
              cx0   <= cx0 + to_signed(DXN, 18);         -- next strip in this row
              state <= S_PATCH;
            elsif row + 1 < IMG_H then
              row   <= row + 1;                          -- next row
              cy    <= cy + to_signed(DYF, 18);
              col0  <= 0;
              cx0   <= to_signed(X0, 18);
              state <= S_PATCH;
            else
              state <= S_DONE;                           -- whole image done
            end if;

          ----------------------------------------------------------------
          when S_DONE =>
            rendering_done <= '1';
        end case;
      end if;
    end if;
  end process;
end architecture;