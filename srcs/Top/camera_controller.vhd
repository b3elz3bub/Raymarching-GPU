library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;
use work.params_pkg.all;

entity camera_controller is
    port (
        clk                   : in  std_logic;
        rst                   : in  std_logic;
        btn_left_debounced    : in  std_logic;   -- move X−
        btn_right_debounced   : in  std_logic;   -- move X+
        btn_forward_debounced : in  std_logic;   -- move Z+
        btn_back_debounced    : in  std_logic;   -- move Z−
        cam_x                 : out pos_t;
        cam_y                 : out pos_t;       -- fixed (no up/down button)
        cam_z                 : out pos_t;
        frame_dirty           : out std_logic    -- pulse: camera moved, re-render
    );
end entity camera_controller;

architecture rtl of camera_controller is
    signal camera_x_reg : pos_t := CAM_INIT_X;
    signal camera_y_reg : pos_t := CAM_INIT_Y;
    signal camera_z_reg : pos_t := CAM_INIT_Z;

    -- Repeat-rate timer: counts down while any button is held.
    -- The camera moves once immediately on press, then again every
    -- CAM_REPEAT_CYCLES clock cycles (~200ms) while held.
    signal repeat_timer : integer range 0 to CAM_REPEAT_CYCLES := 0;
    signal any_btn_prev : std_logic := '0';  -- edge detect for first press
begin
    process(clk)
        variable any_btn   : std_logic;
        variable do_update : std_logic;
    begin
        if rising_edge(clk) then
            frame_dirty <= '0';
            do_update   := '0';

            any_btn := btn_left_debounced or btn_right_debounced or
                        btn_forward_debounced or btn_back_debounced;

            if rst = '1' then
                camera_x_reg <= CAM_INIT_X;
                camera_y_reg <= CAM_INIT_Y;
                camera_z_reg <= CAM_INIT_Z;
                repeat_timer <= 0;
                any_btn_prev <= '0';
                frame_dirty  <= '1';
            else
                if any_btn = '1' then
                    -- Rising edge: move immediately on first press
                    if any_btn_prev = '0' then
                        do_update   := '1';
                        repeat_timer <= CAM_REPEAT_CYCLES;
                    else
                        -- Button held: count down repeat timer
                        if repeat_timer = 0 then
                            do_update    := '1';
                            repeat_timer <= CAM_REPEAT_CYCLES;
                        else
                            repeat_timer <= repeat_timer - 1;
                        end if;
                    end if;
                else
                    repeat_timer <= 0;
                end if;

                any_btn_prev <= any_btn;

                -- Apply movement
                if do_update = '1' then
                    if btn_left_debounced = '1' then
                        camera_x_reg <= resize(camera_x_reg - CAM_STEP, pos_t'left, pos_t'right);
                    elsif btn_right_debounced = '1' then
                        camera_x_reg <= resize(camera_x_reg + CAM_STEP, pos_t'left, pos_t'right);
                    end if;
                    if btn_forward_debounced = '1' then
                        camera_z_reg <= resize(camera_z_reg + CAM_STEP, pos_t'left, pos_t'right);
                    elsif btn_back_debounced = '1' then
                        camera_z_reg <= resize(camera_z_reg - CAM_STEP, pos_t'left, pos_t'right);
                    end if;
                    frame_dirty <= '1';
                end if;
            end if;
        end if;
    end process;

    cam_x <= camera_x_reg;
    cam_y <= camera_y_reg;
    cam_z <= camera_z_reg;
end architecture rtl;
