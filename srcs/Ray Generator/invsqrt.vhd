----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 22.03.2026 16:47:49
-- Design Name: 
-- Module Name: invsqrt - Behavioral
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
use ieee.numeric_std.all;



-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;



--worst case: 22 clock cycles, may be optimized afterwards

entity invsqrt is
generic(
        bl: integer :=32;
        fb: integer := 16
        );

Port (
x: in std_logic_vector ((bl-1) downto 0);
clk: in std_logic;
start: in std_logic;
ans: out std_logic_vector ((bl-1) downto 0);
done: out std_logic
);
end invsqrt;


architecture Behavioral of invsqrt is


signal num: std_logic_vector ((bl-1) downto 0);
signal temp: unsigned ((bl-1) downto 0);
signal frac: unsigned ((fb-1) downto 0);
signal floating: std_logic_vector ((bl-1) downto 0) ;
signal count: unsigned (7 downto 0);
signal rootcount: unsigned (2 downto 0) ;
signal rootdone: std_logic := '0'; 
signal run,floatdone: std_logic:= '0' ;
signal y: unsigned ((bl-1) downto 0) ;
signal exp: natural:=0;

begin
exp<= TO_INTEGER(unsigned(y(30 downto 23))) - 127;

process (clk)
    variable v_y_sq_full   : unsigned(63 downto 0);
    variable v_term1_full  : unsigned(63 downto 0);
    variable v_diff        : unsigned(31 downto 0);
    variable halfnum       : unsigned(31 downto 0); 
    variable v_final_full  : unsigned(63 downto 0);
    begin
          
       if rising_edge(clk) then
            if run ='0' then
                if start='1' then 
                    frac<=unsigned(x((fb-1) downto 0));
                    done<='0';
                    rootdone<='0';
                    run<='1';
                    count<="00000001";
                    rootcount<="000";
                    num <= x;
                    temp <= (others=>'0');
                    floatdone<='0';
                end if;
              
            elsif run = '1' then
            if rootdone='0' then
                   if floatdone='0' then
                     -- converting the fixed point into floating point: worst case 15 clock cycles
                    if num=x"000000000" then
                        floating <= (others=>'0');
                        floatdone<='1';                  
                    elsif num(fb+1)='1' then
                        floating <= "010000000" & num(fb downto 0) & "000000";
                        floatdone<='1';
                    elsif num(fb)='1' then
                       floating <= "001111111" & num((fb-1) downto 0) & "0000000";
                        floatdone<='1'; 

                    else
                        if frac(fb-1)='0' then
                            count <= count+1;
                            
                            frac <= shift_left(unsigned(frac),1);
                        else
                            floating <= '0' & std_logic_vector("01111111"-count) & std_logic_vector(frac((fb-2) downto 0))& "00000000";
                            floatdone<='1';
                        end if;
                    end if;

                -- calculating initial guess: 1 clock cycle     
                else                                    
                    y <= x"5f375a86"-(shift_right(unsigned(floating),1));                        
                    rootdone <= '1';                                                                                 
                end if;

                -- calculating 1 newton-raphson iteration and giving the output: 6 clock cycles
                else
                    if floating = x"00000000" then
                        ans<=x"ffffffff";
                        done<='1';
                        run<='0';
                        rootdone<='0';
                        rootcount<="000";     
                    elsif rootcount ="000" then
                        temp<="0000000000000001" & y(22 downto 7);
                        rootcount<=rootcount+1;    
                    elsif rootcount = "001" then
                        if exp > 0 then
                        temp<=(shift_left(temp,exp));
                        elsif exp < 0 then
                        temp<=(shift_right(temp,abs(exp)));
                        end if;
                        rootcount<=rootcount+1;                                              
                   elsif rootcount = "010" then
                        v_y_sq_full  := temp * temp;
                        rootcount<=rootcount+1;
                   elsif rootcount = "011" then
                        halfnum := shift_right(unsigned(num),1);    
                        v_term1_full := halfnum * v_y_sq_full(47 downto 16);
                        rootcount<=rootcount+1;
                   elsif rootcount = "100" then
                        v_diff:= x"00018000" - v_term1_full(47 downto 16);
                        v_final_full := temp * v_diff;
                        temp <= unsigned(v_final_full(47 downto 16));
                        rootcount<=rootcount+1;      
                   elsif rootcount = "101" then
                        if halfnum = "000000000" then                            
                            ans<=x"00ff9127";
                        else    
                            ans <= std_logic_vector(temp);
                        end if;          
                        done<='1';
                        run<='0';
                        rootdone<='0';
                        rootcount<=rootcount+1;
                   end if;
               end if;
            end if;       
        end if;                

        

end process;





end Behavioral;
