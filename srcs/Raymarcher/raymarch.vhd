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
        -- inputs from Person 2 (ray direction)   [Q2.16 — sfixed(1 downto -16) — 18-bit, locked]
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
        march_t      : out sfixed(5 downto -12)     -- total march distance along ray
    );
end raymarch;

architecture Behavioral of raymarch is

    -- ─────────────────────────────────────────────────────────
    -- TYPES
    --   pos_t  Q6.12   sfixed(5  downto -12)  18-bit  positions, distances, d values, t
    --   dir_t  Q2.16   sfixed(1  downto -16)  18-bit  ray directions  (locked by Person 2)
    --   sos_t  Q12.6   sfixed(11 downto  -6)  18-bit  sum-of-squares  (range up to ~1200)
    --   inv_t  Q4.14   sfixed(3  downto -14)  18-bit  invsqrt output  (range 0..8, floor 1/64)
    -- ─────────────────────────────────────────────────────────
    subtype pos_t is sfixed(5  downto -12);
    subtype dir_t is sfixed(1  downto -16);
    subtype sos_t is sfixed(11 downto  -6);
    subtype inv_t is sfixed(3  downto -14);

    -- ─────────────────────────────────────────────────────────
    -- CONSTANTS                              (all in pos_t / Q6.12)
    -- ─────────────────────────────────────────────────────────
    constant ONE      : pos_t := to_sfixed( 1.0,    5, -12);
    constant RADIUS   : pos_t := to_sfixed( 1.0,    5, -12);
    constant HIT_DIST : pos_t := to_sfixed( 0.005,  5, -12);  -- ~4.88e-3 (nearest Q6.12)
    constant MAX_DIST : pos_t := to_sfixed(20.0,    5, -12);

    -- sphere center at (0, 0, 0)
    -- sits on plane y = -1  because center_y(0) - radius(1) = -1
    constant SP_X : pos_t := to_sfixed(0.0, 5, -12);
    constant SP_Y : pos_t := to_sfixed(0.0, 5, -12);
    constant SP_Z : pos_t := to_sfixed(0.0, 5, -12);

    -- ─────────────────────────────────────────────────────────
    -- COMPONENT — invsqrt block
    --   Input  x   : sos_t  sfixed(11 downto -6)   Q12.6   18-bit
    --   Output ans : inv_t  sfixed(3  downto -14)  Q4.14   18-bit
    -- !! adjust port names to match the actual entity !!
    -- ─────────────────────────────────────────────────────────
    component invsqrt
        Port (
            clk   : in  std_logic;
            start : in  std_logic;
            x     : in  sfixed(11 downto -6);    -- sum-of-squares in Q12.6
            ans   : out sfixed(3  downto -14);   -- 1/sqrt(x) in Q4.14
            done  : out std_logic
        );
    end component;

    -- ─────────────────────────────────────────────────────────
    -- FUNCTIONS
    --   Every multiply is exactly 18 × 18 bits → single DSP block
    -- ─────────────────────────────────────────────────────────

    -- pos × pos → pos   used in sum_of_sq for dx*dx, dy*dy, dz*dz
    function fp_mul_pos(a : pos_t; b : pos_t) return pos_t is
    begin
        return resize(a * b, 5, -12);
    end function;

    -- dir × pos → pos   used in CHECK_HIT to advance: ray_dir * d_min
    function fp_mul_dir(a : dir_t; b : pos_t) return pos_t is
    begin
        return resize(a * b, 5, -12);
    end function;

    -- sos × inv → pos   used in WAIT_INVSQRT: sum_sq * invsqrt_out = sqrt(sum_sq)
    function fp_mul_sos(a : sos_t; b : inv_t) return pos_t is
    begin
        return resize(a * b, 5, -12);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- SCENE FUNCTIONS
    -- ─────────────────────────────────────────────────────────

    -- sdf_plane — combinational; distance = py - (-1) = py + 1
    function sdf_plane(py : pos_t) return pos_t is
    begin
        return resize(py + ONE, 5, -12);
    end function;

    -- sum_of_sq — combinational; returns dx²+dy²+dz² in sos_t (Q12.6)
    -- output is sos_t (not pos_t) because squaring inflates the integer range
    function sum_of_sq(px, py, pz : pos_t) return sos_t is
        variable dx, dy, dz : pos_t;
    begin
        dx := resize(px - SP_X, 5, -12);
        dy := resize(py - SP_Y, 5, -12);
        dz := resize(pz - SP_Z, 5, -12);
        -- each fp_mul_pos returns pos_t; VHDL fixed_pkg widens sum naturally
        -- final resize to sos_t (11 downto -6) keeps the enlarged integer range
        return resize(fp_mul_pos(dx,dx) + fp_mul_pos(dy,dy) + fp_mul_pos(dz,dz), 11, -6);
    end function;

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE STATES
    -- ─────────────────────────────────────────────────────────
    type state_t is (
        IDLE,           -- waiting for start
        INIT,           -- load ray into registers
        COMPUTE_SOS,    -- compute sum of squares + plane SDF, fire invsqrt
        WAIT_INVSQRT,   -- wait for invsqrt block to finish
        EVAL_SDF,       -- pick minimum of d_sphere and d_plane
        CHECK_HIT,      -- hit / miss / continue decision
        OUTPUT_RESULT   -- drive output ports, assert done
    );
    signal state : state_t := IDLE;

    -- ─────────────────────────────────────────────────────────
    -- SIGNALS
    -- ─────────────────────────────────────────────────────────

    -- current march point
    signal curr_x : pos_t := (others => '0');
    signal curr_y : pos_t := (others => '0');
    signal curr_z : pos_t := (others => '0');

    -- total distance marched along the ray
    signal t      : pos_t := (others => '0');

    -- step counter (0–63)
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- invsqrt interface
    signal invsqrt_start : std_logic := '0';
    signal invsqrt_in    : sos_t     := (others => '0');  -- Q12.6
    signal invsqrt_out   : inv_t     := (others => '0');  -- Q4.14
    signal invsqrt_done  : std_logic;

    -- intermediate SDF results
    signal d_plane  : pos_t := (others => '0');
    signal d_sphere : pos_t := (others => '0');
    signal d_min    : pos_t := (others => '0');
    signal sum_sq   : sos_t := (others => '0');  -- Q12.6, stored for the multiply-back

    -- internal result registers
    signal hit_reg : std_logic         := '0';
    signal obj_reg : unsigned(2 downto 0) := (others => '0');

begin

    -- ─────────────────────────────────────────────────────────
    -- INVSQRT INSTANTIATION
    -- ─────────────────────────────────────────────────────────
    INVSQRT_UNIT : invsqrt
        port map (
            clk   => clk,
            start => invsqrt_start,
            x     => invsqrt_in,    -- sos_t  sfixed(11 downto -6)
            ans   => invsqrt_out,   -- inv_t  sfixed(3  downto -14)
            done  => invsqrt_done
        );

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                done          <= '0';
                hit           <= '0';
                invsqrt_start <= '0';

            else
                case state is

                    -- ── IDLE ─────────────────────────────────
                    when IDLE =>
                        done          <= '0';
                        invsqrt_start <= '0';
                        if start = '1' then
                            state <= INIT;
                        end if;

                    -- ── INIT ─────────────────────────────────
                    when INIT =>
                        curr_x     <= ray_orig_x;
                        curr_y     <= ray_orig_y;
                        curr_z     <= ray_orig_z;
                        t          <= to_sfixed(0.0, 5, -12);
                        step_count <= (others => '0');
                        hit_reg    <= '0';
                        state      <= COMPUTE_SOS;

                    -- ── COMPUTE_SOS ───────────────────────────
                    -- plane SDF is free (addition only)
                    -- sum_of_sq feeds both the stored register and the invsqrt block
                    when COMPUTE_SOS =>
                        d_plane       <= sdf_plane(curr_y);
                        sum_sq        <= sum_of_sq(curr_x, curr_y, curr_z);
                        invsqrt_in    <= sum_of_sq(curr_x, curr_y, curr_z);
                        invsqrt_start <= '1';
                        state         <= WAIT_INVSQRT;

                    -- ── WAIT_INVSQRT ─────────────────────────
                    -- sqrt(sum_sq) = sum_sq * (1/sqrt(sum_sq))
                    -- fp_mul_sos: sos_t(18) × inv_t(18) → pos_t(18)  — single DSP
                    when WAIT_INVSQRT =>
                        invsqrt_start <= '0';
                        if invsqrt_done = '1' then
                            d_sphere <= resize(fp_mul_sos(sum_sq, invsqrt_out) - RADIUS, 5, -12);
                            state    <= EVAL_SDF;
                        end if;

                    -- ── EVAL_SDF ──────────────────────────────
                    when EVAL_SDF =>
                        if d_sphere < d_plane then
                            d_min   <= d_sphere;
                            obj_reg <= "001";   -- sphere = obj 1
                        else
                            d_min   <= d_plane;
                            obj_reg <= "000";   -- plane  = obj 0
                        end if;
                        state <= CHECK_HIT;

                    -- ── CHECK_HIT ─────────────────────────────
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
                            -- advance: p = p + dir * d_min
                            -- fp_mul_dir: dir_t(18) × pos_t(18) → pos_t(18) — single DSP each
                            curr_x     <= resize(curr_x + fp_mul_dir(ray_dir_x, d_min), 5, -12);
                            curr_y     <= resize(curr_y + fp_mul_dir(ray_dir_y, d_min), 5, -12);
                            curr_z     <= resize(curr_z + fp_mul_dir(ray_dir_z, d_min), 5, -12);
                            t          <= resize(t + d_min, 5, -12);
                            step_count <= step_count + 1;
                            state      <= COMPUTE_SOS;
                        end if;

                    -- ── OUTPUT_RESULT ─────────────────────────
                    when OUTPUT_RESULT =>
                        hit    <= hit_reg;
                        obj_id <= obj_reg;
                        hit_x  <= curr_x;
                        hit_y  <= curr_y;
                        hit_z  <= curr_z;
                        march_t  <= t;
                        done   <= '1';
                        state  <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
