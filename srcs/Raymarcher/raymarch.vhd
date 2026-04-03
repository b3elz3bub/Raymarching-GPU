library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity raymarch is
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        -- inputs from Person 2
        ray_orig_x : in  signed(31 downto 0);
        ray_orig_y : in  signed(31 downto 0);
        ray_orig_z : in  signed(31 downto 0);
        ray_dir_x  : in  signed(31 downto 0);
        ray_dir_y  : in  signed(31 downto 0);
        ray_dir_z  : in  signed(31 downto 0);
        -- outputs to Person 4
        done       : out std_logic;
        hit        : out std_logic;
        obj_id     : out unsigned(2 downto 0);
        hit_x      : out signed(31 downto 0);
        hit_y      : out signed(31 downto 0);
        hit_z      : out signed(31 downto 0)
    );
end raymarch;

architecture Behavioral of raymarch is

    -- ── Q16.16 constants ──────────────────────────────────────
    constant ONE      : signed(31 downto 0) := to_signed( 65536,   32); -- 1.0
    constant HALF     : signed(31 downto 0) := to_signed( 32768,   32); -- 0.5
    constant RADIUS   : signed(31 downto 0) := to_signed( 26214,   32); -- 0.4
    constant PLANE_Y  : signed(31 downto 0) := to_signed(-65536,   32); -- -1.0
    constant HIT_DIST : signed(31 downto 0) := to_signed( 328,     32); -- 0.005
    constant MAX_DIST : signed(31 downto 0) := to_signed( 1310720, 32); -- 20.0
    constant AMBIENT  : signed(31 downto 0) := to_signed( 9830,    32); -- 0.15

    -- ── sphere center constants in Q16.16 ─────────────────────
    -- four spheres, all at y=-0.6, z=0.0
    -- x positions: -1.5, -0.5, 0.5, 1.5
    constant SP0_X : signed(31 downto 0) := to_signed(-98304, 32); -- -1.5
    constant SP1_X : signed(31 downto 0) := to_signed(-32768, 32); -- -0.5
    constant SP2_X : signed(31 downto 0) := to_signed( 32768, 32); --  0.5
    constant SP3_X : signed(31 downto 0) := to_signed( 98304, 32); --  1.5
    constant SP_Y  : signed(31 downto 0) := to_signed(-39322, 32); -- -0.6
    constant SP_Z  : signed(31 downto 0) := to_signed(     0, 32); --  0.0

    -- ─────────────────────────────────────────────────────────
    -- FUNCTIONS
    -- ─────────────────────────────────────────────────────────

    -- ── fp_mul ────────────────────────────────────────────────
    -- multiplies two Q16.16 signed fixed point numbers
    -- result is also Q16.16
    -- internally uses 64 bit intermediate to avoid overflow
    function fp_mul(a : signed(31 downto 0);
                    b : signed(31 downto 0)) return signed is
        variable tmp : signed(63 downto 0);
    begin
        tmp := a * b;
        return tmp(47 downto 16);
    end function;

    -- ── sdf_plane ─────────────────────────────────────────────
    -- ground plane fixed at y = -1.0
    -- distance from any point to the plane = point_y - (-1.0)
    --                                      = point_y + 1.0
    -- positive = above plane
    -- zero     = on the plane
    -- negative = below the plane
    function sdf_plane(py : signed(31 downto 0)) return signed is
    begin
        return py + ONE;
    end function;

    -- ─────────────────────────────────────────────────────────
    -- SIGNALS
    -- (will be expanded as we add the march loop)
    -- ─────────────────────────────────────────────────────────

begin

    -- state machine process will go here in the next step

end Behavioral;
