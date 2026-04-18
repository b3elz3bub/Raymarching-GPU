library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use ieee.math_real.all;

package params_pkg is

    -- ═══════════════════════════════════════════════════════════════
    -- FIXED-POINT SUBTYPES  (used uniformly across all modules)
    -- ═══════════════════════════════════════════════════════════════
    subtype pos_t is sfixed(5  downto -12);  -- Q6.12, 18-bit: positions, distances
    subtype dir_t is sfixed(1  downto -16);  -- Q2.16, 18-bit: ray directions, normals
    subtype col_t is sfixed(1  downto -10);  -- Q2.10, 12-bit: color channel [0..~1.0]
    subtype sos_t is sfixed(11 downto  -6);  -- Q12.6, 18-bit: sum-of-squares
    subtype inv_t is sfixed(3  downto -14);  -- Q4.14, 18-bit: invsqrt output

    -- ═══════════════════════════════════════════════════════════════
    -- SCREEN & FRAMEBUFFER
    -- ═══════════════════════════════════════════════════════════════
    constant SCREEN_WIDTH  : integer := 640;
    constant SCREEN_HEIGHT : integer := 480;
    constant COLOR_DEPTH   : integer := 12;  -- RGB444

    -- Framebuffer address width: clog2(640*480) = 19 bits
    constant FB_ADDR_WIDTH : integer := 19;

    -- ═══════════════════════════════════════════════════════════════
    -- SUN DIRECTION  (normalized at elaboration time)
    -- ═══════════════════════════════════════════════════════════════
    constant SUN_RAW_X : real := 0.7;
    constant SUN_RAW_Y : real := 1.0;
    constant SUN_RAW_Z : real := -0.4;
    constant SUN_INV_LEN : real := 1.0 / sqrt(
        SUN_RAW_X * SUN_RAW_X + SUN_RAW_Y * SUN_RAW_Y + SUN_RAW_Z * SUN_RAW_Z
    );
    constant SUN_DIR_X : pos_t := to_sfixed(SUN_RAW_X * SUN_INV_LEN, 5, -12);
    constant SUN_DIR_Y : pos_t := to_sfixed(SUN_RAW_Y * SUN_INV_LEN, 5, -12);
    constant SUN_DIR_Z : pos_t := to_sfixed(SUN_RAW_Z * SUN_INV_LEN, 5, -12);

    -- ═══════════════════════════════════════════════════════════════
    -- SCENE GEOMETRY
    -- ═══════════════════════════════════════════════════════════════
    -- Sphere center & radius
    constant SPHERE_CX : pos_t := to_sfixed(0.0, 5, -12);
    constant SPHERE_CY : pos_t := to_sfixed(0.5, 5, -12);
    constant SPHERE_CZ : pos_t := to_sfixed(3.0, 5, -12);
    constant SPHERE_R  : pos_t := to_sfixed(0.5, 5, -12);

    -- Ground plane: y = 0  (sdf_plane(py) = py)
    constant PLANE_HEIGHT : pos_t := to_sfixed(0.0, 5, -12);

    -- Plane normal (constant, always up)
    constant PLANE_NX : dir_t := to_sfixed(0.0, 1, -16);
    constant PLANE_NY : dir_t := to_sfixed(1.0, 1, -16);
    constant PLANE_NZ : dir_t := to_sfixed(0.0, 1, -16);

    -- ═══════════════════════════════════════════════════════════════
    -- RAYMARCHING PARAMETERS
    -- ═══════════════════════════════════════════════════════════════
    constant HIT_DIST       : pos_t := to_sfixed(0.003, 5, -12);
    constant MAX_DIST       : pos_t := to_sfixed(20.0,  5, -12);
    constant MAX_MARCH_STEPS : integer := 63;

    -- Range-reduction thresholds for invsqrt (max input ≈ 7)
    constant SOS_LO     : sos_t := to_sfixed(  7.0, 11, -6);
    constant SOS_HI     : sos_t := to_sfixed(448.0, 11, -6);
    constant FAR_SPHERE : pos_t := to_sfixed(20.0,  5, -12);

    -- ═══════════════════════════════════════════════════════════════
    -- CAMERA DEFAULTS
    -- ═══════════════════════════════════════════════════════════════
    constant CAM_INIT_X : pos_t := to_sfixed(0.0,  5, -12);
    constant CAM_INIT_Y : pos_t := to_sfixed(1.5,  5, -12);
    constant CAM_INIT_Z : pos_t := to_sfixed(-5.0, 5, -12);
    constant CAM_STEP   : pos_t := to_sfixed(0.1,  5, -12);

    -- ═══════════════════════════════════════════════════════════════
    -- CLOCK & DEBOUNCE
    -- ═══════════════════════════════════════════════════════════════
    constant CLK_FREQ        : integer := 100_000_000;
    constant DEBOUNCE_CYCLES : integer := CLK_FREQ / 50;   -- 20ms debounce
    constant CAM_REPEAT_CYCLES : integer := CLK_FREQ / 5;  -- 200ms repeat rate

    -- ═══════════════════════════════════════════════════════════════
    -- UTILITY FUNCTIONS
    -- ═══════════════════════════════════════════════════════════════
    function clog2 (depth : in natural) return integer;

end package params_pkg;

-- ═══════════════════════════════════════════════════════════════
-- PACKAGE BODY
-- ═══════════════════════════════════════════════════════════════
package body params_pkg is
    function clog2(depth : in natural) return integer is
        variable v : natural := depth - 1;
        variable r : integer := 0;
    begin
        while v > 0 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;
end package body params_pkg;