library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_vga is
end tb_vga;

architecture Behavioral of tb_vga is

    -- Component declaration
    component vga_controller
        port (
            clk      : in  STD_LOGIC;
            hsync    : out STD_LOGIC;
            vsync    : out STD_LOGIC;
            rgb_out  : out STD_LOGIC_VECTOR(11 downto 0);
            pixel_x  : out STD_LOGIC_VECTOR(9 downto 0);
            pixel_y  : out STD_LOGIC_VECTOR(9 downto 0);
            active   : out STD_LOGIC
        );
    end component;

    -- Signals
    signal clk_tb     : STD_LOGIC := '0';
    signal hsync_tb   : STD_LOGIC;
    signal vsync_tb   : STD_LOGIC;
    signal rgb_tb     : STD_LOGIC_VECTOR(11 downto 0);
    signal pixel_x_tb : STD_LOGIC_VECTOR(9 downto 0);
    signal pixel_y_tb : STD_LOGIC_VECTOR(9 downto 0);
    signal active_tb  : STD_LOGIC;

begin

    ------------------------------------------------------------------
    -- Instantiate your VGA controller
    ------------------------------------------------------------------
    uut: vga_controller
        port map (
            clk      => clk_tb,
            hsync    => hsync_tb,
            vsync    => vsync_tb,
            rgb_out  => rgb_tb,
            pixel_x  => pixel_x_tb,
            pixel_y  => pixel_y_tb,
            active   => active_tb
        );

    ------------------------------------------------------------------
    -- Clock generation (25 MHz ? 40 ns period)
    ------------------------------------------------------------------
    clk_process : process
    begin
        clk_tb <= '0';
        wait for 20 ns;
        clk_tb <= '1';
        wait for 20 ns;
    end process;

end Behavioral;
