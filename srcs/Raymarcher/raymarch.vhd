library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.FIXED_PKG.ALL;

entity raymarch is
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        -- inputs from Person 2 (ray generator)   [Q6.12 — sfixed(5 downto -12) — 18-bit]
        ray_orig_x : in  sfixed(5 downto -12);
        ray_orig_y : in  sfixed(5 downto -12);
        ray_orig_z : in  sfixed(5 downto -12);
        -- inputs from Person 2 (ray direction)   [Q2.16 — sfixed(1 downto -16) — 18-bit]
        ray_dir_x  : in  sfixed(1 downto -16);
        ray_dir_y  : in  sfixed(1 downto -16);
        ray_dir_z  : in  sfixed(1 downto -16);
        -- outputs to Person 4 (shading)          [Q6.12 — sfixed(5 downto -12) — 18-bit]
        done       : out std_logic;
        hit        : out std_logic;
        obj_id     : out unsigned(2 downto 0);
        hit_x      : out sfixed(5 downto -12);
        hit_y      : out sfixed(5 downto -12);
        hit_z      : out sfixed(5 downto -12);
        hit_t      : out sfixed(5 downto -12);
        -- surface normal at hit point             [Q2.16 — sfixed(1 downto -16) — 18-bit]
        norm_x     : out sfixed(1 downto -16);
        norm_y     : out sfixed(1 downto -16);
        norm_z     : out sfixed(1 downto -16)
    );
end raymarch;

architecture Behavioral of raymarch is

    -- ─────────────────────────────────────────────────────────
    -- TYPES
    --   pos_t  Q6.12   sfixed(5  downto -12)  18-bit  positions, distances
    --   dir_t  Q2.16   sfixed(1  downto -16)  18-bit  ray directions, normals
    --   sos_t  Q12.6   sfixed(11 downto  -6)  18-bit  sum-of-squares
    --   inv_t  Q4.14   sfixed(3  downto -14)  18-bit  invsqrt output
    -- ─────────────────────────────────────────────────────────
    subtype pos_t is sfixed(5  downto -12);
    subtype dir_t is sfixed(1  downto -16);
    subtype sos_t is sfixed(11 downto  -6);
    subtype inv_t is sfixed(3  downto -14);

    -- ─────────────────────────────────────────────────────────
    -- CONSTANTS
    -- ─────────────────────────────────────────────────────────
    constant ONE      : pos_t := to_sfixed( 1.0,    5, -12);
    constant RADIUS   : pos_t := to_sfixed( 1.0,    5, -12);
    constant HIT_DIST : pos_t := to_sfixed( 0.005,  5, -12);
    constant MAX_DIST : pos_t := to_sfixed(20.0,    5, -12);

    -- sphere center
    constant SP_X : pos_t := to_sfixed(0.0, 5, -12);
    constant SP_Y : pos_t := to_sfixed(0.0, 5, -12);
    constant SP_Z : pos_t := to_sfixed(0.0, 5, -12);

    -- plane normal (constant, always up)
    constant PLANE_NX : dir_t := to_sfixed(0.0, 1, -16);
    constant PLANE_NY : dir_t := to_sfixed(1.0, 1, -16);
    constant PLANE_NZ : dir_t := to_sfixed(0.0, 1, -16);

    -- Range-reduction thresholds for invsqrt (max input = 7)
    --   SOS_LO  = 7       : invsqrt works directly for sum_sq ≤ 7
    --   SOS_HI  = 7 × 64  = 448 : after ÷64 (shift-right 6), input ≤ 7
    --   > 448 means sphere > √448 − 1 ≈ 20.2 units away → safe fallback
    constant SOS_LO : sos_t := to_sfixed(  7.0, 11, -6);
    constant SOS_HI : sos_t := to_sfixed(448.0, 11, -6);

    -- Fallback d_sphere when sum_sq > 448 (true d_sphere > 20.2)
    constant FAR_SPHERE : pos_t := to_sfixed(20.0, 5, -12);

    -- ─────────────────────────────────────────────────────────
    -- COMPONENT — invsqrt block (Person 2, accurate for input ≤ 7)
    -- ─────────────────────────────────────────────────────────
    component invsqrt
        Port (
            clk   : in  std_logic;
            start : in  std_logic;
            x     : in  sfixed(11 downto -6);
            ans   : out sfixed(3  downto -14);
            done  : out std_logic
        );
    end component;

    -- ─────────────────────────────────────────────────────────
    -- MULTIPLY FUNCTIONS  (each 18 × 18 → single DSP block)
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
    begin return resize(py + ONE, 5, -12); end function;

    function sum_of_sq(px, py, pz : pos_t) return sos_t is
        variable dx, dy, dz : pos_t;
    begin
        dx := resize(px - SP_X, 5, -12);
        dy := resize(py - SP_Y, 5, -12);
        dz := resize(pz - SP_Z, 5, -12);
        return resize(fp_mul_pos(dx,dx) + fp_mul_pos(dy,dy) + fp_mul_pos(dz,dz), 11, -6);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    type state_t is (IDLE, INIT, COMPUTE_SOS, WAIT_INVSQRT,
                     EVAL_SDF, CHECK_HIT, OUTPUT_RESULT);
    signal state : state_t := IDLE;

    -- current march point & total distance
    signal curr_x, curr_y, curr_z : pos_t := (others => '0');
    signal t          : pos_t := (others => '0');
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- invsqrt interface
    signal invsqrt_start : std_logic := '0';
    signal invsqrt_in    : sos_t     := (others => '0');
    signal invsqrt_out   : inv_t     := (others => '0');
    signal invsqrt_done  : std_logic;

    -- SDF intermediates
    signal d_plane, d_sphere, d_min : pos_t := (others => '0');
    signal sum_sq : sos_t := (others => '0');

    -- result registers
    signal hit_reg : std_logic            := '0';
    signal obj_reg : unsigned(2 downto 0) := (others => '0');

    -- sphere normal (computed in WAIT_INVSQRT, valid at hit)
    signal norm_sphere_x, norm_sphere_y, norm_sphere_z : dir_t := (others => '0');

    -- Range-reduction flag: '1' when sum_sq was divided by 64 before invsqrt.
    -- In WAIT_INVSQRT, if scaled='1', we shift_right the output by 3 to compensate.
    signal scaled : std_logic := '0';

begin

    INVSQRT_UNIT : invsqrt
        port map (clk => clk, start => invsqrt_start,
                  x => invsqrt_in, ans => invsqrt_out, done => invsqrt_done);

    -- ─────────────────────────────────────────────────────────
    -- MAIN PROCESS
    -- ─────────────────────────────────────────────────────────
    process(clk)
        variable v_sq  : sos_t;   -- single compute of sum_of_sq
        variable v_inv : inv_t;   -- corrected 1/sqrt(sum_sq)
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
                -- Three cases based on sum_sq:
                --   ≤ 7   : feed directly to invsqrt (near sphere)
                --   7–448 : divide by 64 (shift right 6), then invsqrt
                --   > 448 : sphere > 20 units away, skip invsqrt
                when COMPUTE_SOS =>
                    v_sq    := sum_of_sq(curr_x, curr_y, curr_z);
                    d_plane <= sdf_plane(curr_y);
                    sum_sq  <= v_sq;

                    if v_sq > SOS_HI then
                        -- Far: sphere > ~21 units away, skip invsqrt
                        d_sphere      <= FAR_SPHERE;
                        invsqrt_start <= '0';
                        scaled        <= '0';
                        state         <= EVAL_SDF;

                    elsif v_sq > SOS_LO then
                        -- Mid-range: scale down by 64 so input ∈ [0.11, 7]
                        invsqrt_in    <= shift_right(v_sq, 6);
                        invsqrt_start <= '1';
                        scaled        <= '1';
                        state         <= WAIT_INVSQRT;

                    else
                        -- Near sphere: input already ≤ 7, use directly
                        invsqrt_in    <= v_sq;
                        invsqrt_start <= '1';
                        scaled        <= '0';
                        state         <= WAIT_INVSQRT;
                    end if;

                -- ── WAIT_INVSQRT ─────────────────────────────
                -- If scaled='1', invsqrt returned 1/√(sum_sq/64) = 8/√(sum_sq).
                -- Shift right by 3 to recover the true 1/√(sum_sq).
                -- If scaled='0', output is already 1/√(sum_sq).
                when WAIT_INVSQRT =>
                    invsqrt_start <= '0';
                    if invsqrt_done = '1' then
                        -- Compensate for range reduction
                        if scaled = '1' then
                            v_inv := shift_right(invsqrt_out, 3);
                        else
                            v_inv := invsqrt_out;
                        end if;

                        -- d_sphere = √(sum_sq) − R = sum_sq × (1/√sum_sq) − R
                        d_sphere <= resize(fp_mul_sos(sum_sq, v_inv) - RADIUS, 5, -12);

                        -- sphere normal = (p − center) / |p − center|
                        norm_sphere_x <= fp_mul_norm(resize(curr_x - SP_X, 5, -12), v_inv);
                        norm_sphere_y <= fp_mul_norm(resize(curr_y - SP_Y, 5, -12), v_inv);
                        norm_sphere_z <= fp_mul_norm(resize(curr_z - SP_Z, 5, -12), v_inv);
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
                    elsif step_count = 63 then
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
                    hit_t  <= t;
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
