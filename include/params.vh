`ifndef PARAMS_VH
`define PARAMS_VH

// 1. Fixed-Point Configuration (Q16.16)
parameter FP_WIDTH = 32;
parameter FP_FRACT = 16;

// 2. AXI-Lite Register Offsets
parameter ADDR_LIGHT_X    = 4'h0; // Register 0
parameter ADDR_LIGHT_Y    = 4'h4; // Register 1
parameter ADDR_CAM_Z      = 4'h8; // Register 2
parameter ADDR_SPHERE_R   = 4'hC; // Register 3

// 3. Display Configuration
parameter SCREEN_WIDTH    = 640;
parameter SCREEN_HEIGHT   = 480;
parameter COLOR_DEPTH     = 24; // 8-bit R, 8-bit G, 8-bit B

`endif