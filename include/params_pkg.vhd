library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.math_real.all;

package params_pkg is
    --Constants
    constant SCREEN_WIDTH  : integer := 640;
    constant SCREEN_HEIGHT : integer := 480;
    constant COLOR_DEPTH   : integer := 12;
   constant SUN_RAW_X : real := 0.7;
    constant SUN_RAW_Y : real := 1.0;
    constant SUN_RAW_Z : real := -0.4;
    constant SUN_INV_LEN : real := 1.0 / sqrt(
        SUN_RAW_X * SUN_RAW_X + SUN_RAW_Y * SUN_RAW_Y + SUN_RAW_Z * SUN_RAW_Z
    );
    constant SUN_DIR_X : sfixed(5 downto -12) := to_sfixed(SUN_RAW_X * SUN_INV_LEN, 5, -12);
    constant SUN_DIR_Y : sfixed(5 downto -12) := to_sfixed(SUN_RAW_Y * SUN_INV_LEN, 5, -12);
    constant SUN_DIR_Z : sfixed(5 downto -12) := to_sfixed(SUN_RAW_Z * SUN_INV_LEN, 5, -12);

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