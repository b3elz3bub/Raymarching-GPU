library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.FIXED_PKG.ALL;

entity raymarch is
    Port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        -- inputs from Person 2 (ray generator)
        ray_orig_x : in  sfixed(15 downto -16);
        ray_orig_y : in  sfixed(15 downto -16);
        ray_orig_z : in  sfixed(15 downto -16);
        ray_dir_x  : in  sfixed(15 downto -16);
        ray_dir_y  : in  sfixed(15 downto -16);
        ray_dir_z  : in  sfixed(15 downto -16);
        -- outputs to Person 4 (shading)
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
    -- TYPE
    -- ─────────────────────────────────────────────────────────
    subtype fixed32 is sfixed(15 downto -16);

    -- ─────────────────────────────────────────────────────────
    -- CONSTANTS
    -- ─────────────────────────────────────────────────────────
    constant ONE      : fixed32 := to_sfixed( 1.0,   15, -16);
    constant HALF     : fixed32 := to_sfixed( 0.5,   15, -16);
    constant RADIUS   : fixed32 := to_sfixed( 1.0,   15, -16); -- bigger sphere
    constant HIT_DIST : fixed32 := to_sfixed( 0.005, 15, -16);
    constant MAX_DIST : fixed32 := to_sfixed(20.0,   15, -16);

    -- single sphere center at (0, 0, 0)
    -- sits on plane at y=-1.0 because center_y(0) - radius(1.0) = -1.0
    constant SP_X : fixed32 := to_sfixed(0.0, 15, -16);
    constant SP_Y : fixed32 := to_sfixed(0.0, 15, -16);
    constant SP_Z : fixed32 := to_sfixed(0.0, 15, -16);

    -- ─────────────────────────────────────────────────────────
    -- COMPONENT — Person 2's invsqrt block
    -- !! adjust port names to match Person 2's actual entity !!
    -- ─────────────────────────────────────────────────────────
    component invsqrt
        Port (
            clk   : in  std_logic;
            start : in  std_logic;
            x     : in  sfixed(15 downto -16);   -- input: value to invsqrt
            ans   : out sfixed(15 downto -16);    -- output: 1/sqrt(x)
            done  : out std_logic
        );
    end component;

    -- ─────────────────────────────────────────────────────────
    -- FUNCTIONS
    -- ─────────────────────────────────────────────────────────

    -- fixed point multiply — resize back to fixed32
    function fp_mul(a : fixed32;
                    b : fixed32) return fixed32 is
    begin
        return resize(a * b, 15, -16);
    end function;

    -- sdf_plane — pure combinational, just addition
    function sdf_plane(py : fixed32) return fixed32 is
    begin
        return resize(py + ONE, 15, -16);
    end function;

    -- sum of squares — combinational part of sdf_sphere
    -- computes dx²+dy²+dz² relative to sphere center
    -- this is the value fed into invsqrt
    function sum_of_sq(px, py, pz : fixed32) return fixed32 is
        variable dx, dy, dz : fixed32;
        variable s          : fixed32;
    begin
        dx := resize(px - SP_X, 15, -16);
        dy := resize(py - SP_Y, 15, -16);
        dz := resize(pz - SP_Z, 15, -16);
        s  := resize(fp_mul(dx, dx) + fp_mul(dy, dy) + fp_mul(dz, dz), 15, -16);
        return s;
    end function;

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE STATES
    -- ─────────────────────────────────────────────────────────
    type state_t is (
        IDLE,           -- waiting for start
        INIT,           -- load ray into registers
        COMPUTE_SOS,    -- compute sum of squares for current point
        WAIT_INVSQRT,   -- wait for Person 2's block to finish
        EVAL_SDF,       -- compute final sdf values, pick minimum
        CHECK_HIT,      -- hit or miss decision
        OUTPUT_RESULT   -- assert done, put outputs on ports
    );
    signal state : state_t := IDLE;

    -- ─────────────────────────────────────────────────────────
    -- SIGNALS
    -- ─────────────────────────────────────────────────────────

    -- current march point (updated each step)
    signal curr_x : fixed32 := (others => '0');
    signal curr_y : fixed32 := (others => '0');
    signal curr_z : fixed32 := (others => '0');

    -- current t (distance travelled along ray)
    signal t      : fixed32 := (others => '0');

    -- step counter (0 to 63)
    signal step_count : unsigned(5 downto 0) := (others => '0');

    -- invsqrt interface signals
    signal invsqrt_start : std_logic := '0';
    signal invsqrt_in    : fixed32   := (others => '0');
    signal invsqrt_out   : fixed32   := (others => '0');
    signal invsqrt_done  : std_logic;

    -- intermediate sdf results
    signal d_plane  : fixed32 := (others => '0');  -- plane distance
    signal d_sphere : fixed32 := (others => '0');  -- sphere distance
    signal d_min    : fixed32 := (others => '0');  -- minimum distance
    signal sum_sq   : fixed32 := (others => '0');  -- stored for multiply back

    -- internal hit registers
    signal hit_reg    : std_logic := '0';
    signal obj_reg    : unsigned(2 downto 0) := (others => '0');

begin

    -- ─────────────────────────────────────────────────────────
    -- INVSQRT INSTANTIATION
    -- ─────────────────────────────────────────────────────────
    INVSQRT_UNIT : invsqrt
        port map (
            clk   => clk,
            start => invsqrt_start,
            x     => invsqrt_in,
            ans   => invsqrt_out,
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
                    -- load ray into internal registers
                    -- starting point = ray origin
                    when INIT =>
                        curr_x    <= ray_orig_x;
                        curr_y    <= ray_orig_y;
                        curr_z    <= ray_orig_z;
                        t         <= to_sfixed(0.0, 15, -16);
                        step_count <= (others => '0');
                        hit_reg   <= '0';
                        state     <= COMPUTE_SOS;

                    -- ── COMPUTE_SOS ───────────────────────────
                    -- compute sum of squares and plane SDF
                    -- feed sum_sq to invsqrt
                    when COMPUTE_SOS =>
                        -- plane SDF is free — just addition
                        d_plane <= sdf_plane(curr_y);

                        -- sphere: compute sum of squares
                        sum_sq        <= sum_of_sq(curr_x, curr_y, curr_z);
                        invsqrt_in    <= sum_of_sq(curr_x, curr_y, curr_z);
                        invsqrt_start <= '1';
                        state         <= WAIT_INVSQRT;

                    -- ── WAIT_INVSQRT ─────────────────────────
                    -- wait for Person 2's block to produce result
                    when WAIT_INVSQRT =>
                        invsqrt_start <= '0';   -- de-assert after one cycle
                        if invsqrt_done = '1' then
                            -- length = sum_sq * (1/sqrt(sum_sq)) = sqrt(sum_sq)
                            d_sphere <= resize(fp_mul(sum_sq, invsqrt_out) - RADIUS, 15, -16);
                            state    <= EVAL_SDF;
                        end if;

                    -- ── EVAL_SDF ──────────────────────────────
                    -- pick minimum of plane and sphere
                    -- decide which object is closer
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

                        -- hit condition: very close to a surface
                        if d_min < HIT_DIST then
                            hit_reg <= '1';
                            state   <= OUTPUT_RESULT;

                        -- miss condition: travelled too far
                        elsif t > MAX_DIST then
                            hit_reg <= '0';
                            state   <= OUTPUT_RESULT;

                        -- miss condition: out of steps
                        elsif step_count = 63 then
                            hit_reg <= '0';
                            state   <= OUTPUT_RESULT;

                        -- continue marching
                        else
                            -- advance point: p = p + dir * d_min
                            curr_x     <= resize(curr_x + fp_mul(ray_dir_x, d_min), 15, -16);
                            curr_y     <= resize(curr_y + fp_mul(ray_dir_y, d_min), 15, -16);
                            curr_z     <= resize(curr_z + fp_mul(ray_dir_z, d_min), 15, -16);
                            t          <= resize(t + d_min, 15, -16);
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
                        done   <= '1';
                        state  <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
