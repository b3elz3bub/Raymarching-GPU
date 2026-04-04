----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 22.03.2026 14:01:58
-- Design Name: 
-- Module Name: main_module - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity main_module is
    Port (
        clk_100MHz : in  STD_LOGIC;   -- Board clock

        hsync  : out STD_LOGIC;
        vsync  : out STD_LOGIC;
        -- rgb_in : out STD_LOGIC_VECTOR (11 downto 0);
        rgb_out : out STD_LOGIC_VECTOR (11 downto 0) 
    );
end main_module;

architecture Behavioral of main_module is

    -- Clock Wizard signals
    signal clk_25MHz : STD_LOGIC;
    signal locked    : STD_LOGIC;

    -- VGA internal signals
    signal pixel_x : STD_LOGIC_VECTOR (9 downto 0):=(others=>'0');
    signal pixel_y : STD_LOGIC_VECTOR (9 downto 0):=(others=>'0');
    signal active  : STD_LOGIC;
    
    component clk_wiz_0 
    port(
    clk_in1:in std_logic;
    clk_out1: out std_logic;
    reset: in std_logic;
    locked: out std_logic
    ) ;
    end component;

begin

    ------------------------------------------------------------------
    -- Clock Wizard Instance
    ------------------------------------------------------------------
    clk_wiz_inst : clk_wiz_0
        port map (
            clk_in1  => clk_100MHz,
            clk_out1 => clk_25MHz,
            reset=>'0',
            locked   => locked
        );

    ------------------------------------------------------------------
    -- VGA Controller Instance
    ------------------------------------------------------------------
    vga_inst : entity work.vga_controller
        port map (
            clk      => clk_25MHz,

            hsync    => hsync,
            vsync    => vsync,
            --rgb_in   => rgb_in,
            rgb_out  => rgb_out,

            pixel_x  => pixel_x,
            pixel_y  => pixel_y,
            active   => active
        );

end Behavioral;
