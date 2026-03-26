library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package params_pkg is
    --Constants
    constant SCREEN_WIDTH  : integer := 640;
    constant SCREEN_HEIGHT : integer := 480;
    constant COLOR_DEPTH   : integer := 16;
    --Functions
    function clog2 (depth: in natural) return integer;
end package params_pkg;

--Function Definitions
package body params_pkg is
    function clog2 (depth: in natural) return integer is
        variable temp    : integer := depth;
        variable ret_val : integer := 0;
    begin
        while temp > 1 loop
            ret_val := ret_val + 1;
            temp    := temp / 2;
        end loop;
        return ret_val;
    end function;
end package body params_pkg;