----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 22.03.2026 20:28:03
-- Design Name: 
-- Module Name: vga_controller_1 - Behavioral
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


----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 22.03.2026 11:51:37
-- Design Name: 
-- Module Name: vga_controller - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

entity vga_controller is

    generic(
    ---horizontal parameters
    h_visible: integer := 640;
    h_frontporch: integer := 16;
    h_syncpulse: integer := 96;
    h_backporch: integer := 48;
    h_total: integer :=800; --h_visible+h_frontporch+h_syncpulse+h_backporch
    
    N : integer := 10; --- no of bits in representing h_total in binary
    
    ---vertical parameters
    v_visible: integer := 480;
    v_frontporch: integer := 10;
    v_syncpulse: integer := 2;
    v_backporch: integer := 33;
    v_total: integer :=525 --v_visible+v_frontporch+v_syncpulse+v_backporch
    );
    
    Port ( clk : in STD_LOGIC;
           --rgb_in : in STD_LOGIC_VECTOR (11 downto 0); --12bit representation of colour
           rgb_out : out STD_LOGIC_VECTOR (11 downto 0); --12bit representation of colour
           hsync : out STD_LOGIC;
           vsync : out STD_LOGIC;
           pixel_x : out STD_LOGIC_VECTOR (N-1 downto 0);
           pixel_y : out STD_LOGIC_VECTOR (N-1 downto 0);
           active : out STD_LOGIC);
end vga_controller;

architecture Behavioral of vga_controller is
signal h_count:unsigned (N-1 downto 0):=(others=>'0');
signal v_count:unsigned (N-1 downto 0):=(others=>'0');
--signal rgbin: STD_LOGIC_VECTOR (11 downto 0) :="111100000000";
signal active_status: std_logic;
begin

--traversing through the pixels of screen 
--along with extra space for providing time for monitor to adjust
process (clk)
begin
if(rising_edge(clk)) then
    if(h_count=h_total-1) then 
    h_count<=(others=>'0');
        if(v_count=v_total-1) then 
        v_count<=(others=>'0');
        else v_count<=v_count+1;
        end if;
    else h_count<=h_count+1;
    end if;
end if;
end process;

hsync<='0' WHEN (h_count>=(h_visible+h_frontporch) and h_count<=(h_visible+h_frontporch+h_syncpulse-1)) ELSE '1';
vsync<='0' WHEN (v_count>=(v_visible+v_frontporch) and v_count<=(v_visible+v_frontporch+v_syncpulse-1)) ELSE '1';
active_status<='1' WHEN (h_count<h_visible and v_count<v_visible) ELSE '0';
active<=active_status;
pixel_x<= std_logic_vector(h_count);
pixel_y<= std_logic_vector(v_count);
rgb_out<="111100000000" WHEN active_status='1' ELSE (others=>'0');

end Behavioral;
