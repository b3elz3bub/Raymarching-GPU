-- ============================================================================
-- raygen.vhd — Ray Generator
--
-- Converts pixel coordinates to a normalized ray direction.
-- Worst case: 23 clock cycles (11 for inverse sqrt + 12 here)
--
-- I/O uses sfixed types from params_pkg for clean integration.
-- Internal arithmetic preserved as original signed/std_logic_vector.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.params_pkg.all;

entity raygen is
    generic(
        inlen   : integer := 18;
        infrac  : integer := 0;
        outlen  : integer := 18;
        dirfrac : integer := 16;
        orifrac : integer := 12
    );
    port (
        clk        : in  std_logic;
        start      : in  std_logic;
        -- Pixel coordinates (integer, 10-bit each in std_logic_vector)
        pixx       : in  std_logic_vector(inlen-1 downto 0);
        pixy       : in  std_logic_vector(inlen-1 downto 0);
        -- Camera origin (passed through to outputs)
        cam_x      : in  pos_t;
        cam_y      : in  pos_t;
        cam_z      : in  pos_t;
        -- Outputs: ray origin (passed through)
        ray_orig_x : out pos_t;
        ray_orig_y : out pos_t;
        ray_orig_z : out pos_t;
        -- Outputs: ray direction  [Q2.16 — dir_t]
        ray_dir_x  : out dir_t;
        ray_dir_y  : out dir_t;
        ray_dir_z  : out dir_t;
        -- Control
        done       : out std_logic
    );
end raygen;

architecture Behavioral of raygen is

    -- Internal signals (original arithmetic, preserved as-is)
    signal x, y             : signed(inlen-1 downto 0);
    signal h                : signed(inlen-1 downto 0);
    signal w                : signed(inlen-1 downto 0);
    signal invh             : signed(inlen-1 downto 0);
    signal uvx, uvy         : signed(inlen-1 downto 0);
    signal dotx, doty, dotz : signed(inlen-1 downto 0);
    signal dot, invmag      : std_logic_vector(inlen-1 downto 0);
    signal mag              : sfixed(8 downto -9);   -- Q9.9 from invsqrt
    signal run              : std_logic := '0';
    signal magstart         : std_logic := '0';
    signal magdone          : std_logic := '1';
    signal count            : signed(3 downto 0);

    -- Internal direction results (std_logic_vector, converted to sfixed at output)
    signal dir_x_slv, dir_y_slv, dir_z_slv : std_logic_vector(outlen-1 downto 0);

    component invsqrt is
        Port (
            x     : in  std_logic_vector((inlen-1) downto 0);
            clk   : in  std_logic;
            start : in  std_logic;
            ans   : out sfixed(8 downto -9);
            done  : out std_logic
        );
    end component;

begin

    invh <= "00" & x"0089";                              -- 1/480 in Q2.16 (137/65536 ≈ 0.00209)
    h    <= TO_SIGNED(SCREEN_HEIGHT, inlen);               -- Q18.0
    w    <= TO_SIGNED(SCREEN_WIDTH,  inlen);               -- Q18.0
    dotz <= "00" & x"8000";                              -- (1.0) in Q3.15

    u1: invsqrt
        port map(
            x     => dot,
            clk   => clk,
            start => magstart,
            ans   => mag,
            done  => magdone
        );

    -- Pass camera origin straight through (latched on done)
    process(clk)
        variable x2, y2, xshift, yshift : signed(inlen-1 downto 0);
        variable dotxy                  : signed(inlen downto 0);
        variable dottemp                : signed(inlen-1 downto 0);
        variable dotxfull, dotyfull, uvxfull, uvyfull : signed(inlen*2-1 downto 0);
        variable dirxfull, diryfull     : signed(inlen*2-1 downto 0);
    begin
        if rising_edge(clk) then
            if run = '0' then
                if start = '1' then
                    x        <= signed(pixx);
                    y        <= signed(pixy);
                    done     <= '0';
                    run      <= '1';
                    magstart <= '0';
                    count    <= x"0";
                    dot      <= "00" & x"0000";
                end if;

            elsif run = '1' then
                if count = x"0" then
                    x2       := x(inlen-2 downto 0) & '0';
                    xshift   := x2 - w;
                    uvxfull  := xshift * invh;          -- Q20.16
                    uvx      <= uvxfull(17 downto 0);   -- Q2.16
                    count    <= count + 1;

                elsif count = x"1" then
                    y2       := y(inlen-2 downto 0) & '0';
                    yshift   := h - y2;
                    uvyfull  := yshift * invh;          -- Q20.16
                    uvy      <= uvyfull(17 downto 0);   -- Q2.16
                    count    <= count + 1;

                elsif count = x"2" then
                    dotxfull := uvx * uvx;              -- Q4.32
                    dotx     <= dotxfull(34 downto 17); -- Q3.15
                    count    <= count + 1;

                elsif count = x"3" then
                    dotyfull := uvy * uvy;              -- Q4.32
                    doty     <= dotyfull(34 downto 17); -- Q3.15
                    count    <= count + 1;

                elsif count = x"4" then
                    dotxy := resize(dotx, 19) + resize(doty, 19) + resize(dotz, 19);
                    dotxy := shift_right(dotxy, 2);     -- divide by 4
                    dot   <= std_logic_vector(dotxy(17 downto 0));
                    count <= count + 1;

                elsif count = x"5" then
                    magstart <= '1';
                    count    <= count + 1;

                elsif count = x"6" then
                    count <= count + 1;

                elsif count = x"7" then
                    if magdone = '1' then
                        invmag <= std_logic_vector(mag);
                        count  <= count + 1;
                    else
                        magstart <= '0';
                    end if;

                elsif count = x"8" then
                    dirxfull   := uvx * signed(invmag);         -- Q11.25
                    dir_x_slv  <= std_logic_vector(dirxfull(27 downto 10)); -- Q2.16
                    count      <= count + 1;

                elsif count = x"9" then
                    diryfull   := uvy * signed(invmag);         -- Q11.25
                    dir_y_slv  <= std_logic_vector(diryfull(27 downto 10)); -- Q2.16
                    count      <= count + 1;

                elsif count = x"a" then
                    dir_z_slv <= invmag(11 downto 0) & "000000"; -- Q2.16
                    -- Latch camera origin on completion
                    ray_orig_x <= cam_x;
                    ray_orig_y <= cam_y;
                    ray_orig_z <= cam_z;
                    done       <= '1';
                    run        <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Convert internal std_logic_vector directions → sfixed dir_t outputs
    ray_dir_x <= to_sfixed(dir_x_slv, dir_t'left, dir_t'right);
    ray_dir_y <= to_sfixed(dir_y_slv, dir_t'left, dir_t'right);
    ray_dir_z <= to_sfixed(dir_z_slv, dir_t'left, dir_t'right);

end Behavioral;
