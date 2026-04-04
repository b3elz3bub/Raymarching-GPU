-------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02.04.2026 21:38:12
-- Design Name: 
-- Module Name: gen_tb - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity gen_tb is
    generic(
        bl: integer :=32;
        fb: integer := 16;
        screen_width: integer := 720;
        screen_height: integer := 405  
        );
--  Port ( );
end gen_tb;

architecture Behavioral of gen_tb is
signal dotout: std_logic_vector (bl-1 downto 0);
signal start:  std_logic;
signal clk:  std_logic;
signal pixx:  std_logic_vector (bl-1 downto 0);
signal pixy:  std_logic_vector (bl-1 downto 0);
signal originx,originy,originz:  std_logic_vector (bl-1 downto 0);
signal directionx,directiony,directionz:  std_logic_vector (bl-1 downto 0);
signal done:  std_logic;


begin

uut: entity work.gen
    port map(
        dotout=>dotout,
        start=>start,
        clk=>clk,
        pixx=>pixx,
        pixy=>pixy,
        originx=>originx,originy=>originy,originz=>originz,
        directionx=>directionx,directiony=>directiony,directionz=>directionz,
        done=>done
        );
process
begin
    while true loop
        clk<='0';
        wait for 5 ns;
        clk<='1';
        wait for 5 ns;
        end loop;
        end process;

process
    begin
    
    start<='0';
    pixx<= x"00010000";
    pixy<= x"00000000";
    wait for 20 ns;
    
    
    start<='1';
    wait for 11 ns;
    
    start<='0';
    pixx<= x"02d00000";
    pixy<= x"01950000";
    wait for 400 ns;
    
    
    start<='1';
    wait for 11 ns;
    
    start<='0';
    wait;

end process;                 

end Behavioral;
