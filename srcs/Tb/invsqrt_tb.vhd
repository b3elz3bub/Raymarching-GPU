----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 28.03.2026 14:03:48
-- Design Name: 
-- Module Name: invsqrt_tb - Behavioral
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

entity invsqrt_tb is
generic(
        bl: integer :=32;
        fb: integer := 16
        );
--  Port ( );
end invsqrt_tb;

architecture Behavioral of invsqrt_tb is
signal x:  std_logic_vector ((bl-1) downto 0);
signal clk: std_logic;
signal start: std_logic;
signal ans: std_logic_vector ((bl-1) downto 0);
signal done: std_logic;


begin

uut: entity work.invsqrt
port map(
x=>x,
clk=>clk,
start=>start,
ans=>ans,
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
    x<=(others=>'0');
    wait for 21 ns;
    
    x<=x"00010001";
    wait for 20 ns;
    
    start<='1';
    wait for 10 ns;
    
    start<='0';
    wait for 10 ns;
    
    x<=x"00000002";
    wait for 150 ns;
    
    start<='1';
    wait for 10 ns;
    
    start<='0';
    wait for 10 ns;
    
    x<=(others=>'0');
    wait;

end process;


end Behavioral;
