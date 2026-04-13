----------------------------------------------------------------------------------
-- VGA Controller — 640×480 @ 60Hz
-- Generates hsync, vsync, pixel coordinates, and active region flag
-- Requires 25.175 MHz pixel clock (use 25 MHz from clock wizard)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_controller is
    generic(
        -- Horizontal timing (pixels)
        h_visible   : integer := 640;
        h_frontporch: integer := 16;
        h_syncpulse : integer := 96;
        h_backporch : integer := 48;
        h_total     : integer := 800;
        -- Bit width for counters
        N : integer := 10;
        -- Vertical timing (lines)
        v_visible   : integer := 480;
        v_frontporch: integer := 10;
        v_syncpulse : integer := 2;
        v_backporch : integer := 33;
        v_total     : integer := 525
    );
    port (
        clk     : in  STD_LOGIC;
        rgb_in  : in  STD_LOGIC_VECTOR(11 downto 0);
        rgb_out : out STD_LOGIC_VECTOR(11 downto 0);
        hsync   : out STD_LOGIC;
        vsync   : out STD_LOGIC;
        pixel_x : out STD_LOGIC_VECTOR(N-1 downto 0);
        pixel_y : out STD_LOGIC_VECTOR(N-1 downto 0);
        active  : out STD_LOGIC
    );
end vga_controller;

architecture Behavioral of vga_controller is
    signal h_count : unsigned(N-1 downto 0) := (others => '0');
    signal v_count : unsigned(N-1 downto 0) := (others => '0');
    signal active_status : std_logic;
begin

    -- Pixel / line counters
    process(clk)
    begin
        if rising_edge(clk) then
            if h_count = h_total - 1 then
                h_count <= (others => '0');
                if v_count = v_total - 1 then
                    v_count <= (others => '0');
                else
                    v_count <= v_count + 1;
                end if;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    -- Sync signals (active-low)
    hsync <= '0' when (h_count >= (h_visible + h_frontporch) and
                       h_count <= (h_visible + h_frontporch + h_syncpulse - 1)) else '1';
    vsync <= '0' when (v_count >= (v_visible + v_frontporch) and
                       v_count <= (v_visible + v_frontporch + v_syncpulse - 1)) else '1';

    -- Active region
    active_status <= '1' when (h_count < h_visible and v_count < v_visible) else '0';
    active  <= active_status;
    pixel_x <= std_logic_vector(h_count);
    pixel_y <= std_logic_vector(v_count);

    -- Blank RGB outside active region
    rgb_out <= rgb_in when active_status = '1' else (others => '0');

end Behavioral;
