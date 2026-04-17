library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.params_pkg.all;

entity debouncer is
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        button    : in  std_logic;
        debounced : out std_logic
    );
end entity debouncer;

architecture rtl of debouncer is
    signal counter       : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal debounced_reg : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter       <= 0;
                debounced_reg <= '0';
            else
                if button = '1' then
                    if counter < DEBOUNCE_CYCLES then
                        counter <= counter + 1;
                    end if;
                    if counter = DEBOUNCE_CYCLES then
                        debounced_reg <= '1';
                    end if;
                else
                    counter       <= 0;
                    debounced_reg <= '0';
                end if;
            end if;
        end if;
    end process;
    debounced <= debounced_reg;
end architecture rtl;