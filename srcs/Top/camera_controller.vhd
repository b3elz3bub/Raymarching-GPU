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
begin
    process(clk)
    begin
        if rising_edge(clk) then
            frame_dirty <= '0';
            if rst = '1' then
                camera_x_reg <= CAM_INIT_X;
                camera_y_reg <= CAM_INIT_Y;
                camera_z_reg <= CAM_INIT_Z;
                frame_dirty  <= '1';
            else
                if btn_left_debounced = '1' then
                    camera_x_reg <= resize(camera_x_reg - CAM_STEP, pos_t'left, pos_t'right);
                    frame_dirty  <= '1';
                elsif btn_right_debounced = '1' then
                    camera_x_reg <= resize(camera_x_reg + CAM_STEP, pos_t'left, pos_t'right);
                    frame_dirty  <= '1';
                elsif btn_forward_debounced = '1' then
                    camera_z_reg <= resize(camera_z_reg + CAM_STEP, pos_t'left, pos_t'right);
                    frame_dirty  <= '1';
                elsif btn_back_debounced = '1' then
                    camera_z_reg <= resize(camera_z_reg - CAM_STEP, pos_t'left, pos_t'right);
                    frame_dirty  <= '1';
                end if;
            end if;
        end if;
    end process;

    cam_x <= camera_x_reg;
    cam_y <= camera_y_reg;
    cam_z <= camera_z_reg;
end architecture rtl;
