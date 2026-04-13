-- ============================================================================
-- top.vhd — Raymarching GPU Top-Level Module
--
-- Instantiates and connects every module in the rendering pipeline:
--   Buttons → Debouncers → Camera Controller → Render Controller
--   Render Controller orchestrates: Raygen → Raymarch → Shader → Framebuffer
--   VGA Controller reads framebuffer and drives VGA output
--
-- Clock domains:
--   clk_100MHz  — system clock for the render pipeline
--   clk_25MHz   — pixel clock for VGA output (from clock wizard)
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.params_pkg.all;

entity top is
    port (
        clk_100MHz  : in  std_logic;       -- Board oscillator
        rst_btn     : in  std_logic;       -- Active-high reset button
        -- Camera control buttons (active-high, active from board)
        btn_left    : in  std_logic;
        btn_right   : in  std_logic;
        btn_forward : in  std_logic;
        btn_back    : in  std_logic;
        -- VGA output
        vga_hsync   : out std_logic;
        vga_vsync   : out std_logic;
        vga_rgb     : out std_logic_vector(11 downto 0)
    );
end entity top;

architecture structural of top is

    -- ─────────────────────────────────────────────────────────
    -- CLOCK WIZARD (100 MHz → 25 MHz for VGA)
    -- ─────────────────────────────────────────────────────────
    component clk_wiz_0
        port (
            clk_in1  : in  std_logic;
            clk_out1 : out std_logic;
            reset    : in  std_logic;
            locked   : out std_logic
        );
    end component;

    signal clk_25MHz : std_logic;
    signal clk_locked : std_logic;

    -- ─────────────────────────────────────────────────────────
    -- RESET
    -- ─────────────────────────────────────────────────────────
    signal sys_rst : std_logic;

    -- ─────────────────────────────────────────────────────────
    -- DEBOUNCED BUTTONS
    -- ─────────────────────────────────────────────────────────
    signal db_left, db_right, db_forward, db_back : std_logic;

    -- ─────────────────────────────────────────────────────────
    -- CAMERA CONTROLLER
    -- ─────────────────────────────────────────────────────────
    signal cam_x, cam_y, cam_z : pos_t;
    signal frame_dirty : std_logic;

    -- ─────────────────────────────────────────────────────────
    -- RAYGEN SIGNALS
    -- ─────────────────────────────────────────────────────────
    signal rg_start      : std_logic;
    signal rg_done       : std_logic;
    signal rg_pixx       : std_logic_vector(17 downto 0);
    signal rg_pixy       : std_logic_vector(17 downto 0);
    signal rg_cam_x, rg_cam_y, rg_cam_z : pos_t;
    signal rg_ray_orig_x, rg_ray_orig_y, rg_ray_orig_z : pos_t;
    signal rg_ray_dir_x,  rg_ray_dir_y,  rg_ray_dir_z  : dir_t;

    -- ─────────────────────────────────────────────────────────
    -- RAYMARCH SIGNALS
    -- ─────────────────────────────────────────────────────────
    signal rm_start      : std_logic;
    signal rm_done       : std_logic;
    signal rm_ray_orig_x, rm_ray_orig_y, rm_ray_orig_z : pos_t;
    signal rm_ray_dir_x,  rm_ray_dir_y,  rm_ray_dir_z  : dir_t;
    signal rm_hit        : std_logic;
    signal rm_obj_id     : unsigned(2 downto 0);
    signal rm_hit_x, rm_hit_y, rm_hit_z : pos_t;
    signal rm_march_t    : pos_t;
    signal rm_norm_x, rm_norm_y, rm_norm_z : dir_t;

    -- ─────────────────────────────────────────────────────────
    -- SHADER SIGNALS
    -- ─────────────────────────────────────────────────────────
    signal sh_start      : std_logic;
    signal sh_done       : std_logic;
    signal sh_hit_flag   : std_logic;
    signal sh_mat_id     : std_logic_vector(2 downto 0);
    signal sh_hit_pos_x, sh_hit_pos_y, sh_hit_pos_z : pos_t;
    signal sh_normal_x,  sh_normal_y,  sh_normal_z  : dir_t;
    signal sh_march_t    : pos_t;
    signal sh_ray_dir_x, sh_ray_dir_y, sh_ray_dir_z : dir_t;
    signal sh_rgb444     : std_logic_vector(11 downto 0);

    -- ─────────────────────────────────────────────────────────
    -- FRAMEBUFFER SIGNALS
    -- ─────────────────────────────────────────────────────────
    signal fb_wr_addr : std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
    signal fb_wr_data : std_logic_vector(COLOR_DEPTH - 1 downto 0);
    signal fb_wr_en   : std_logic;
    signal fb_rd_addr : std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
    signal fb_rd_data : std_logic_vector(COLOR_DEPTH - 1 downto 0);

    -- ─────────────────────────────────────────────────────────
    -- VGA CONTROLLER SIGNALS
    -- ─────────────────────────────────────────────────────────
    signal vga_pixel_x : std_logic_vector(9 downto 0);
    signal vga_pixel_y : std_logic_vector(9 downto 0);
    signal vga_active  : std_logic;
    signal vga_rgb_out : std_logic_vector(11 downto 0);

    -- Render status
    signal rendering : std_logic;

begin

    -- ═══════════════════════════════════════════════════════════
    -- RESET: hold system in reset until clock is locked
    -- ═══════════════════════════════════════════════════════════
    sys_rst <= rst_btn or (not clk_locked);

    -- ═══════════════════════════════════════════════════════════
    -- CLOCK WIZARD
    -- ═══════════════════════════════════════════════════════════
    CLK_GEN : clk_wiz_0
        port map (
            clk_in1  => clk_100MHz,
            clk_out1 => clk_25MHz,
            reset    => '0',
            locked   => clk_locked
        );

    -- ═══════════════════════════════════════════════════════════
    -- DEBOUNCERS (×4)
    -- ═══════════════════════════════════════════════════════════
    DB_LEFT_INST : entity work.debouncer
        port map (clk => clk_100MHz, reset => sys_rst,
                  button => btn_left, debounced => db_left);

    DB_RIGHT_INST : entity work.debouncer
        port map (clk => clk_100MHz, reset => sys_rst,
                  button => btn_right, debounced => db_right);

    DB_FWD_INST : entity work.debouncer
        port map (clk => clk_100MHz, reset => sys_rst,
                  button => btn_forward, debounced => db_forward);

    DB_BACK_INST : entity work.debouncer
        port map (clk => clk_100MHz, reset => sys_rst,
                  button => btn_back, debounced => db_back);

    -- ═══════════════════════════════════════════════════════════
    -- CAMERA CONTROLLER
    -- ═══════════════════════════════════════════════════════════
    CAM_CTRL : entity work.camera_controller
        port map (
            clk                   => clk_100MHz,
            rst                   => sys_rst,
            btn_left_debounced    => db_left,
            btn_right_debounced   => db_right,
            btn_forward_debounced => db_forward,
            btn_back_debounced    => db_back,
            cam_x                 => cam_x,
            cam_y                 => cam_y,
            cam_z                 => cam_z,
            frame_dirty           => frame_dirty
        );

    -- ═══════════════════════════════════════════════════════════
    -- RENDER CONTROLLER (orchestrates the pixel pipeline)
    -- ═══════════════════════════════════════════════════════════
    RENDER_CTRL : entity work.render_controller
        port map (
            clk           => clk_100MHz,
            rst           => sys_rst,
            frame_dirty   => frame_dirty,
            cam_x         => cam_x,
            cam_y         => cam_y,
            cam_z         => cam_z,
            -- Raygen interface
            rg_start      => rg_start,
            rg_done       => rg_done,
            rg_pixx       => rg_pixx,
            rg_pixy       => rg_pixy,
            rg_cam_x      => rg_cam_x,
            rg_cam_y      => rg_cam_y,
            rg_cam_z      => rg_cam_z,
            rg_ray_orig_x => rg_ray_orig_x,
            rg_ray_orig_y => rg_ray_orig_y,
            rg_ray_orig_z => rg_ray_orig_z,
            rg_ray_dir_x  => rg_ray_dir_x,
            rg_ray_dir_y  => rg_ray_dir_y,
            rg_ray_dir_z  => rg_ray_dir_z,
            -- Raymarch interface
            rm_start      => rm_start,
            rm_done       => rm_done,
            rm_ray_orig_x => rm_ray_orig_x,
            rm_ray_orig_y => rm_ray_orig_y,
            rm_ray_orig_z => rm_ray_orig_z,
            rm_ray_dir_x  => rm_ray_dir_x,
            rm_ray_dir_y  => rm_ray_dir_y,
            rm_ray_dir_z  => rm_ray_dir_z,
            rm_hit        => rm_hit,
            rm_obj_id     => rm_obj_id,
            rm_hit_x      => rm_hit_x,
            rm_hit_y      => rm_hit_y,
            rm_hit_z      => rm_hit_z,
            rm_march_t    => rm_march_t,
            rm_norm_x     => rm_norm_x,
            rm_norm_y     => rm_norm_y,
            rm_norm_z     => rm_norm_z,
            -- Shader interface
            sh_start      => sh_start,
            sh_done       => sh_done,
            sh_hit_flag   => sh_hit_flag,
            sh_mat_id     => sh_mat_id,
            sh_hit_pos_x  => sh_hit_pos_x,
            sh_hit_pos_y  => sh_hit_pos_y,
            sh_hit_pos_z  => sh_hit_pos_z,
            sh_normal_x   => sh_normal_x,
            sh_normal_y   => sh_normal_y,
            sh_normal_z   => sh_normal_z,
            sh_march_t    => sh_march_t,
            sh_ray_dir_x  => sh_ray_dir_x,
            sh_ray_dir_y  => sh_ray_dir_y,
            sh_ray_dir_z  => sh_ray_dir_z,
            sh_rgb444     => sh_rgb444,
            -- Framebuffer write
            fb_wr_addr    => fb_wr_addr,
            fb_wr_data    => fb_wr_data,
            fb_wr_en      => fb_wr_en,
            -- Status
            rendering     => rendering
        );

    -- ═══════════════════════════════════════════════════════════
    -- RAY GENERATOR
    -- ═══════════════════════════════════════════════════════════
    RAYGEN_INST : entity work.raygen
        port map (
            clk        => clk_100MHz,
            start      => rg_start,
            pixx       => rg_pixx,
            pixy       => rg_pixy,
            cam_x      => rg_cam_x,
            cam_y      => rg_cam_y,
            cam_z      => rg_cam_z,
            ray_orig_x => rg_ray_orig_x,
            ray_orig_y => rg_ray_orig_y,
            ray_orig_z => rg_ray_orig_z,
            ray_dir_x  => rg_ray_dir_x,
            ray_dir_y  => rg_ray_dir_y,
            ray_dir_z  => rg_ray_dir_z,
            done       => rg_done
        );

    -- ═══════════════════════════════════════════════════════════
    -- RAYMARCHER
    -- ═══════════════════════════════════════════════════════════
    RAYMARCH_INST : entity work.raymarch
        port map (
            clk        => clk_100MHz,
            rst        => sys_rst,
            start      => rm_start,
            ray_orig_x => rm_ray_orig_x,
            ray_orig_y => rm_ray_orig_y,
            ray_orig_z => rm_ray_orig_z,
            ray_dir_x  => rm_ray_dir_x,
            ray_dir_y  => rm_ray_dir_y,
            ray_dir_z  => rm_ray_dir_z,
            done       => rm_done,
            hit        => rm_hit,
            obj_id     => rm_obj_id,
            hit_x      => rm_hit_x,
            hit_y      => rm_hit_y,
            hit_z      => rm_hit_z,
            march_t    => rm_march_t,
            norm_x     => rm_norm_x,
            norm_y     => rm_norm_y,
            norm_z     => rm_norm_z
        );

    -- ═══════════════════════════════════════════════════════════
    -- SHADER
    -- ═══════════════════════════════════════════════════════════
    SHADER_INST : entity work.shader
        port map (
            clk        => clk_100MHz,
            rst        => sys_rst,
            start      => sh_start,
            hit_flag   => sh_hit_flag,
            mat_id     => sh_mat_id,
            hit_pos_x  => sh_hit_pos_x,
            hit_pos_y  => sh_hit_pos_y,
            hit_pos_z  => sh_hit_pos_z,
            normal_x   => sh_normal_x,
            normal_y   => sh_normal_y,
            normal_z   => sh_normal_z,
            march_t    => sh_march_t,
            ray_dir_x  => sh_ray_dir_x,
            ray_dir_y  => sh_ray_dir_y,
            ray_dir_z  => sh_ray_dir_z,
            rgb444_out => sh_rgb444,
            done       => sh_done
        );

    -- ═══════════════════════════════════════════════════════════
    -- FRAMEBUFFER (dual-port RAM: render writes, VGA reads)
    -- ═══════════════════════════════════════════════════════════
    FB_INST : entity work.framebuffer
        port map (
            wr_clk     => clk_100MHz,
            rd_clk     => clk_25MHz,
            wr_addr    => fb_wr_addr,
            rd_addr    => fb_rd_addr,
            write_data => fb_wr_data,
            write_en   => fb_wr_en,
            read_data  => fb_rd_data
        );

    -- ═══════════════════════════════════════════════════════════
    -- VGA CONTROLLER
    -- ═══════════════════════════════════════════════════════════
    VGA_INST : entity work.vga_controller
        port map (
            clk     => clk_25MHz,
            rgb_in  => fb_rd_data,
            rgb_out => vga_rgb_out,
            hsync   => vga_hsync,
            vsync   => vga_vsync,
            pixel_x => vga_pixel_x,
            pixel_y => vga_pixel_y,
            active  => vga_active
        );

    -- ═══════════════════════════════════════════════════════════
    -- FRAMEBUFFER READ ADDRESS GENERATION
    -- Compute: rd_addr = vga_pixel_y * SCREEN_WIDTH + vga_pixel_x
    -- Only valid during active region; clamp otherwise
    -- ═══════════════════════════════════════════════════════════
    process(vga_pixel_x, vga_pixel_y, vga_active)
        variable addr : unsigned(FB_ADDR_WIDTH - 1 downto 0);
    begin
        if vga_active = '1' then
            addr := resize(
                unsigned(vga_pixel_y) * to_unsigned(SCREEN_WIDTH, 10)
                + unsigned(vga_pixel_x),
                FB_ADDR_WIDTH);
            fb_rd_addr <= std_logic_vector(addr);
        else
            fb_rd_addr <= (others => '0');
        end if;
    end process;

    -- VGA RGB output
    vga_rgb <= vga_rgb_out;

end architecture structural;
