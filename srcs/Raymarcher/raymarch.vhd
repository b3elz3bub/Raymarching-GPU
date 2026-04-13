-- ============================================================================
-- raymarch.vhd — Sphere-marching engine
--
-- Iteratively steps along a ray, evaluating the scene SDF at each point.
-- Scene: sphere + ground plane.
-- Uses invsqrt for sphere-distance calculation.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.FIXED_PKG.ALL;
use work.params_pkg.all;

entity raymarch is
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        -- Ray origin   [pos_t = Q6.12]
        ray_orig_x : in  pos_t;
        ray_orig_y : in  pos_t;
        ray_orig_z : in  pos_t;
        -- Ray direction [dir_t = Q2.16]
        ray_dir_x  : in  dir_t;
        ray_dir_y  : in  dir_t;
        ray_dir_z  : in  dir_t;
        -- Outputs to shader
        done       : out std_logic;
        hit        : out std_logic;
        obj_id     : out unsigned(2 downto 0);
        hit_x      : out pos_t;
        hit_y      : out pos_t;
        hit_z      : out pos_t;
        march_t    : out pos_t;
        -- Surface normal at hit point [dir_t = Q2.16]
        norm_x     : out dir_t;
        norm_y     : out dir_t;
        norm_z     : out dir_t
    );
end raymarch;

architecture Behavioral of raymarch is

    -- ─────────────────────────────────────────────────────────
    -- LOCAL CONSTANTS (not shared — raymarch-specific)
    -- ─────────────────────────────────────────────────────────
    constant ONE : pos_t := to_sfixed(1.0, 5, -12);

    -- ─────────────────────────────────────────────────────────
    -- COMPONENT — invsqrt (raymarch uses Q12.6 input → Q4.14 output)
    -- ─────────────────────────────────────────────────────────
    component invsqrt
        Port (
            clk   : in  std_logic;
            start : in  std_logic;
            x     : in  sos_t;
            ans   : out inv_t;
            done  : out std_logic
        );
    end component;

    -- ─────────────────────────────────────────────────────────
    -- MULTIPLY FUNCTIONS (each 18×18 → single DSP block)
    -- ─────────────────────────────────────────────────────────
    function fp_mul_pos(a : pos_t; b : pos_t) return pos_t is
    begin return resize(a * b, 5, -12); end function;

    function fp_mul_dir(a : dir_t; b : pos_t) return pos_t is
    begin return resize(a * b, 5, -12); end function;

    function fp_mul_sos(a : sos_t; b : inv_t) return pos_t is
    begin return resize(a * b, 5, -12); end function;

    function fp_mul_norm(a : pos_t; b : inv_t) return dir_t is
    begin return resize(a * b, 1, -16); end function;

    -- ─────────────────────────────────────────────────────────
    -- SCENE FUNCTIONS
    -- ─────────────────────────────────────────────────────────
    function sdf_plane(py : pos_t) return pos_t is
    begin return resize(py + PLANE_HEIGHT, 5, -12); end function;

    function sum_of_sq(px, py, pz : pos_t) return sos_t is
        variable dx, dy, dz : pos_t;
    begin
        dx := resize(px - SPHERE_CX, 5, -12);
        dy := resize(py - SPHERE_CY, 5, -12);
        dz := resize(pz - SPHERE_CZ, 5, -12);
        return resize(fp_mul_pos(dx,dx) + fp_mul_pos(dy,dy) + fp_mul_pos(dz,dz), 11, -6);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    type state_t is (IDLE, INIT, COMPUTE_SOS, WAIT_INVSQRT,
                     EVAL_SDF, CHECK_HIT, OUTPUT_RESULT);
    signal state : state_t := IDLE;

    -- Current march point & total distance
    signal curr_x, curr_y, curr_z : pos_t := (others => '0');
    signal t          : pos_t := (others => '0');
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- Invsqrt interface
    signal invsqrt_start : std_logic := '0';
    signal invsqrt_in    : sos_t     := (others => '0');
    signal invsqrt_out   : inv_t     := (others => '0');
    signal invsqrt_done  : std_logic;

    -- SDF intermediates
    signal d_plane, d_sphere, d_min : pos_t := (others => '0');
    signal sum_sq : sos_t := (others => '0');

    -- Result registers
    signal hit_reg : std_logic            := '0';
    signal obj_reg : unsigned(2 downto 0) := (others => '0');

    -- Sphere normal (computed in WAIT_INVSQRT, valid at hit)
    signal norm_sphere_x, norm_sphere_y, norm_sphere_z : dir_t := (others => '0');

    -- Range-reduction flag
    signal scaled : std_logic := '0';

begin

    INVSQRT_UNIT : invsqrt
        port map (clk => clk, start => invsqrt_start,
                  x => invsqrt_in, ans => invsqrt_out, done => invsqrt_done);

    -- ─────────────────────────────────────────────────────────
    -- MAIN PROCESS
    -- ─────────────────────────────────────────────────────────
    process(clk)
        variable v_sq  : sos_t;
        variable v_inv : inv_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                done          <= '0';
                hit           <= '0';
                invsqrt_start <= '0';
                norm_x        <= (others => '0');
                norm_y        <= (others => '0');
                norm_z        <= (others => '0');
            else
                case state is

                -- ── IDLE ─────────────────────────────────────
                when IDLE =>
                    done          <= '0';
                    invsqrt_start <= '0';
                    if start = '1' then
                        state <= INIT;
                    end if;

                -- ── INIT ─────────────────────────────────────
                when INIT =>
                    curr_x     <= ray_orig_x;
                    curr_y     <= ray_orig_y;
                    curr_z     <= ray_orig_z;
                    t          <= to_sfixed(0.0, 5, -12);
                    step_count <= (others => '0');
                    hit_reg    <= '0';
                    state      <= COMPUTE_SOS;

                -- ── COMPUTE_SOS ──────────────────────────────
                when COMPUTE_SOS =>
                    v_sq    := sum_of_sq(curr_x, curr_y, curr_z);
                    d_plane <= sdf_plane(curr_y);
                    sum_sq  <= v_sq;

                    if v_sq > SOS_HI then
                        d_sphere      <= FAR_SPHERE;
                        invsqrt_start <= '0';
                        scaled        <= '0';
                        state         <= EVAL_SDF;
                    elsif v_sq > SOS_LO then
                        invsqrt_in    <= shift_right(v_sq, 6);
                        invsqrt_start <= '1';
                        scaled        <= '1';
                        state         <= WAIT_INVSQRT;
                    else
                        invsqrt_in    <= v_sq;
                        invsqrt_start <= '1';
                        scaled        <= '0';
                        state         <= WAIT_INVSQRT;
                    end if;

                -- ── WAIT_INVSQRT ─────────────────────────────
                when WAIT_INVSQRT =>
                    invsqrt_start <= '0';
                    if invsqrt_done = '1' then
                        if scaled = '1' then
                            v_inv := shift_right(invsqrt_out, 3);
                        else
                            v_inv := invsqrt_out;
                        end if;

                        d_sphere <= resize(fp_mul_sos(sum_sq, v_inv) - SPHERE_R, 5, -12);

                        norm_sphere_x <= fp_mul_norm(resize(curr_x - SPHERE_CX, 5, -12), v_inv);
                        norm_sphere_y <= fp_mul_norm(resize(curr_y - SPHERE_CY, 5, -12), v_inv);
                        norm_sphere_z <= fp_mul_norm(resize(curr_z - SPHERE_CZ, 5, -12), v_inv);
                        state         <= EVAL_SDF;
                    end if;

                -- ── EVAL_SDF ─────────────────────────────────
                when EVAL_SDF =>
                    if d_sphere < d_plane then
                        d_min   <= d_sphere;
                        obj_reg <= "001";   -- sphere
                    else
                        d_min   <= d_plane;
                        obj_reg <= "000";   -- plane
                    end if;
                    state <= CHECK_HIT;

                -- ── CHECK_HIT ────────────────────────────────
                when CHECK_HIT =>
                    if d_min < HIT_DIST then
                        hit_reg <= '1';
                        state   <= OUTPUT_RESULT;
                    elsif t > MAX_DIST then
                        hit_reg <= '0';
                        state   <= OUTPUT_RESULT;
                    elsif step_count = MAX_MARCH_STEPS then
                        hit_reg <= '0';
                        state   <= OUTPUT_RESULT;
                    else
                        curr_x     <= resize(curr_x + fp_mul_dir(ray_dir_x, d_min), 5, -12);
                        curr_y     <= resize(curr_y + fp_mul_dir(ray_dir_y, d_min), 5, -12);
                        curr_z     <= resize(curr_z + fp_mul_dir(ray_dir_z, d_min), 5, -12);
                        t          <= resize(t + d_min, 5, -12);
                        step_count <= step_count + 1;
                        state      <= COMPUTE_SOS;
                    end if;

                -- ── OUTPUT_RESULT ────────────────────────────
                when OUTPUT_RESULT =>
                    hit    <= hit_reg;
                    obj_id <= obj_reg;
                    hit_x  <= curr_x;
                    hit_y  <= curr_y;
                    hit_z  <= curr_z;
                    march_t <= t;
                    if obj_reg = "001" then
                        norm_x <= norm_sphere_x;
                        norm_y <= norm_sphere_y;
                        norm_z <= norm_sphere_z;
                    else
                        norm_x <= PLANE_NX;
                        norm_y <= PLANE_NY;
                        norm_z <= PLANE_NZ;
                    end if;
                    done  <= '1';
                    state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
