---------------------------------------------------------------------------------
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


------------- worst case: 23 clock cycles - 11 for inverse squareroot + 12 here -----------
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
        inlen: integer :=18;
        infrac: integer := 0;
        outlen: integer := 18;
        dirfrac: integer := 16;
        orifrac: integer := 12;
        screen_width: integer := 720;
        screen_height: integer := 405  
        );
        
     Port (
        dotout: out std_logic_vector (outlen-1 downto 0);
        start: in std_logic;
        clk: in std_logic;
        pixx: in std_logic_vector (inlen-1 downto 0);
        pixy: in std_logic_vector (inlen-1 downto 0);
        originx,originy,originz: out std_logic_vector (outlen-1 downto 0);
        directionx,directiony,directionz: out std_logic_vector (outlen-1 downto 0);
        done: out std_logic
        );
end gen;

architecture Behavioral of gen is
  signal x,y: signed (inlen-1 downto 0);
  signal h: signed (inlen-1 downto 0);    
  signal w: signed (inlen-1 downto 0); 
  signal invh: signed (inlen-1 downto 0);
  signal uvx,uvy: signed (inlen-1 downto 0);
  signal dotx,doty,dotz : signed (inlen-1 downto 0);
  signal dot,mag,invmag: std_logic_vector (inlen-1 downto 0);  
  signal run: std_logic:= '0';
  signal magstart: std_logic:= '0';
  signal magdone: std_logic:= '1'; 
  signal count: signed (3 downto 0); 
  
component invsqrt is
    Port (
x: in std_logic_vector ((inlen-1) downto 0);
clk: in std_logic;
start: in std_logic;
ans: out std_logic_vector ((outlen-1) downto 0);
done: out std_logic
);
    end component;
          
begin    
    invh <= "00"&x"00A2"; -- Q2.16
    h<= TO_SIGNED(screen_height,inlen); -- Q18.0
    w<= TO_SIGNED(screen_width,inlen);  -- Q18.0 
    dotz<= "00" & x"8000"; -- (1.0)d in Q3.15
u1: invsqrt
    port map(
        x=>dot,
        clk=>clk,
        start=>magstart,
        ans=>mag,-- Q9.9
        done=>magdone
        );
            
    process (clk)
    variable x2,y2,xshift,yshift: signed (inlen-1 downto 0);
    variable dotxy: signed (inlen downto 0); -- Q3.16
    variable dottemp: signed (inlen-1 downto 0); -- Q4.14
    variable dotxfull,dotyfull,uvxfull,uvyfull,dirxfull,diryfull: signed (inlen*2-1 downto 0);   
        begin
        if rising_edge(clk) then
            if run ='0' then
                if start = '1' then
                    x<=signed(pixx); -- Q18.0
                    y<=signed(pixy); -- Q18.0                    
                    done<='0';
                    run <= '1';
                    magstart<='0';                
                    count <= x"0";
                    dot <= "00" & x"0000"; -- Q3.15
                end if;
                
            elsif run = '1' then
                if count = x"0" then
                    x2:=x(inlen-2 downto 0) & '0'; -- Q18.0                   
                    xshift:=x2-w; -- Q18.0                                       
                    uvxfull:= xshift * invh; -- Q20.16 , we need only the 2.16 
                    uvx <= uvxfull(17 downto 0); -- Q2.16
                    count <= count +1;
                elsif count = x"1" then
                
                    y2:=y(inlen-2 downto 0) & '0';
                    yshift:=h-y2;
                    uvyfull := yshift * invh; -- Q20.16, we need only 2.16
                    uvy <= uvyfull(17 downto 0); -- Q2.16  
                    count<=count+1;
                elsif count = x"2" then
                    dotxfull := (uvx * uvx); -- Q4.32
                    dotx <= dotxfull(34 downto 17); -- Q3.15 
                    count<=count+1;
                elsif count = x"3" then                    
                    dotyfull:= (uvy*uvy); -- Q4.32
                    doty <= dotyfull(34 downto 17); -- Q3.15
                    count <= count+1;
                elsif count = x"4" then                
                    dotxy := resize(dotx, 19) + resize(doty, 19) + resize(dotz, 19);
                    dotxy := shift_right(dotxy, 2);  -- divide by 4, Q3.15
                    dot <= std_logic_vector(dotxy(17 downto 0)); -- Q3.15, to invsqrt                   
                    count <= count +1;
                elsif count = x"5" then                                       
                    magstart<='1';
                    count<=count+1;
                elsif count = x"6" then
                    count <=count+1;                            
                elsif count = x"7" then
                    if magdone = '1' then
                        invmag <= mag(17 downto 0); -- divide by 2 (right shift), Q9.9
                        count <=count+1;
                    else magstart<='0';                            
                    end if;    
                elsif count = x"8" then
                    dotout<=std_logic_vector(dotx); 
                    dirxfull:=(uvx*signed(invmag)); -- Q11.25, we need only 2.16
                    directionx<=std_logic_vector(dirxfull(27 downto 10)); -- Q2.16
                    count <= count +1;
                elsif count = x"9" then
                    diryfull:=(uvy*signed(invmag)); -- Q11.25, we need only 2.16
                    directiony<=std_logic_vector(diryfull(27 downto 10)); -- Q2.16    
                    count <= count+1;
                elsif count = x"a" then
                    directionz <= invmag(11 downto 0) & "000000"; -- Q2.16
------------------  ray origin hard-coded to (0,0,-3) for now ---------------------- 
                    originx<=(others=>'0'); -- Q6.12
                    originy<=(others=>'0'); -- Q6.12
                    originz<="11"& x"d000"; -- Q6.12
                    done<='1';
                    run<='0';    
                end if;
            end if;
        end if;                            
    end process;
                            
                           
    
end Behavioral;
