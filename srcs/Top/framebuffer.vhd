library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.params_pkg.all;

entity framebuffer is
    port (
        wr_clk     : in  std_logic;
        rd_clk     : in  std_logic;
        
        rd_addr    : in  std_logic_vector(clog2(SCREEN_WIDTH * SCREEN_HEIGHT) - 1 downto 0);
        wr_addr    : in  std_logic_vector(clog2(SCREEN_WIDTH * SCREEN_HEIGHT) - 1 downto 0);
        
        write_data : in  std_logic_vector(COLOR_DEPTH - 1 downto 0);
        write_en   : in  std_logic;
        read_data : out std_logic_vector(COLOR_DEPTH - 1 downto 0);
    );
end entity framebuffer;

architecture rtl of framebuffer is

    constant DEPTH : integer := SCREEN_WIDTH * SCREEN_HEIGHT;
    type ram_type is array (0 to DEPTH - 1) of std_logic_vector(COLOR_DEPTH - 1 downto 0);
    
    signal stored_data : ram_type;

    attribute ram_style : string;
    attribute ram_style of stored_data : signal is "block";

begin

    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            read_data <= stored_data(to_integer(unsigned(rd_addr)));
        end if;
    end process;

    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if write_en = '1' then
                stored_data(to_integer(unsigned(wr_addr))) <= write_data;
            end if;
        end if;
    end process;

end architecture rtl;