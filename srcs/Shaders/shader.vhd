-- ============================================================================
-- shader.vhd — Shading unit for raymarching GPU
--
-- Faithful translation of software/scene.py shade() function.
-- Uses a state machine to sequence operations and reuse DSP multipliers.
--
-- Pipeline overview (state machine, ~20-25 clock cycles per pixel):
--   IDLE        → wait for start pulse
--   LATCH       → register all inputs
--   MISS_SKY    → if miss: output sky color, done in 1 cycle
--   DIFFUSE     → dot(N, sun) = Nx*Sx + Ny*Sy + Nz*Sz  (3 cycles)
--   CHECKER     → ground checkerboard: XOR of integer bits of hit_x, hit_z
--   MATERIAL    → select base color from mat_id
--   LIGHT       → base * (sun_light + ambient)  (3 cycles for R,G,B)
--   FRESNEL     → NoV = -dot(rd, N), fres = (1-NoV)^4  (4 muls)
--   REFLECT     → sky_col(reflect(rd, N)) — simplified to gradient
--   MIX_REFL    → mix(col, sky_refl, fres)
--   FOG         → fog_amt from LUT, mix(col, fog_color, fog_amt)
--   GAMMA       → sqrt via LUT per channel
--   PACK        → assemble RGB444 output
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.params_pkg.all;

entity shader is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;   -- pulse high for 1 cycle when inputs valid
        -- From raymarcher
        hit_flag   : in  std_logic;
        mat_id     : in  std_logic_vector(2 downto 0);
        hit_pos_x  : in  sfixed(5 downto -12);
        hit_pos_y  : in  sfixed(5 downto -12);
        hit_pos_z  : in  sfixed(5 downto -12);
        normal_x   : in  sfixed(1 downto -16);
        normal_y   : in  sfixed(1 downto -16);
        normal_z   : in  sfixed(1 downto -16);
        march_t    : in  sfixed(5 downto -12);
        -- Ray direction (passed through from raygen)
        ray_dir_x  : in  sfixed(1 downto -16);
        ray_dir_y  : in  sfixed(1 downto -16);
        ray_dir_z  : in  sfixed(1 downto -16);
        -- Output
        rgb444_out : out std_logic_vector(11 downto 0);
        done       : out std_logic
    );
end entity shader;

architecture rtl of shader is

    -- Types pos_t, dir_t, col_t now come from params_pkg

    -- ─────────────────────────────────────────────────────────────
    -- MULTIPLY HELPERS (18x18 → DSP)
    -- ─────────────────────────────────────────────────────────────
    -- dir × dir → col  (normal dot sun, etc.)
    function mul_dd(a : dir_t; b : dir_t) return col_t is
    begin
        return resize(a * b, 1, -10);
    end function;

    -- dir × pos → col  (normal dot sun with pos-format sun constants)
    function mul_dp(a : dir_t; b : pos_t) return col_t is
    begin
        return resize(a * b, 1, -10);
    end function;

    -- col × col → col
    function mul_cc(a : col_t; b : col_t) return col_t is
    begin
        return resize(a * b, 1, -10);
    end function;

    -- Clamp col_t to [0, 1.0)
    function clamp01(x : col_t) return col_t is
        constant ZERO : col_t := to_sfixed(0.0, 1, -10);
        constant ONE  : col_t := to_sfixed(0.999, 1, -10);
    begin
        if x < ZERO then return ZERO;
        elsif x > ONE then return ONE;
        else return x;
        end if;
    end function;

    -- ─────────────────────────────────────────────────────────────
    -- SCENE CONSTANTS (from params_pkg: SUN_DIR_X/Y/Z)
    -- Convert sun direction to dir_t for dot products
    -- ─────────────────────────────────────────────────────────────
    -- SUN_DIR is in pos_t (sfixed 5 downto -12) in params_pkg
    -- We'll use them directly in mul_dp

    -- Fog color and strength (lower weight avoids washed-out image)
    constant FOG_R : col_t := to_sfixed(0.70, 1, -10);
    constant FOG_G : col_t := to_sfixed(0.75, 1, -10);
    constant FOG_B : col_t := to_sfixed(0.84, 1, -10);
    constant FOG_STRENGTH : col_t := to_sfixed(0.62, 1, -10);

    -- Sky horizon color (slightly deeper to increase scene contrast)
    constant SKY_HOR_R : col_t := to_sfixed(0.84, 1, -10);
    constant SKY_HOR_G : col_t := to_sfixed(0.78, 1, -10);
    constant SKY_HOR_B : col_t := to_sfixed(0.70, 1, -10);

    -- Sky zenith color (deep blue: [0.18, 0.38, 0.82])
    constant SKY_ZEN_R : col_t := to_sfixed(0.18, 1, -10);
    constant SKY_ZEN_G : col_t := to_sfixed(0.38, 1, -10);
    constant SKY_ZEN_B : col_t := to_sfixed(0.82, 1, -10);

    -- Sun light tint ([1.0, 0.88, 0.72] * 0.90)
    constant SUN_TINT_R : col_t := to_sfixed(0.90, 1, -10);
    constant SUN_TINT_G : col_t := to_sfixed(0.792, 1, -10);
    constant SUN_TINT_B : col_t := to_sfixed(0.648, 1, -10);

    -- Ground ambient ([0.15, 0.22, 0.42] * 0.30)
    constant GND_AMB_R : col_t := to_sfixed(0.045, 1, -10);
    constant GND_AMB_G : col_t := to_sfixed(0.066, 1, -10);
    constant GND_AMB_B : col_t := to_sfixed(0.126, 1, -10);

    -- Sphere base color (richer blue to avoid flat desaturation)
    constant SPH_BASE_R : col_t := to_sfixed(0.05, 1, -10);
    constant SPH_BASE_G : col_t := to_sfixed(0.14, 1, -10);
    constant SPH_BASE_B : col_t := to_sfixed(0.48, 1, -10);

    -- Sphere ambient ([0.10, 0.16, 0.40] * 0.45)
    constant SPH_AMB_R : col_t := to_sfixed(0.045, 1, -10);
    constant SPH_AMB_G : col_t := to_sfixed(0.072, 1, -10);
    constant SPH_AMB_B : col_t := to_sfixed(0.180, 1, -10);

    -- ─────────────────────────────────────────────────────────────
    -- FOG LUT — fog_amt = 1 - exp(-t * 0.028)
    -- Indexed by march_t integer part (0..31), 5 bits
    -- Returns Q1.10 value [0.0 .. ~1.0]
    -- ─────────────────────────────────────────────────────────────
    type fog_lut_t is array (0 to 31) of unsigned(9 downto 0);  -- 10-bit, maps to 0..1023 = 0.0..~1.0
    constant FOG_LUT : fog_lut_t := (
        --  t=0:  1-exp(0)       = 0.000
        --  t=1:  1-exp(-0.028)  = 0.028
        --  t=2:  1-exp(-0.056)  = 0.054
        --  ...
        --  t=20: 1-exp(-0.56)   = 0.429
        --  t=31: 1-exp(-0.868)  = 0.580
         0 => to_unsigned(  0, 10),  -- t=0
         1 => to_unsigned( 29, 10),  -- t=1   0.028*1024≈29
         2 => to_unsigned( 56, 10),  -- t=2
         3 => to_unsigned( 82, 10),  -- t=3
         4 => to_unsigned(107, 10),  -- t=4
         5 => to_unsigned(131, 10),  -- t=5
         6 => to_unsigned(155, 10),  -- t=6
         7 => to_unsigned(178, 10),  -- t=7
         8 => to_unsigned(200, 10),  -- t=8
         9 => to_unsigned(221, 10),  -- t=9
        10 => to_unsigned(241, 10),  -- t=10
        11 => to_unsigned(261, 10),  -- t=11
        12 => to_unsigned(280, 10),  -- t=12
        13 => to_unsigned(298, 10),  -- t=13
        14 => to_unsigned(315, 10),  -- t=14
        15 => to_unsigned(332, 10),  -- t=15
        16 => to_unsigned(348, 10),  -- t=16
        17 => to_unsigned(363, 10),  -- t=17
        18 => to_unsigned(378, 10),  -- t=18
        19 => to_unsigned(392, 10),  -- t=19
        20 => to_unsigned(406, 10),  -- t=20
        21 => to_unsigned(419, 10),  -- t=21
        22 => to_unsigned(432, 10),  -- t=22
        23 => to_unsigned(444, 10),  -- t=23
        24 => to_unsigned(455, 10),  -- t=24
        25 => to_unsigned(466, 10),  -- t=25
        26 => to_unsigned(477, 10),  -- t=26
        27 => to_unsigned(487, 10),  -- t=27
        28 => to_unsigned(497, 10),  -- t=28
        29 => to_unsigned(506, 10),  -- t=29
        30 => to_unsigned(515, 10),  -- t=30
        31 => to_unsigned(524, 10)   -- t=31
    );

    -- ─────────────────────────────────────────────────────────────
    -- GAMMA LUT — sqrt(x) for gamma correction
    -- Input: 8-bit linear (0..255 representing 0.0..1.0)
    -- Output: 4-bit sRGB (0..15)
    -- gamma_out = round(sqrt(i/255) * 15)
    -- ─────────────────────────────────────────────────────────────
    type gamma_lut_t is array (0 to 255) of unsigned(3 downto 0);
    constant GAMMA_LUT : gamma_lut_t := (
        -- sqrt(0/255)*15=0, sqrt(1/255)*15=0.94≈1, ..., sqrt(255/255)*15=15
          0 => x"0",   1 => x"1",   2 => x"1",   3 => x"2",   4 => x"2",
          5 => x"2",   6 => x"2",   7 => x"2",   8 => x"3",   9 => x"3",
         10 => x"3",  11 => x"3",  12 => x"3",  13 => x"3",  14 => x"4",
         15 => x"4",  16 => x"4",  17 => x"4",  18 => x"4",  19 => x"4",
         20 => x"4",  21 => x"4",  22 => x"5",  23 => x"5",  24 => x"5",
         25 => x"5",  26 => x"5",  27 => x"5",  28 => x"5",  29 => x"5",
         30 => x"5",  31 => x"5",  32 => x"5",  33 => x"5",  34 => x"5",
         35 => x"6",  36 => x"6",  37 => x"6",  38 => x"6",  39 => x"6",
         40 => x"6",  41 => x"6",  42 => x"6",  43 => x"6",  44 => x"6",
         45 => x"6",  46 => x"6",  47 => x"6",  48 => x"7",  49 => x"7",
         50 => x"7",  51 => x"7",  52 => x"7",  53 => x"7",  54 => x"7",
         55 => x"7",  56 => x"7",  57 => x"7",  58 => x"7",  59 => x"7",
         60 => x"7",  61 => x"7",  62 => x"7",  63 => x"7",  64 => x"8",
         65 => x"8",  66 => x"8",  67 => x"8",  68 => x"8",  69 => x"8",
         70 => x"8",  71 => x"8",  72 => x"8",  73 => x"8",  74 => x"8",
         75 => x"8",  76 => x"8",  77 => x"8",  78 => x"8",  79 => x"8",
         80 => x"8",  81 => x"9",  82 => x"9",  83 => x"9",  84 => x"9",
         85 => x"9",  86 => x"9",  87 => x"9",  88 => x"9",  89 => x"9",
         90 => x"9",  91 => x"9",  92 => x"9",  93 => x"9",  94 => x"9",
         95 => x"9",  96 => x"9",  97 => x"9",  98 => x"9",  99 => x"9",
        100 => x"9", 101 => x"A", 102 => x"A", 103 => x"A", 104 => x"A",
        105 => x"A", 106 => x"A", 107 => x"A", 108 => x"A", 109 => x"A",
        110 => x"A", 111 => x"A", 112 => x"A", 113 => x"A", 114 => x"A",
        115 => x"A", 116 => x"A", 117 => x"A", 118 => x"A", 119 => x"A",
        120 => x"A", 121 => x"A", 122 => x"B", 123 => x"B", 124 => x"B",
        125 => x"B", 126 => x"B", 127 => x"B", 128 => x"B", 129 => x"B",
        130 => x"B", 131 => x"B", 132 => x"B", 133 => x"B", 134 => x"B",
        135 => x"B", 136 => x"B", 137 => x"B", 138 => x"B", 139 => x"B",
        140 => x"B", 141 => x"B", 142 => x"B", 143 => x"B", 144 => x"C",
        145 => x"C", 146 => x"C", 147 => x"C", 148 => x"C", 149 => x"C",
        150 => x"C", 151 => x"C", 152 => x"C", 153 => x"C", 154 => x"C",
        155 => x"C", 156 => x"C", 157 => x"C", 158 => x"C", 159 => x"C",
        160 => x"C", 161 => x"C", 162 => x"C", 163 => x"C", 164 => x"C",
        165 => x"C", 166 => x"C", 167 => x"C", 168 => x"C", 169 => x"D",
        170 => x"D", 171 => x"D", 172 => x"D", 173 => x"D", 174 => x"D",
        175 => x"D", 176 => x"D", 177 => x"D", 178 => x"D", 179 => x"D",
        180 => x"D", 181 => x"D", 182 => x"D", 183 => x"D", 184 => x"D",
        185 => x"D", 186 => x"D", 187 => x"D", 188 => x"D", 189 => x"D",
        190 => x"D", 191 => x"D", 192 => x"D", 193 => x"D", 194 => x"D",
        195 => x"D", 196 => x"E", 197 => x"E", 198 => x"E", 199 => x"E",
        200 => x"E", 201 => x"E", 202 => x"E", 203 => x"E", 204 => x"E",
        205 => x"E", 206 => x"E", 207 => x"E", 208 => x"E", 209 => x"E",
        210 => x"E", 211 => x"E", 212 => x"E", 213 => x"E", 214 => x"E",
        215 => x"E", 216 => x"E", 217 => x"E", 218 => x"E", 219 => x"E",
        220 => x"E", 221 => x"E", 222 => x"E", 223 => x"E", 224 => x"E",
        225 => x"E", 226 => x"F", 227 => x"F", 228 => x"F", 229 => x"F",
        230 => x"F", 231 => x"F", 232 => x"F", 233 => x"F", 234 => x"F",
        235 => x"F", 236 => x"F", 237 => x"F", 238 => x"F", 239 => x"F",
        240 => x"F", 241 => x"F", 242 => x"F", 243 => x"F", 244 => x"F",
        245 => x"F", 246 => x"F", 247 => x"F", 248 => x"F", 249 => x"F",
        250 => x"F", 251 => x"F", 252 => x"F", 253 => x"F", 254 => x"F",
        255 => x"F"
    );

    -- ─────────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────────
    type state_t is (
        S_IDLE,
        S_LATCH,
        S_MISS_SKY,
        S_DIFFUSE_1,    -- Nx*Sx
        S_DIFFUSE_2,    -- + Ny*Sy
        S_DIFFUSE_3,    -- + Nz*Sz → diff
        S_MATERIAL,     -- select base color, compute checker for ground
        S_LIGHT_MUL,    -- base * (sun_tint * diff + ambient)  per channel
        S_NOV_1,        -- compute -dot(rd, N) step 1: rdx*nx
        S_NOV_2,        -- + rdy*ny
        S_NOV_3,        -- + rdz*nz → NoV, then (1-NoV)
        S_FRESNEL,      -- (1-NoV)^4 = two squarings
        S_REFLECT_SKY,  -- simplified sky color from reflect direction
        S_MIX_REFL,     -- mix(col, sky_refl, fres_factor)
        S_FOG,          -- fog LUT + mix
        S_GAMMA_PACK    -- gamma LUT + pack RGB444
    );
    signal state : state_t := S_IDLE;

    -- ─────────────────────────────────────────────────────────────
    -- REGISTERED INPUTS (latched on start)
    -- ─────────────────────────────────────────────────────────────
    signal r_hit    : std_logic;
    signal r_mat    : std_logic_vector(2 downto 0);
    signal r_hx, r_hy, r_hz : pos_t;
    signal r_nx, r_ny, r_nz : dir_t;
    signal r_dx, r_dy, r_dz : dir_t;  -- ray direction
    signal r_t      : pos_t;

    -- ─────────────────────────────────────────────────────────────
    -- WORKING REGISTERS
    -- ─────────────────────────────────────────────────────────────
    -- Color accumulator (R, G, B)
    signal col_r, col_g, col_b : col_t := (others => '0');

    -- Diffuse intensity dot(N, sun)
    signal diff      : col_t := (others => '0');

    -- Fresnel-related
    signal nov       : col_t := (others => '0');  -- max(0, -dot(rd, N))
    signal fres      : col_t := (others => '0');  -- fresnel term

    -- Sky reflection color
    signal sky_r, sky_g, sky_b : col_t := (others => '0');

    -- Temporary accumulator for dot products
    signal acc       : col_t := (others => '0');

    -- Base color per material
    signal base_r, base_g, base_b : col_t := (others => '0');

    -- Useful constants
    constant COL_ZERO : col_t := to_sfixed(0.0,   1, -10);
    constant COL_ONE  : col_t := to_sfixed(0.999, 1, -10);

begin

    process(clk)
        variable v_acc     : col_t;
        variable v_tmp     : col_t;
        variable v_fres_factor : col_t;
        variable v_fog_idx : integer range 0 to 31;
        variable v_fog_amt : col_t;
        variable v_lin_r, v_lin_g, v_lin_b : integer range 0 to 255;
        variable v_checker : std_logic;
        variable v_ck      : col_t;
        -- For sky color calculation
        variable v_sky_t   : col_t;
        variable v_fog_slv : std_logic_vector(11 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= S_IDLE;
                done       <= '0';
                rgb444_out <= (others => '0');
            else
                case state is

                -- ══════════════════════════════════════════════════
                -- IDLE: wait for start
                -- ══════════════════════════════════════════════════
                when S_IDLE =>
                    done <= '0';
                    if start = '1' then
                        state <= S_LATCH;
                    end if;

                -- ══════════════════════════════════════════════════
                -- LATCH: register all inputs
                -- ══════════════════════════════════════════════════
                when S_LATCH =>
                    r_hit <= hit_flag;
                    r_mat <= mat_id;
                    r_hx  <= hit_pos_x;
                    r_hy  <= hit_pos_y;
                    r_hz  <= hit_pos_z;
                    r_nx  <= normal_x;
                    r_ny  <= normal_y;
                    r_nz  <= normal_z;
                    r_dx  <= ray_dir_x;
                    r_dy  <= ray_dir_y;
                    r_dz  <= ray_dir_z;
                    r_t   <= march_t;

                    if hit_flag = '1' then
                        state <= S_DIFFUSE_1;
                    else
                        state <= S_MISS_SKY;
                    end if;

                -- ══════════════════════════════════════════════════
                -- MISS → output sky color (simplified gradient)
                -- Python: sky_col(rd)
                -- Simplified: gradient based on ray_dir_y
                --   t = clamp(rd_y * 0.5 + 0.5, 0, 1)
                --   color = mix(horizon, zenith, t)
                -- ══════════════════════════════════════════════════
                when S_MISS_SKY =>
                    -- Approximate sky: use ray_dir_y to blend
                    -- rd_y is dir_t (Q2.16). We want t = rd_y*0.5 + 0.5
                    -- For simplicity: if rd_y >= 0 → blend toward zenith
                    --                  if rd_y <  0 → horizon
                    v_sky_t := resize(
                        to_sfixed(0.5, 1, -10) +
                        mul_dd(r_dy, to_sfixed(0.5, 1, -16)),
                        1, -10);
                    v_sky_t := clamp01(v_sky_t);

                    -- mix(horizon, zenith, t) = horizon - t*(horizon - zenith)
                    -- We subtract to keep the constant (SKY_HOR - SKY_ZEN) positive, 
                    -- working around potential Vivado synthesis bugs with negative sfixed constants.
                    col_r <= resize(SKY_HOR_R - mul_cc(v_sky_t,
                                resize(SKY_HOR_R - SKY_ZEN_R, 1, -10)), 1, -10);
                    col_g <= resize(SKY_HOR_G - mul_cc(v_sky_t,
                                resize(SKY_HOR_G - SKY_ZEN_G, 1, -10)), 1, -10);
                    col_b <= resize(SKY_HOR_B - mul_cc(v_sky_t,
                                resize(SKY_HOR_B - SKY_ZEN_B, 1, -10)), 1, -10);

                    state <= S_GAMMA_PACK;

                -- ══════════════════════════════════════════════════
                -- DIFFUSE step 1: acc = Nx * SUN_DIR_X
                -- ══════════════════════════════════════════════════
                when S_DIFFUSE_1 =>
                    acc   <= mul_dp(r_nx, SUN_DIR_X);
                    state <= S_DIFFUSE_2;

                -- DIFFUSE step 2: acc += Ny * SUN_DIR_Y
                when S_DIFFUSE_2 =>
                    acc   <= resize(acc + mul_dp(r_ny, SUN_DIR_Y), 1, -10);
                    state <= S_DIFFUSE_3;

                -- DIFFUSE step 3: acc += Nz * SUN_DIR_Z → clamp to [0,1]
                when S_DIFFUSE_3 =>
                    v_acc := resize(acc + mul_dp(r_nz, SUN_DIR_Z), 1, -10);
                    -- clamp: max(0, dot(N, sun))
                    if v_acc < COL_ZERO then
                        diff <= COL_ZERO;
                    else
                        diff <= v_acc;
                    end if;
                    state <= S_MATERIAL;

                -- ══════════════════════════════════════════════════
                -- MATERIAL: select base color
                -- Ground: checkerboard pattern from hit_pos integer bits
                -- Sphere: constant deep blue
                -- ══════════════════════════════════════════════════
                when S_MATERIAL =>
                    if r_mat = "000" then
                        -- Ground: checkerboard
                        -- Python: (floor(px) + floor(pz)) & 1
                        -- FPGA: XOR of sign+integer bits
                        -- hit_pos_x is sfixed(5 downto -12)
                        -- Integer part is bits 5 downto 0 (the part above the binary point)
                        -- floor() for negative: sfixed already truncates toward -inf
                        -- We take bit 0 of the integer part of x XOR bit 0 of integer part of z
                        v_checker := r_hx(0) xor r_hz(0);

                        if v_checker = '1' then
                            -- Dark tile: 0.10
                            base_r <= to_sfixed(0.10,   1, -10);
                            base_g <= to_sfixed(0.097,  1, -10);  -- 0.10 * 0.97
                            base_b <= to_sfixed(0.093,  1, -10);  -- 0.10 * 0.93
                        else
                            -- Light tile: 0.88
                            base_r <= to_sfixed(0.88,   1, -10);
                            base_g <= to_sfixed(0.854,  1, -10);  -- 0.88 * 0.97
                            base_b <= to_sfixed(0.818,  1, -10);  -- 0.88 * 0.93
                        end if;
                    else
                        -- Sphere: deep blue metallic
                        base_r <= SPH_BASE_R;
                        base_g <= SPH_BASE_G;
                        base_b <= SPH_BASE_B;
                    end if;
                    state <= S_LIGHT_MUL;

                -- ══════════════════════════════════════════════════
                -- LIGHT: col = base * (sun_tint * diff + ambient)
                -- Python (ground): col = base * ([1,0.88,0.72]*diff*0.9 + [0.15,0.22,0.42]*0.3)
                -- Python (sphere): col = base * ([1,0.88,0.72]*diff     + [0.10,0.16,0.40]*0.45)
                -- No shadow ray — omitted for simplicity (soft_shadow would
                -- require re-marching; can be added later as a separate module)
                -- ══════════════════════════════════════════════════
                when S_LIGHT_MUL =>
                    if r_mat = "000" then
                        -- Ground lighting
                        col_r <= mul_cc(base_r, resize(mul_cc(SUN_TINT_R, diff) + GND_AMB_R, 1, -10));
                        col_g <= mul_cc(base_g, resize(mul_cc(SUN_TINT_G, diff) + GND_AMB_G, 1, -10));
                        col_b <= mul_cc(base_b, resize(mul_cc(SUN_TINT_B, diff) + GND_AMB_B, 1, -10));
                    else
                        -- Sphere lighting
                        col_r <= mul_cc(base_r, resize(mul_cc(SUN_TINT_R, diff) + SPH_AMB_R, 1, -10));
                        col_g <= mul_cc(base_g, resize(mul_cc(SUN_TINT_G, diff) + SPH_AMB_G, 1, -10));
                        col_b <= mul_cc(base_b, resize(mul_cc(SUN_TINT_B, diff) + SPH_AMB_B, 1, -10));
                    end if;
                    state <= S_NOV_1;

                -- ══════════════════════════════════════════════════
                -- NoV computation: NoV = max(0, -dot(ray_dir, normal))
                -- Step 1: acc = -(rdx * nx)
                -- ══════════════════════════════════════════════════
                when S_NOV_1 =>
                    -- negate: -dot(rd,n) = -(rdx*nx + rdy*ny + rdz*nz)
                    -- start with -rdx*nx
                    acc   <= resize(-mul_dd(r_dx, r_nx), 1, -10);
                    state <= S_NOV_2;

                when S_NOV_2 =>
                    acc   <= resize(acc - mul_dd(r_dy, r_ny), 1, -10);
                    state <= S_NOV_3;

                when S_NOV_3 =>
                    v_acc := resize(acc - mul_dd(r_dz, r_nz), 1, -10);
                    if v_acc < COL_ZERO then
                        nov <= COL_ZERO;
                    elsif v_acc > COL_ONE then
                        nov <= COL_ONE;
                    else
                        nov <= v_acc;
                    end if;
                    state <= S_FRESNEL;

                -- ══════════════════════════════════════════════════
                -- FRESNEL: fres = (1 - NoV)^4
                -- Python (ground): 0.04 + 0.96 * (1-NoV)^5, then * 0.5 + 0.06
                -- Python (sphere): 0.05 + 0.95 * (1-NoV)^4, then * 0.65
                -- Simplified: fres ≈ (1-NoV)^4  (drop the F0 offset, close enough for 4-bit)
                -- (1-NoV)^4 = ((1-NoV)^2)^2 — only 2 multiplies
                -- ══════════════════════════════════════════════════
                when S_FRESNEL =>
                    v_tmp := resize(COL_ONE - nov, 1, -10);  -- (1 - NoV)
                    v_tmp := mul_cc(v_tmp, v_tmp);           -- (1-NoV)^2
                    fres  <= mul_cc(v_tmp, v_tmp);           -- (1-NoV)^4

                    -- Compute simplified sky reflection color
                    -- reflect(rd, N) direction's y component ≈ 2*NoV*Ny - rdy
                    -- For the sky gradient, we only care about the y component
                    -- refl_y = rdy - 2*(rdx*nx+rdy*ny+rdz*nz)*ny
                    -- Since NoV = -dot(rd,n), refl_y = rdy + 2*NoV*ny
                    -- Use nov (already computed) * ny, doubled
                    state <= S_REFLECT_SKY;

                -- ══════════════════════════════════════════════════
                -- REFLECT_SKY: compute sky color from reflected direction
                -- Use same gradient as miss path but from reflected y
                -- refl_y ≈ rd_y + 2 * NoV * N_y
                -- ══════════════════════════════════════════════════
                when S_REFLECT_SKY =>
                    -- Reflected ray y component
                    -- 2*NoV*Ny: nov is col_t, r_ny is dir_t
                    -- mul: col_t * dir_t → we approximate as col_t
                    v_tmp := resize(
                        mul_cc(nov, resize(r_ny, 1, -10)),
                        1, -10);
                    -- refl_y ≈ rd_y + 2*NoV*ny
                    v_sky_t := resize(
                        to_sfixed(0.5, 1, -10) +
                        resize(r_dy, 1, -10) +
                        v_tmp + v_tmp,    -- Add twice to apply the missing 2.0x factor
                        1, -10);
                    v_sky_t := clamp01(v_sky_t);

                    -- Sky reflection color from gradient (subtract positive difference)
                    sky_r <= resize(SKY_HOR_R - mul_cc(v_sky_t,
                                resize(SKY_HOR_R - SKY_ZEN_R, 1, -10)), 1, -10);
                    sky_g <= resize(SKY_HOR_G - mul_cc(v_sky_t,
                                resize(SKY_HOR_G - SKY_ZEN_G, 1, -10)), 1, -10);
                    sky_b <= resize(SKY_HOR_B - mul_cc(v_sky_t,
                                resize(SKY_HOR_B - SKY_ZEN_B, 1, -10)), 1, -10);

                    state <= S_MIX_REFL;

                -- ══════════════════════════════════════════════════
                -- MIX_REFL: col = mix(col, sky_refl, fres_factor)
                -- Python (ground): fres_factor = clamp(fres*0.5+0.06, 0, 1)
                -- Python (sphere): fres_factor = clamp(fres*0.65, 0, 1)
                -- mix(a, b, t) = a + t*(b - a)
                -- ══════════════════════════════════════════════════
                when S_MIX_REFL =>
                    if r_mat = "000" then
                        -- Ground: fres * 0.5 + 0.06
                        v_fres_factor := resize(
                            mul_cc(fres, to_sfixed(0.5, 1, -10)) +
                            to_sfixed(0.06, 1, -10),
                            1, -10);
                    else
                        -- Sphere: fres * 0.65
                        v_fres_factor := mul_cc(fres, to_sfixed(0.65, 1, -10));
                    end if;
                    v_fres_factor := clamp01(v_fres_factor);

                    -- col = col + fres_factor * (sky - col)
                    col_r <= resize(col_r + mul_cc(v_fres_factor,
                                resize(sky_r - col_r, 1, -10)), 1, -10);
                    col_g <= resize(col_g + mul_cc(v_fres_factor,
                                resize(sky_g - col_g, 1, -10)), 1, -10);
                    col_b <= resize(col_b + mul_cc(v_fres_factor,
                                resize(sky_b - col_b, 1, -10)), 1, -10);

                    state <= S_FOG;

                -- ══════════════════════════════════════════════════
                -- FOG: col = mix(col, fog_color, fog_amt)
                -- fog_amt from LUT indexed by march_t integer part
                -- ══════════════════════════════════════════════════
                when S_FOG =>
                    -- Index fog LUT by integer part of march_t (bits 5 downto 0 = 0..31)
                    -- march_t is sfixed(5 downto -12), integer part is bits [5:0]
                    -- Clamp to positive
                    if r_t < to_sfixed(0.0, 5, -12) then
                        v_fog_idx := 0;
                    elsif r_t > to_sfixed(31.0, 5, -12) then
                        v_fog_idx := 31;
                    else
                        v_fog_idx := to_integer(unsigned(
                            std_logic_vector(r_t(4 downto 0))));
                    end if;

                    -- fog_amt as col_t: LUT value is 0..1023 representing 0.0..~1.0
                    -- Construct col_t (Q2.10) directly: "00" & 10-bit fraction
                    v_fog_slv := "00" & std_logic_vector(FOG_LUT(v_fog_idx));
                    v_fog_amt := mul_cc(to_sfixed(v_fog_slv, 1, -10), FOG_STRENGTH);

                    -- mix: col = col + fog_amt * (fog_color - col)
                    col_r <= clamp01(resize(col_r + mul_cc(v_fog_amt,
                                resize(FOG_R - col_r, 1, -10)), 1, -10));
                    col_g <= clamp01(resize(col_g + mul_cc(v_fog_amt,
                                resize(FOG_G - col_g, 1, -10)), 1, -10));
                    col_b <= clamp01(resize(col_b + mul_cc(v_fog_amt,
                                resize(FOG_B - col_b, 1, -10)), 1, -10));

                    state <= S_GAMMA_PACK;

                -- ══════════════════════════════════════════════════
                -- GAMMA + PACK: gamma LUT per channel, assemble RGB444
                -- col_t is Q2.10, range [0, 1)
                -- Scale to 0..255: take fractional bits [−1 downto −8]
                -- after clamping to [0, 1)
                -- ══════════════════════════════════════════════════
                when S_GAMMA_PACK =>
                    -- Convert col_t [0.0, 1.0) → 8-bit integer [0..255]
                    -- col_t bits: sign(1), int(1), frac(-1 to -10)
                    -- For [0, 1): take bits [-1 downto -8] as unsigned
                    v_lin_r := to_integer(unsigned(
                        std_logic_vector(clamp01(col_r)(-1 downto -8))));
                    v_lin_g := to_integer(unsigned(
                        std_logic_vector(clamp01(col_g)(-1 downto -8))));
                    v_lin_b := to_integer(unsigned(
                        std_logic_vector(clamp01(col_b)(-1 downto -8))));

                    -- Gamma LUT: 8-bit linear → 4-bit sRGB
                    rgb444_out <= std_logic_vector(GAMMA_LUT(v_lin_r))
                                & std_logic_vector(GAMMA_LUT(v_lin_g))
                                & std_logic_vector(GAMMA_LUT(v_lin_b));

                    done  <= '1';
                    state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;