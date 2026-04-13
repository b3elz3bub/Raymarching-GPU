-- ============================================================================
-- render_controller.vhd — Pixel-sequential render orchestrator
--
-- State machine that iterates over every pixel in the frame and sequences:
--   raygen → raymarch → shader → framebuffer write
--
-- One pixel is processed at a time (no pipelining).
-- A full 640×480 frame takes ~307,200 × ~100 cycles ≈ 30M cycles ≈ 0.3s @ 100MHz.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.params_pkg.all;

entity render_controller is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        frame_dirty   : in  std_logic;    -- pulse from camera: re-render needed

        -- Camera position (from camera controller)
        cam_x, cam_y, cam_z : in pos_t;

        -- ── Raygen interface ──────────────────────────
        rg_start      : out std_logic;
        rg_done       : in  std_logic;
        rg_pixx       : out std_logic_vector(17 downto 0);
        rg_pixy       : out std_logic_vector(17 downto 0);
        rg_cam_x      : out pos_t;
        rg_cam_y      : out pos_t;
        rg_cam_z      : out pos_t;
        -- Raygen outputs (directly wired to raymarch inputs at top level)
        rg_ray_orig_x : in  pos_t;
        rg_ray_orig_y : in  pos_t;
        rg_ray_orig_z : in  pos_t;
        rg_ray_dir_x  : in  dir_t;
        rg_ray_dir_y  : in  dir_t;
        rg_ray_dir_z  : in  dir_t;

        -- ── Raymarch interface ────────────────────────
        rm_start      : out std_logic;
        rm_done       : in  std_logic;
        rm_ray_orig_x : out pos_t;
        rm_ray_orig_y : out pos_t;
        rm_ray_orig_z : out pos_t;
        rm_ray_dir_x  : out dir_t;
        rm_ray_dir_y  : out dir_t;
        rm_ray_dir_z  : out dir_t;
        -- Raymarch outputs
        rm_hit        : in  std_logic;
        rm_obj_id     : in  unsigned(2 downto 0);
        rm_hit_x      : in  pos_t;
        rm_hit_y      : in  pos_t;
        rm_hit_z      : in  pos_t;
        rm_march_t    : in  pos_t;
        rm_norm_x     : in  dir_t;
        rm_norm_y     : in  dir_t;
        rm_norm_z     : in  dir_t;

        -- ── Shader interface ─────────────────────────
        sh_start      : out std_logic;
        sh_done       : in  std_logic;
        sh_hit_flag   : out std_logic;
        sh_mat_id     : out std_logic_vector(2 downto 0);
        sh_hit_pos_x  : out pos_t;
        sh_hit_pos_y  : out pos_t;
        sh_hit_pos_z  : out pos_t;
        sh_normal_x   : out dir_t;
        sh_normal_y   : out dir_t;
        sh_normal_z   : out dir_t;
        sh_march_t    : out pos_t;
        sh_ray_dir_x  : out dir_t;
        sh_ray_dir_y  : out dir_t;
        sh_ray_dir_z  : out dir_t;
        -- Shader output
        sh_rgb444     : in  std_logic_vector(11 downto 0);

        -- ── Framebuffer write port ───────────────────
        fb_wr_addr    : out std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
        fb_wr_data    : out std_logic_vector(COLOR_DEPTH - 1 downto 0);
        fb_wr_en      : out std_logic;

        -- ── Status ───────────────────────────────────
        rendering     : out std_logic     -- '1' while a frame is being rendered
    );
end entity render_controller;

architecture rtl of render_controller is

    -- ─────────────────────────────────────────────────────────
    -- STATE MACHINE
    -- ─────────────────────────────────────────────────────────
    type state_t is (
        S_IDLE,
        S_FRAME_INIT,
        S_START_RAYGEN,
        S_WAIT_RAYGEN,
        S_START_RAYMARCH,
        S_WAIT_RAYMARCH,
        S_START_SHADER,
        S_WAIT_SHADER,
        S_WRITE_FB,
        S_NEXT_PIXEL,
        S_FRAME_DONE
    );
    signal state : state_t := S_IDLE;

    -- Pixel counters
    signal pix_x : unsigned(9 downto 0) := (others => '0');  -- 0..639
    signal pix_y : unsigned(9 downto 0) := (others => '0');  -- 0..479

    -- Latched camera position for the current frame
    signal frame_cam_x, frame_cam_y, frame_cam_z : pos_t;

    -- Latched intermediate results (raygen → raymarch → shader pipeline)
    signal lat_ray_orig_x, lat_ray_orig_y, lat_ray_orig_z : pos_t;
    signal lat_ray_dir_x,  lat_ray_dir_y,  lat_ray_dir_z  : dir_t;

    -- Frame-dirty latch (edge detect: capture pulse, clear when render starts)
    signal dirty_latch : std_logic := '1';  -- start dirty so first frame renders

begin

    -- Capture frame_dirty pulses
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                dirty_latch <= '1';  -- render on reset
            elsif frame_dirty = '1' then
                dirty_latch <= '1';
            elsif state = S_FRAME_INIT then
                dirty_latch <= '0';
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────
    -- MAIN FSM
    -- ─────────────────────────────────────────────────────────
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= S_IDLE;
                rg_start  <= '0';
                rm_start  <= '0';
                sh_start  <= '0';
                fb_wr_en  <= '0';
                rendering <= '0';
            else
                -- Default: deassert one-cycle pulses
                rg_start <= '0';
                rm_start <= '0';
                sh_start <= '0';
                fb_wr_en <= '0';

                case state is

                -- ══════════════════════════════════════════════
                -- IDLE: wait for dirty frame
                -- ══════════════════════════════════════════════
                when S_IDLE =>
                    rendering <= '0';
                    if dirty_latch = '1' then
                        state <= S_FRAME_INIT;
                    end if;

                -- ══════════════════════════════════════════════
                -- FRAME_INIT: latch camera, reset pixel counters
                -- ══════════════════════════════════════════════
                when S_FRAME_INIT =>
                    rendering   <= '1';
                    frame_cam_x <= cam_x;
                    frame_cam_y <= cam_y;
                    frame_cam_z <= cam_z;
                    pix_x       <= (others => '0');
                    pix_y       <= (others => '0');
                    state       <= S_START_RAYGEN;

                -- ══════════════════════════════════════════════
                -- START_RAYGEN: issue start pulse to raygen
                -- ══════════════════════════════════════════════
                when S_START_RAYGEN =>
                    rg_pixx  <= std_logic_vector(resize(pix_x, 18));
                    rg_pixy  <= std_logic_vector(resize(pix_y, 18));
                    rg_cam_x <= frame_cam_x;
                    rg_cam_y <= frame_cam_y;
                    rg_cam_z <= frame_cam_z;
                    rg_start <= '1';
                    state    <= S_WAIT_RAYGEN;

                -- ══════════════════════════════════════════════
                -- WAIT_RAYGEN: wait for raygen done, latch results
                -- ══════════════════════════════════════════════
                when S_WAIT_RAYGEN =>
                    if rg_done = '1' then
                        lat_ray_orig_x <= rg_ray_orig_x;
                        lat_ray_orig_y <= rg_ray_orig_y;
                        lat_ray_orig_z <= rg_ray_orig_z;
                        lat_ray_dir_x  <= rg_ray_dir_x;
                        lat_ray_dir_y  <= rg_ray_dir_y;
                        lat_ray_dir_z  <= rg_ray_dir_z;
                        state          <= S_START_RAYMARCH;
                    end if;

                -- ══════════════════════════════════════════════
                -- START_RAYMARCH: forward ray to raymarcher
                -- ══════════════════════════════════════════════
                when S_START_RAYMARCH =>
                    rm_ray_orig_x <= lat_ray_orig_x;
                    rm_ray_orig_y <= lat_ray_orig_y;
                    rm_ray_orig_z <= lat_ray_orig_z;
                    rm_ray_dir_x  <= lat_ray_dir_x;
                    rm_ray_dir_y  <= lat_ray_dir_y;
                    rm_ray_dir_z  <= lat_ray_dir_z;
                    rm_start      <= '1';
                    state         <= S_WAIT_RAYMARCH;

                -- ══════════════════════════════════════════════
                -- WAIT_RAYMARCH: wait for march done
                -- ══════════════════════════════════════════════
                when S_WAIT_RAYMARCH =>
                    if rm_done = '1' then
                        state <= S_START_SHADER;
                    end if;

                -- ══════════════════════════════════════════════
                -- START_SHADER: forward hit data + ray direction
                -- ══════════════════════════════════════════════
                when S_START_SHADER =>
                    sh_hit_flag  <= rm_hit;
                    sh_mat_id    <= std_logic_vector(rm_obj_id);
                    sh_hit_pos_x <= rm_hit_x;
                    sh_hit_pos_y <= rm_hit_y;
                    sh_hit_pos_z <= rm_hit_z;
                    sh_normal_x  <= rm_norm_x;
                    sh_normal_y  <= rm_norm_y;
                    sh_normal_z  <= rm_norm_z;
                    sh_march_t   <= rm_march_t;
                    sh_ray_dir_x <= lat_ray_dir_x;
                    sh_ray_dir_y <= lat_ray_dir_y;
                    sh_ray_dir_z <= lat_ray_dir_z;
                    sh_start     <= '1';
                    state        <= S_WAIT_SHADER;

                -- ══════════════════════════════════════════════
                -- WAIT_SHADER: wait for shading done
                -- ══════════════════════════════════════════════
                when S_WAIT_SHADER =>
                    if sh_done = '1' then
                        state <= S_WRITE_FB;
                    end if;

                -- ══════════════════════════════════════════════
                -- WRITE_FB: write pixel color to framebuffer
                -- ══════════════════════════════════════════════
                when S_WRITE_FB =>
                    fb_wr_addr <= std_logic_vector(
                        resize(pix_y * to_unsigned(SCREEN_WIDTH, 10) + pix_x,
                               FB_ADDR_WIDTH));
                    fb_wr_data <= sh_rgb444;
                    fb_wr_en   <= '1';
                    state      <= S_NEXT_PIXEL;

                -- ══════════════════════════════════════════════
                -- NEXT_PIXEL: advance pixel counter
                -- ══════════════════════════════════════════════
                when S_NEXT_PIXEL =>
                    if pix_x = SCREEN_WIDTH - 1 then
                        pix_x <= (others => '0');
                        if pix_y = SCREEN_HEIGHT - 1 then
                            state <= S_FRAME_DONE;
                        else
                            pix_y <= pix_y + 1;
                            state <= S_START_RAYGEN;
                        end if;
                    else
                        pix_x <= pix_x + 1;
                        state <= S_START_RAYGEN;
                    end if;

                -- ══════════════════════════════════════════════
                -- FRAME_DONE: one frame complete
                -- ══════════════════════════════════════════════
                when S_FRAME_DONE =>
                    rendering <= '0';
                    state     <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;