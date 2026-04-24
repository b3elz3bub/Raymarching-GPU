-- ============================================================================
-- raymarch.vhd — Sphere-marching engine
--
-- Iteratively steps along a ray, evaluating the scene SDF at each point.
-- Scene: 4 spheres + ground plane.
-- Uses 4 parallel invsqrt units for simultaneous sphere-distance calculation.
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
    -- COMPONENT — invsqrt
    -- ─────────────────────────────────────────────────────────
    component invsqrt
        Port (
            clk   : in  std_logic;
            start : in  std_logic;
            x     : in  std_logic_vector(17 downto 0);
            ans   : out sfixed(8 downto -9);
            done  : out std_logic
        );
    end component;

    -- ─────────────────────────────────────────────────────────
    -- MULTIPLY FUNCTIONS
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

    function sum_of_sq(px, py, pz : pos_t; idx : integer) return sos_t is
        variable dx, dy, dz : pos_t;
    begin
        dx := resize(px - SPHERE_CX(idx), 5, -12);
        dy := resize(py - SPHERE_CY(idx), 5, -12);
        dz := resize(pz - SPHERE_CZ(idx), 5, -12);
        return resize(dx*dx + dy*dy + dz*dz, 11, -6);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- ARRAY TYPES for parallel sphere evaluation
    -- ─────────────────────────────────────────────────────────
    type sos_array_t   is array (0 to NUM_SPHERES-1) of sos_t;
    type pos_array_t   is array (0 to NUM_SPHERES-1) of pos_t;
    type dir_array_t   is array (0 to NUM_SPHERES-1) of dir_t;
    type inv_array_t   is array (0 to NUM_SPHERES-1) of inv_t;
    type slv18_array_t is array (0 to NUM_SPHERES-1) of std_logic_vector(17 downto 0);
    type shift_array_t is array (0 to NUM_SPHERES-1) of unsigned(1 downto 0);
    type sfx9_array_t  is array (0 to NUM_SPHERES-1) of sfixed(8 downto -9);

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    type state_t is (IDLE, INIT, COMPUTE_SOS, WAIT_INVSQRT,
                     COMPUTE_DIST, EVAL_SDF, CHECK_HIT, OUTPUT_RESULT);
    signal state : state_t := IDLE;

    -- Current march point & total distance
    signal curr_x, curr_y, curr_z : pos_t := (others => '0');
    signal t          : pos_t := (others => '0');
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- Per-sphere invsqrt signals
    signal invsqrt_start_arr : std_logic_vector(NUM_SPHERES-1 downto 0) := (others => '0');
    signal invsqrt_done_arr  : std_logic_vector(NUM_SPHERES-1 downto 0);
    signal invsqrt_hw_in_arr : slv18_array_t;
    signal invsqrt_hw_out_arr : sfx9_array_t;
    signal invsqrt_out_arr   : inv_array_t;

    -- Per-sphere SDF data
    signal sum_sq_arr      : sos_array_t;
    signal scale_shift_arr : shift_array_t := (others => "00");
    signal skip_arr        : std_logic_vector(NUM_SPHERES-1 downto 0) := (others => '0');
    signal d_sphere_arr    : pos_array_t := (others => (others => '0'));

    -- Per-sphere normals
    signal norm_x_arr, norm_y_arr, norm_z_arr : dir_array_t := (others => (others => '0'));

    -- Ground plane distance
    signal d_plane : pos_t := (others => '0');
    signal d_min   : pos_t := (others => '0');

    -- Result registers
    signal hit_reg  : std_logic            := '0';
    signal obj_reg  : unsigned(2 downto 0) := (others => '0');
    signal best_norm_x, best_norm_y, best_norm_z : dir_t := (others => '0');

    -- All-done combinational signal
    signal all_done : std_logic;

begin

    -- ─────────────────────────────────────────────────────────
    -- GENERATE 4 PARALLEL INVSQRT UNITS
    -- ─────────────────────────────────────────────────────────
    GEN_INVSQRT: for i in 0 to NUM_SPHERES-1 generate
        -- Output format conversion: Q9.9 → Q4.14
        invsqrt_out_arr(i) <= to_sfixed(
            std_logic_vector(invsqrt_hw_out_arr(i)(3 downto -9)) & "00000",
            inv_t'left, inv_t'right);

        INVSQRT_I : invsqrt
            port map (
                clk   => clk,
                start => invsqrt_start_arr(i),
                x     => invsqrt_hw_in_arr(i),
                ans   => invsqrt_hw_out_arr(i),
                done  => invsqrt_done_arr(i)
            );
    end generate;

    -- All spheres complete when each is either done or skipped
    all_done <= '1' when (invsqrt_done_arr or skip_arr) = "1111" else '0';

    -- ─────────────────────────────────────────────────────────
    -- MAIN PROCESS
    -- ─────────────────────────────────────────────────────────
    process(clk)
        variable v_sq    : sos_t;
        variable v_inv   : inv_t;
        variable v_min_d : pos_t;
        variable v_min_id : integer range 0 to NUM_SPHERES-1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state            <= IDLE;
                done             <= '0';
                hit              <= '0';
                invsqrt_start_arr <= (others => '0');
                norm_x           <= (others => '0');
                norm_y           <= (others => '0');
                norm_z           <= (others => '0');
            else
                case state is

                -- ── IDLE ─────────────────────────────────────
                when IDLE =>
                    done             <= '0';
                    invsqrt_start_arr <= (others => '0');
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
                -- Compute sum-of-squares for ALL 4 spheres in parallel,
                -- set up all 4 invsqrt inputs, compute ground plane distance.
                when COMPUTE_SOS =>
                    d_plane <= sdf_plane(curr_y);

                    for i in 0 to NUM_SPHERES-1 loop
                        v_sq := sum_of_sq(curr_x, curr_y, curr_z, i);
                        sum_sq_arr(i) <= v_sq;

                        if v_sq > SOS_HI then
                            skip_arr(i)           <= '1';
                            d_sphere_arr(i)       <= FAR_SPHERE;
                            invsqrt_start_arr(i)  <= '0';
                            scale_shift_arr(i)    <= "00";
                        elsif v_sq > SOS_MED then
                            invsqrt_hw_in_arr(i)  <= std_logic_vector(v_sq(8 downto -6)) & "000";
                            invsqrt_start_arr(i)  <= '1';
                            scale_shift_arr(i)    <= "11";
                            skip_arr(i)           <= '0';
                        elsif v_sq > SOS_LO then
                            invsqrt_hw_in_arr(i)  <= std_logic_vector(v_sq(4 downto -6)) & "0000000";
                            invsqrt_start_arr(i)  <= '1';
                            scale_shift_arr(i)    <= "01";
                            skip_arr(i)           <= '0';
                        else
                            invsqrt_hw_in_arr(i)  <= std_logic_vector(v_sq(2 downto -6)) & "000000000";
                            invsqrt_start_arr(i)  <= '1';
                            scale_shift_arr(i)    <= "00";
                            skip_arr(i)           <= '0';
                        end if;
                    end loop;

                    state <= WAIT_INVSQRT;

                -- ── WAIT_INVSQRT ─────────────────────────────
                -- Wait for all 4 invsqrt units to finish (or be skipped)
                when WAIT_INVSQRT =>
                    invsqrt_start_arr <= (others => '0');
                    if all_done = '1' then
                        state <= COMPUTE_DIST;
                    end if;

                -- ── COMPUTE_DIST ─────────────────────────────
                -- Compute sphere distances and normals from invsqrt results
                when COMPUTE_DIST =>
                    for i in 0 to NUM_SPHERES-1 loop
                        if skip_arr(i) = '0' then
                            case scale_shift_arr(i) is
                                when "11"   => v_inv := shift_right(invsqrt_out_arr(i), 3);
                                when "01"   => v_inv := shift_right(invsqrt_out_arr(i), 1);
                                when others => v_inv := invsqrt_out_arr(i);
                            end case;

                            d_sphere_arr(i) <= resize(
                                fp_mul_sos(sum_sq_arr(i), v_inv) - SPHERE_R(i), 5, -12);

                            norm_x_arr(i) <= fp_mul_norm(
                                resize(curr_x - SPHERE_CX(i), 5, -12), v_inv);
                            norm_y_arr(i) <= fp_mul_norm(
                                resize(curr_y - SPHERE_CY(i), 5, -12), v_inv);
                            norm_z_arr(i) <= fp_mul_norm(
                                resize(curr_z - SPHERE_CZ(i), 5, -12), v_inv);
                        end if;
                    end loop;
                    state <= EVAL_SDF;

                -- ── EVAL_SDF ─────────────────────────────────
                -- Find minimum sphere distance, compare with ground plane
                when EVAL_SDF =>
                    v_min_d  := d_sphere_arr(0);
                    v_min_id := 0;
                    for i in 1 to NUM_SPHERES-1 loop
                        if d_sphere_arr(i) < v_min_d then
                            v_min_d  := d_sphere_arr(i);
                            v_min_id := i;
                        end if;
                    end loop;

                    if v_min_d < d_plane then
                        d_min   <= v_min_d;
                        obj_reg <= to_unsigned(v_min_id + 1, 3);
                        best_norm_x <= norm_x_arr(v_min_id);
                        best_norm_y <= norm_y_arr(v_min_id);
                        best_norm_z <= norm_z_arr(v_min_id);
                    else
                        d_min   <= d_plane;
                        obj_reg <= "000";
                    end if;
                    state <= CHECK_HIT;

                -- ── CHECK_HIT ────────────────────────────────
                when CHECK_HIT =>
                    if d_min < HIT_DIST then
                        hit_reg <= '1';
                        state   <= OUTPUT_RESULT;
                    elsif t > MAX_DIST or t < to_sfixed(0.0, 5, -12) then
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
                    hit     <= hit_reg;
                    obj_id  <= obj_reg;
                    hit_x   <= curr_x;
                    hit_y   <= curr_y;
                    hit_z   <= curr_z;
                    march_t <= t;
                    if obj_reg /= "000" then
                        norm_x <= best_norm_x;
                        norm_y <= best_norm_y;
                        norm_z <= best_norm_z;
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