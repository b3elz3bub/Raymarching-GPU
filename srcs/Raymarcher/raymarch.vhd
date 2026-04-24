-- ============================================================================
-- raymarch.vhd — Sphere-marching engine
--
-- Iteratively steps along a ray, evaluating the scene SDF at each point.
-- Scene: 4 spheres + ground plane.
-- Uses invsqrt for sphere-distance calculation.
-- Spheres are evaluated sequentially (one invsqrt unit reused).
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
    -- COMPONENT — invsqrt (hardware module expects Q3.15 input → Q9.9 output)
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

    -- Sum-of-squares for a specific sphere index
    function sum_of_sq(px, py, pz : pos_t; idx : integer) return sos_t is
        variable dx, dy, dz : pos_t;
    begin
        dx := resize(px - SPHERE_CX(idx), 5, -12);
        dy := resize(py - SPHERE_CY(idx), 5, -12);
        dz := resize(pz - SPHERE_CZ(idx), 5, -12);
        return resize(dx*dx + dy*dy + dz*dz, 11, -6);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    type state_t is (IDLE, INIT, COMPUTE_SOS, WAIT_INVSQRT,
                     STORE_SPHERE, EVAL_SDF, CHECK_HIT, OUTPUT_RESULT);
    signal state : state_t := IDLE;

    -- Current march point & total distance
    signal curr_x, curr_y, curr_z : pos_t := (others => '0');
    signal t          : pos_t := (others => '0');
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- Sphere iteration index (0 to NUM_SPHERES-1)
    signal sphere_idx : integer range 0 to NUM_SPHERES-1 := 0;

    -- Best (minimum) sphere distance and its index
    signal best_sphere_d : pos_t := (others => '0');
    signal best_sphere_id : integer range 0 to NUM_SPHERES-1 := 0;
    -- Best sphere normal (saved when we find a closer sphere)
    signal best_norm_x, best_norm_y, best_norm_z : dir_t := (others => '0');

    -- Invsqrt interface
    signal invsqrt_start  : std_logic := '0';
    signal invsqrt_in     : sos_t     := (others => '0');  -- Q12.6
    signal invsqrt_out    : inv_t     := (others => '0');  -- Q4.14
    signal invsqrt_done   : std_logic;

    -- Hardware bindings
    signal invsqrt_hw_in  : std_logic_vector(17 downto 0);
    signal invsqrt_hw_out : sfixed(8 downto -9);

    -- SDF intermediates
    signal d_plane, d_sphere, d_min : pos_t := (others => '0');
    signal sum_sq : sos_t := (others => '0');

    -- Result registers
    signal hit_reg : std_logic            := '0';
    signal obj_reg : unsigned(2 downto 0) := (others => '0');

    -- Current sphere normal (computed in WAIT_INVSQRT for current sphere)
    signal norm_sphere_x, norm_sphere_y, norm_sphere_z : dir_t := (others => '0');

    -- Range-reduction shift amount (00=unscaled, 01=÷4, 11=÷64)
    signal scale_shift : unsigned(1 downto 0) := "00";

begin

    -- Format mapping: 
    -- Hardware expects Q3.15. We pass the chosen bits directly from the FSM to preserve precision.
    invsqrt_out   <= to_sfixed(std_logic_vector(invsqrt_hw_out(3 downto -9)) & "00000", inv_t'left, inv_t'right);

    INVSQRT_UNIT : invsqrt
        port map (clk => clk, start => invsqrt_start,
                  x => invsqrt_hw_in, ans => invsqrt_hw_out, done => invsqrt_done);

    -- ─────────────────────────────────────────────────────────
    -- MAIN PROCESS
    -- ─────────────────────────────────────────────────────────
    process(clk)
        variable v_sq  : sos_t;
        variable v_inv : inv_t;
        variable v_d   : pos_t;
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
                    -- Initialize sphere iteration
                    sphere_idx    <= 0;
                    best_sphere_d <= FAR_SPHERE;
                    best_sphere_id <= 0;
                    -- Compute ground plane distance (constant across spheres)
                    -- Will be latched in first COMPUTE_SOS

                -- ── COMPUTE_SOS ──────────────────────────────
                -- Compute sum-of-squares for current sphere_idx
                when COMPUTE_SOS =>
                    v_sq    := sum_of_sq(curr_x, curr_y, curr_z, sphere_idx);
                    sum_sq  <= v_sq;

                    -- Compute plane distance on first sphere iteration
                    if sphere_idx = 0 then
                        d_plane <= sdf_plane(curr_y);
                        -- Reset best sphere tracking
                        best_sphere_d <= FAR_SPHERE;
                    end if;

                    if v_sq > SOS_HI then
                        -- Very far from this sphere: skip invsqrt entirely
                        d_sphere      <= FAR_SPHERE;
                        invsqrt_start <= '0';
                        scale_shift   <= "00";
                        state         <= STORE_SPHERE;
                    elsif v_sq > SOS_MED then
                        -- Far: divide by 64, recover by shift_right(3)
                        invsqrt_hw_in <= std_logic_vector(v_sq(8 downto -6)) & "000";
                        invsqrt_start <= '1';
                        scale_shift   <= "11";
                        state         <= WAIT_INVSQRT;
                    elsif v_sq > SOS_LO then
                        -- Medium: divide by 4, recover by shift_right(1)
                        invsqrt_hw_in <= std_logic_vector(v_sq(4 downto -6)) & "0000000";
                        invsqrt_start <= '1';
                        scale_shift   <= "01";
                        state         <= WAIT_INVSQRT;
                    else
                        -- Close: unscaled, no recovery shift needed
                        invsqrt_hw_in <= std_logic_vector(v_sq(2 downto -6)) & "000000000";
                        invsqrt_start <= '1';
                        scale_shift   <= "00";
                        state         <= WAIT_INVSQRT;
                    end if;

                -- ── WAIT_INVSQRT ─────────────────────────────
                when WAIT_INVSQRT =>
                    invsqrt_start <= '0';
                    if invsqrt_done = '1' then
                        case scale_shift is
                            when "11"   => v_inv := shift_right(invsqrt_out, 3);  -- ÷64 recovery
                            when "01"   => v_inv := shift_right(invsqrt_out, 1);  -- ÷4 recovery
                            when others => v_inv := invsqrt_out;                  -- unscaled
                        end case;

                        d_sphere <= resize(fp_mul_sos(sum_sq, v_inv) - SPHERE_R(sphere_idx), 5, -12);

                        -- Save normal for this sphere (may be overwritten if not closest)
                        norm_sphere_x <= fp_mul_norm(resize(curr_x - SPHERE_CX(sphere_idx), 5, -12), v_inv);
                        norm_sphere_y <= fp_mul_norm(resize(curr_y - SPHERE_CY(sphere_idx), 5, -12), v_inv);
                        norm_sphere_z <= fp_mul_norm(resize(curr_z - SPHERE_CZ(sphere_idx), 5, -12), v_inv);
                        state         <= STORE_SPHERE;
                    end if;

                -- ── STORE_SPHERE ─────────────────────────────
                -- Compare this sphere's distance against best so far
                when STORE_SPHERE =>
                    if d_sphere < best_sphere_d then
                        best_sphere_d  <= d_sphere;
                        best_sphere_id <= sphere_idx;
                        best_norm_x    <= norm_sphere_x;
                        best_norm_y    <= norm_sphere_y;
                        best_norm_z    <= norm_sphere_z;
                    end if;

                    -- Move to next sphere or proceed to EVAL_SDF
                    if sphere_idx = NUM_SPHERES - 1 then
                        state <= EVAL_SDF;
                    else
                        sphere_idx <= sphere_idx + 1;
                        state      <= COMPUTE_SOS;
                    end if;

                -- ── EVAL_SDF ─────────────────────────────────
                -- Compare best sphere distance vs ground plane
                when EVAL_SDF =>
                    if best_sphere_d < d_plane then
                        d_min   <= best_sphere_d;
                        -- mat_id: sphere 0="001", 1="010", 2="011", 3="100"
                        obj_reg <= to_unsigned(best_sphere_id + 1, 3);
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
                    elsif t > MAX_DIST or t < to_sfixed(0.0, 5, -12) then  -- Overflow Wrap Preventer
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
                        -- Reset sphere iteration for next march step
                        sphere_idx    <= 0;
                        best_sphere_d <= FAR_SPHERE;
                        state         <= COMPUTE_SOS;
                    end if;

                -- ── OUTPUT_RESULT ────────────────────────────
                when OUTPUT_RESULT =>
                    hit    <= hit_reg;
                    obj_id <= obj_reg;
                    hit_x  <= curr_x;
                    hit_y  <= curr_y;
                    hit_z  <= curr_z;
                    march_t <= t;
                    if obj_reg /= "000" then
                        -- Sphere hit: use the best sphere's normal
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