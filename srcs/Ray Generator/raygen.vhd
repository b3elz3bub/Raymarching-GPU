----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02.04.2026 09:03:09
-- Design Name: 
-- Module Name: gen - Behavioral
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


------------- worst case: 34 clock cycles - 22 for inverse squareroot + 12 here -----------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity gen is
    generic(
        bl: integer :=32;
        fb: integer := 16;
        screen_width: integer := 720;
        screen_height: integer := 405  
        );
        
     Port (
        dotout: out std_logic_vector (bl-1 downto 0);
        start: in std_logic;
        clk: in std_logic;
        pixx: in std_logic_vector (bl-1 downto 0);
        pixy: in std_logic_vector (bl-1 downto 0);
        originx,originy,originz: out std_logic_vector (bl-1 downto 0);
        directionx,directiony,directionz: out std_logic_vector (bl-1 downto 0);
        done: out std_logic
        );
end gen;

architecture Behavioral of gen is
  signal x,y: signed (bl-1 downto 0);
  signal h: signed (bl-1 downto 0);    
  signal w: signed (bl-1 downto 0); 
  signal invh: signed (bl-1 downto 0);
  signal uvx,uvy: signed (bl-1 downto 0);
  signal dotx,doty,dotz : signed (bl-1 downto 0);
  signal dot,mag,invmag: std_logic_vector (bl-1 downto 0);  
  signal run: std_logic:= '0';
  signal magstart: std_logic:= '0';
  signal magdone: std_logic:= '1'; 
  signal count: signed (3 downto 0); 
  
component invsqrt is
    Port (
x: in std_logic_vector ((bl-1) downto 0);
clk: in std_logic;
start: in std_logic;
ans: out std_logic_vector ((bl-1) downto 0);
done: out std_logic
);
    end component;
          
begin    
    invh <= x"000000A2";
    h<= TO_SIGNED(screen_height,bl);    
    w<= TO_SIGNED(screen_width,bl); 
    dotz<= x"00010000";
u1: invsqrt
    port map(
        x=>dot,
        clk=>clk,
        start=>magstart,
        ans=>mag,
        done=>magdone
        );
            
    process (clk)
    variable x2,y2,xshift,yshift,dotxy: signed (bl-1 downto 0);
    variable dotxfull,dotyfull,uvxfull,uvyfull,dirxfull,diryfull: signed (bl*2-1 downto 0);   
        begin
        if rising_edge(clk) then
            if run ='0' then
                if start = '1' then
                    x<=signed(pixx);
                    y<=signed(pixy);
                    done<='0';
                    run <= '1';
                    magstart<='0';                
                    count <= x"0";
                    dot <= x"00000000";
                end if;
                
            elsif run = '1' then
                if count = x"0" then
                    x2:=x(bl-2 downto 0) & '0';                    
                    xshift:=x2-signed(w((bl/2)-1 downto 0) & x"0000");                                       
                    uvxfull:= xshift * invh; 
                    uvx <= uvxfull(3*bl/2-1 downto bl/2);
                    count <= count +1;
                elsif count = x"1" then
                
                    y2:=y(bl-2 downto 0) & '0';
                    yshift:=signed( h((bl/2)-1 downto 0) & x"0000")-y2;
                    uvyfull := yshift * invh; 
                    uvy <= uvyfull(3*bl/2-1 downto bl/2);  
                    count<=count+1;
                elsif count = x"2" then
                    dotxfull := (uvx *uvx);
                    dotx <= dotxfull(3*bl/2-1 downto bl/2);
                    count<=count+1;
                elsif count = x"3" then                    
                    dotyfull:= (uvy*uvy);
                    doty <= dotyfull(3*bl/2-1 downto bl/2);
                    count <= count+1;
                elsif count = x"4" then                
                    dotxy := (dotx + doty);
                    dot <= std_logic_vector(dotxy + dotz);                    
                    count <= count +1;
                elsif count = x"5" then                                       
                    magstart<='1';
                    count<=count+1;
                elsif count = x"6" then
                    count <=count+1;                            
                elsif count = x"7" then
                    if magdone = '1' then
                        invmag<= mag ((bl-1) downto 0) ;
                        count <=count+1;
                    else magstart<='0';                            
                    end if;    
                elsif count = x"8" then
                    dotout<=std_logic_vector(dotx); 
                    dirxfull:=(uvx*signed(invmag));
                    directionx<=std_logic_vector(dirxfull(3*bl/2-1 downto bl/2));
                    count <= count +1;
                elsif count = x"9" then
                    diryfull:=(uvy*signed(invmag));
                    directiony<=std_logic_vector(diryfull(3*bl/2-1 downto bl/2));    
                    count <= count +1;
                elsif count = x"a" then
                    directionz<=invmag;
------------------  ray origin hard-coded to (0,0,-3) for now ---------------------- 
                    originx<=(others=>'0');
                    originy<=(others=>'0');
                    originz<=x"fffd0000";
                    done<='1';
                    run<='0';    
                end if;
            end if;
        end if;                            
    end process;
                            
                           
    
end Behavioral;
