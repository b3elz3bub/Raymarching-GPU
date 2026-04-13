library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

--worst case: 11 clock cycles, may be optimized afterwards

entity invsqrt is
generic(
        inlen: integer :=18;
        outlen: integer := 18;
        floatlen: integer := 32;
        infrac: integer := 15;
        outfrac: integer := 9
        );

Port (
x: in std_logic_vector ((inlen-1) downto 0);
clk: in std_logic;
start: in std_logic;
ans: out sfixed((outlen - outfrac - 1) downto -outfrac);
done: out std_logic
);
end invsqrt;


architecture Behavioral of invsqrt is


signal num: std_logic_vector ((inlen-1) downto 0);
signal temp: unsigned ((2*inlen-1) downto 0);
signal frac: unsigned ((infrac-1) downto 0);
signal floating: std_logic_vector ((floatlen-1) downto 0) ;
signal count: unsigned (7 downto 0);
signal rootcount: unsigned (2 downto 0) ;
signal rootdone: std_logic := '0'; 
signal run,floatdone: std_logic:= '0' ;
signal y: unsigned ((floatlen-1) downto 0) ;
signal exp: integer:=0;
signal v_y_sq_full   : unsigned(2*inlen-1 downto 0);
signal v_term1_full  : unsigned(2*inlen-1 downto 0);
signal halfnum       : unsigned(inlen-1 downto 0);
begin
exp<= TO_INTEGER(unsigned(y(30 downto 23))) - 127;

process (clk)
    variable v_diff,temp2  : unsigned(inlen-1 downto 0);
    variable tempvar: unsigned ((2*inlen-1) downto 0); 
    variable v_final_full  : unsigned(2*inlen-1 downto 0);
    begin
          
       if rising_edge(clk) then
            if run ='0' then
                if start='1' then 
                    frac<=unsigned(x((infrac-1) downto 0));
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
                     -- converting the fixed point into floating point: worst case 4 clock cycles
                    if num="00" & x"0000" then
                        floating <= (others=>'0');
                        floatdone<='1';
                    elsif num(infrac+2) ='1' then
                        floating <= "010000001" & num((infrac+1) downto 0) & "000000";
                        floatdone<='1';                      
                    elsif num(infrac+1)='1' then
                        floating <= "010000000" & num(infrac downto 0) & "0000000";
                        floatdone<='1';
                    elsif num(infrac)='1' then
                       floating <= "001111111" & num((infrac-1) downto 0) & "00000000";
                        floatdone<='1'; 
                     
                    else
                        if frac(infrac-1)='0' then
                            count <= count+1;
                            
                            frac <= shift_left(unsigned(frac),1);
                        else
                            floating <= '0' & std_logic_vector("01111111"-count) & std_logic_vector(frac((infrac-2) downto 0))& "000000000";
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
                        ans <= to_sfixed(std_logic_vector'("11" & x"ffff"), ans'left, ans'right);
                        done<='1';
                        run<='0';
                        rootdone<='0';
                        rootcount<="000";     
                    elsif rootcount ="000" then
                        temp<="00000000000000000001" & y(22 downto 7);
                        rootcount<=rootcount+1;    
                    elsif rootcount = "001" then
                        if exp > 0 then                        
                        tempvar:=(shift_left(temp,exp));
                        temp<=tempvar;
                        elsif exp < 0 then
                        tempvar:=(shift_right(temp,abs(exp)));
                        temp<=tempvar;
                        end if;
                        rootcount<=rootcount+1;  
                        --temp = Q16.16                                            
                   elsif rootcount = "010" then
                        temp2 := temp(17 downto 0);
                        --temp2 = Q2.16
                        v_y_sq_full  <= temp2 * temp2;
                        halfnum <= shift_right(unsigned(num),1);
                        --v_y_sq_full = Q4.32
                        rootcount<=rootcount+1;
                   elsif rootcount = "011" then
                        
                        -- halfnum = Q3.15    
                        v_term1_full <= halfnum * v_y_sq_full(35 downto 18);
                        -- v_term1_full = Q7.29
                        rootcount<=rootcount+1;
                   elsif rootcount = "100" then
                        v_diff:= "00" & x"0c00" - v_term1_full(35 downto 18);
                        -- v_diff = Q7.11
                        temp2:= temp(17 downto 0);
                        -- temp2 = Q2.16
                        v_final_full := temp2 * v_diff;
                        -- v_final_full = Q9.27
                        tempvar:= unsigned(v_final_full);
                        temp <= tempvar;
                        -- temp updates with Q9.27
                        rootcount<=rootcount+1;      
                   elsif rootcount = "101" then
                         if halfnum = (halfnum'range => '0') then
                             -- input was zero-length vec; return ~1/sqrt(0.5) as sentinel
                             ans <= to_sfixed(std_logic_vector'("01" & x"6a09"), ans'left, ans'right);
                         else
                             temp2 := temp(35 downto 18);
                             -- temp2 = Q9.9 (unsigned bits)
                             ans <= to_sfixed(std_logic_vector(temp2), ans'left, ans'right);
                             -- ans = sfixed(8 downto -9)
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
