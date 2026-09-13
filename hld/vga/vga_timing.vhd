library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing is
    generic(
        H_VISIBLE : integer := 640;
        H_FRONT : integer := 16;
        H_SYNC : integer := 96;
        H_BACK : integer := 48;
        V_VISIBLE : integer := 480;
        V_FRONT : integer := 10;
        V_SYNC : integer := 2;
        V_BACK : integer := 33
    );
    port(
        clk : in std_logic; -- 100 Mhz system clock
        rst : in std_logic; 
        pix_ce : in std_logic; -- pixel_rate enable (25 Mhz)
        hsync : out std_logic; -- active low
        vsync : out std_logic; -- active low
        vide_on : out std_logic; -- high in the visible area
        px : out unsigned(9 downto 0); -- 0..639 when vide_on
        py : out unsigned(9 downto 0) -- 0..479 when video_on
        frame_start : out std_logic -- 1-cycle pulse at (0,0)
    );
end entity;


architecture rtl of vga_timing is
    constant H_TOTAL : integer := H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    constant V_TOTAL : integer := V_VISIBLE + V_FRONT + V_SYNC + V_BACK;
    constant H_SYNC_START : integer := H_VISIBLE + H_FRONT;
    constant H_SYNC_END : integer := H_VISIBLE + H_FRONT + H_SYNC;
    constant V_SYNC_START : integer := V_VISIBLE + V_FRONT;
    constant V_SYNC_END : integer := V_VISIBLE + V_FRONT + V_SYNC;

    signal hc : integer range 0 to H_TOTAL - 1 := 0;  -- h_count
    signal vc : integer range 0 to V_TOTAL - 1 := 0;  -- v_count

begin
    --position counters. hc walks each line, vc advances at end of line
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                hc <= 0;
                vc <= 0;
            elsif pix_Ce = '1' then
                if hc = H_TOTAL -1 then
                    hc <= 0;
                    if vc = V_TOTAL -1 then
                        vc <= 0;
                    else
                        vc <= vc + 1;
                    end if;
                else
                    hc <= hc + 1;
                end if;
            end if;
        end if;
    end process;

-- Combinational decode of the registered counters (stable for the whole pixel).
  hsync       <= '0' when (hc >= H_SYNC_START and hc < H_SYNC_END) else '1';
  vsync       <= '0' when (vc >= V_SYNC_START and vc < V_SYNC_END) else '1';
  video_on    <= '1' when (hc < H_VISIBLE and vc < V_VISIBLE) else '0';
  px          <= to_unsigned(hc, 10) when hc < H_VISIBLE else (others => '0');
  py          <= to_unsigned(vc, 10) when vc < V_VISIBLE else (others => '0');
  frame_start <= '1' when (hc = 0 and vc = 0 and pix_ce = '1') else '0';
  
end architecture;
