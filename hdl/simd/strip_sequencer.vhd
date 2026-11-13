-- Strip sequencer with interactive zoom. Walks every (row, strip) computing
-- CX0/CY0/FB_BASE by accumulation, patches the core's instruction memory,
-- pulses start, waits done, advances -- then holds in S_DONE where it accepts
-- zoom buttons and re-renders.
--
-- Zoom: the view parameters (X0/Y0/DXF/DYF/DXN) are now REGISTERS. On a zoom-in
-- press (when idle) the pixel step halves and the origin is recomputed DIRECTLY
-- so the fixed point (CXC,CYC) stays centered -- exact at every level:
--   DXF' = DXF>>1 ;  X0' = CXC - (W/2)*DXF' ;  Y0' = CYC - (H/2)*DYF'
-- Reset restores the base view. Zoom-in is ignored once DXF = 1 (Q4.14 limit:
-- ~8 levels / 256x; deeper needs a wider word).
-- actually : 358 → 179 → 89 → 44 → 22 → 11 → 5 → 2 → 1 KEEP THIS IN MIND (it's basically x8)
-- With no zoom pulses the design renders once and holds -- identical to the
-- non-zoom sequencer, so the integration testbench still passes unchanged.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity strip_sequencer is
  generic (
    N     : integer := 4;
    IMG_W : integer := 160;
    IMG_H : integer := 120;
    X0    : integer := -40846;    -- base view (centered on the fixed point)
    Y0    : integer := -19629;
    DXF   : integer := 358;
    DYF   : integer := 358;
    DXN   : integer := 1432;
    CXC   : integer := -12206;    -- fixed zoom point, to_fixed(-0.745)
    CYC   : integer := 1851;      -- to_fixed(0.113)
    P_CX0 : integer := 2;
    P_DX  : integer := 3;         -- LI V8, DX  (per-lane step; patched for zoom)
    P_CY0 : integer := 6;
    P_FB  : integer := 26
  );
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    core_done      : in  std_logic;
    zoom_in        : in  std_logic := '0';     -- 1-cycle debounced pulse
    zoom_reset     : in  std_logic := '0';
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
  signal pcnt    : integer range 0 to 3 := 0;      -- 4 param words per strip

  -- live view parameters (registers; init to the base generics)
  -- s = state (ie, current)
  signal sx0  : signed(17 downto 0) := to_signed(X0, 18);
  signal sy0  : signed(17 downto 0) := to_signed(Y0, 18);
  signal sdxf : signed(17 downto 0) := to_signed(DXF, 18);
  signal sdyf : signed(17 downto 0) := to_signed(DYF, 18);
  signal sdxn : signed(17 downto 0) := to_signed(DXN, 18);

  -- per-strip accumulators
  signal cx0     : signed(17 downto 0) := to_signed(X0, 18);
  signal cy      : signed(17 downto 0) := to_signed(Y0, 18);
  signal fb_base : unsigned(21 downto 0) := (others => '0');

  constant LI_V0 : unsigned(31 downto 0) := x"04000000";   -- LI V0, imm
  constant LI_V1 : unsigned(31 downto 0) := x"04400000";   -- LI V1, imm
  constant LI_V8 : unsigned(31 downto 0) := x"06000000";   -- LI V8, imm (per-lane step)
  constant ST_V7 : unsigned(31 downto 0) := x"2C1C0000";   -- STORE V7, base

  -- auxiliary function
  -- ORs the 18-bit immediate into the low bits of the given template.
  -- The template already holds the opcode and the destination register. 
  -- V1 = 0x04400000, V8 = 0x06000000, so the destination register sits in bits 25:22. 
  -- unsigned(v) reinterprets the two’s-complement bits, so the core has to sign-extend from bit 17.
  function hw_li(tmpl : unsigned(31 downto 0); v : signed(17 downto 0))
    return std_logic_vector is
  begin
    return std_logic_vector(tmpl or resize(unsigned(v), 32));
  end function;

  function hw_store(b : unsigned(21 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(ST_V7
      or (resize(b(21 downto 18), 32) sll 22)
      or (resize(b(17 downto 14), 32) sll 14)
      or  resize(b(13 downto 0), 32));
  end function;
begin
  process (clk)
    -- n = next (ie, next dx, next dy, next y0,...)
    variable ndxf, ndyf, nx0, ny0, ndxn : signed(17 downto 0);
    -- also update the DX immediate the kernel loads (per-lane step = DXF)
  begin
    if rising_edge(clk) then
      core_start     <= '0';
      imem_we        <= '0';
      rendering_done <= '0';

      if rst = '1' then
        state <= S_PATCH;
        row <= 0; 
        col0 <= 0; 
        pcnt <= 0;
        sx0 <= to_signed(X0,18); 
        sy0 <= to_signed(Y0,18);
        sdxf <= to_signed(DXF,18); 
        sdyf <= to_signed(DYF,18); 
        sdxn <= to_signed(DXN,18);
        cx0 <= to_signed(X0,18); 
        cy <= to_signed(Y0,18);
        fb_base <= (others => '0');
      else
        case state is
          when S_PATCH =>
            imem_we <= '1';
            case pcnt is
              when 0 => imem_waddr <= P_CX0; imem_wdata <= hw_li(LI_V0, cx0);
              when 1 => imem_waddr <= P_CY0; imem_wdata <= hw_li(LI_V1, cy);
              when 2 => imem_waddr <= P_DX;  imem_wdata <= hw_li(LI_V8, sdxf);
              when others => imem_waddr <= P_FB; imem_wdata <= hw_store(fb_base);
            end case;
            if pcnt = 3 then pcnt <= 0; state <= S_START; else pcnt <= pcnt + 1; end if;

          when S_START =>
            core_start <= '1';
            state <= S_WAIT;

          when S_WAIT =>
            if core_done = '1' then state <= S_NEXT; end if;

          when S_NEXT =>
            fb_base <= fb_base + to_unsigned(N, 22);
            if col0 + N < IMG_W then
              col0 <= col0 + N;
              cx0  <= cx0 + sdxn;
              state <= S_PATCH;
            elsif row + 1 < IMG_H then
              row  <= row + 1;
              cy   <= cy + sdyf;
              col0 <= 0;
              cx0  <= sx0;
              state <= S_PATCH;
            else
              state <= S_DONE;
            end if;

          when S_DONE =>
            rendering_done <= '1';
            if zoom_in = '1' and sdxf > 1 then          -- zoom in (guard Q4.14 limit)
              ndxf := shift_right(sdxf, 1);
              ndyf := shift_right(sdyf, 1);
              nx0  := to_signed(CXC,18) - resize(to_signed(IMG_W/2, 9) * ndxf, 18);
              ny0  := to_signed(CYC,18) - resize(to_signed(IMG_H/2, 9) * ndyf, 18);
              ndxn := resize(to_signed(N, 6) * ndxf, 18);
              sdxf <= ndxf; sdyf <= ndyf; sdxn <= ndxn; sx0 <= nx0; sy0 <= ny0;
              cx0 <= nx0; cy <= ny0; row <= 0; col0 <= 0; fb_base <= (others=>'0');
              state <= S_PATCH;
            elsif zoom_reset = '1' then                  -- back to base view
              sx0 <= to_signed(X0,18); sy0 <= to_signed(Y0,18);
              sdxf <= to_signed(DXF,18); sdyf <= to_signed(DYF,18); sdxn <= to_signed(DXN,18);
              cx0 <= to_signed(X0,18); cy <= to_signed(Y0,18);
              row <= 0; col0 <= 0; fb_base <= (others=>'0');
              state <= S_PATCH;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;