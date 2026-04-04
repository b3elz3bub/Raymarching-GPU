library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.FIXED_PKG.ALL;

entity raymarch is
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        -- inputs from Person 2
        ray_orig_x : in  sfixed(15 downto -16);
        ray_orig_y : in  sfixed(15 downto -16);
        ray_orig_z : in  sfixed(15 downto -16);
        ray_dir_x  : in  sfixed(15 downto -16);
        ray_dir_y  : in  sfixed(15 downto -16);
        ray_dir_z  : in  sfixed(15 downto -16);
        -- outputs to Person 4
        done       : out std_logic;
        hit        : out std_logic;
        obj_id     : out unsigned(2 downto 0);
        hit_x      : out sfixed(15 downto -16);
        hit_y      : out sfixed(15 downto -16);
        hit_z      : out sfixed(15 downto -16)
    );
end raymarch;

architecture Behavioral of raymarch is

    -- ─────────────────────────────────────────────────────────
    -- TYPE ALIAS
    -- sfixed(15 downto -16) = 16 integer bits + 16 fractional bits
    -- = 32 bits total, equivalent to our old Q16.16
    -- positive index = integer part, negative index = fractional part
    -- ─────────────────────────────────────────────────────────
    subtype fixed32 is sfixed(15 downto -16);

    -- ── constants ─────────────────────────────────────────────
    -- notice: we just write the real value directly, no more x*65536
    constant ONE      : fixed32 := to_sfixed( 1.0,   15, -16);
    constant HALF     : fixed32 := to_sfixed( 0.5,   15, -16);
    constant RADIUS   : fixed32 := to_sfixed( 0.4,   15, -16);
    constant PLANE_Y  : fixed32 := to_sfixed(-1.0,   15, -16);
    constant HIT_DIST : fixed32 := to_sfixed( 0.005, 15, -16);
    constant MAX_DIST : fixed32 := to_sfixed(20.0,   15, -16);
    constant AMBIENT  : fixed32 := to_sfixed( 0.15,  15, -16);

    -- ── sphere center constants ───────────────────────────────
    -- four spheres, all at y=-0.6, z=0.0
    -- x positions: -1.5, -0.5, 0.5, 1.5
    constant SP0_X : fixed32 := to_sfixed(-1.5, 15, -16);
    constant SP1_X : fixed32 := to_sfixed(-0.5, 15, -16);
    constant SP2_X : fixed32 := to_sfixed( 0.5, 15, -16);
    constant SP3_X : fixed32 := to_sfixed( 1.5, 15, -16);
    constant SP_Y  : fixed32 := to_sfixed(-0.6, 15, -16);
    constant SP_Z  : fixed32 := to_sfixed( 0.0, 15, -16);

    -- ─────────────────────────────────────────────────────────
    -- FUNCTIONS
    -- ─────────────────────────────────────────────────────────

    -- ── fp_mul ────────────────────────────────────────────────
    -- with sfixed the multiply automatically tracks the binary point
    -- a * b gives sfixed(31 downto -32) — 64 bits
    -- resize brings it back to fixed32 — 32 bits
    -- no manual bit slicing needed unlike the signed version
    function fp_mul(a : fixed32;
                    b : fixed32) return fixed32 is
    begin
        return resize(a * b, 15, -16);
    end function;

    -- ── sdf_plane ─────────────────────────────────────────────
    -- ground plane fixed at y = -1.0
    -- distance = point_y - (-1.0) = point_y + 1.0
    -- positive = above plane
    -- zero     = on the plane
    -- negative = below the plane
    function sdf_plane(py : fixed32) return fixed32 is
    begin
        return resize(py + ONE, 15, -16);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- SIGNALS
    -- (will be expanded as we add fp_length, sdf_sphere,
    --  sdf_scene and the march loop)
    -- ─────────────────────────────────────────────────────────

begin

    -- state machine process will go here in the next step

end Behavioral;
