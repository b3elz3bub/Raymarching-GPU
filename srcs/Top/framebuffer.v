`include "params.vh"
module framebuffer(
    input wr_clk,
    input rd_clk,
    input [$clog2(`SCREEN_WIDTH*`SCREEN_HEIGHT)-1:0] rd_addr, //x+640*y max 307,200 ~ 18.22 bits
    input [$clog2(`SCREEN_WIDTH*`SCREEN_HEIGHT)-1:0] wr_addr,
    input [`COLOR_DEPTH-1:0] write_data,
    input write_en,
    output reg [15:0] read_data
);
    (* ram_style = "block" *) reg [`COLOR_DEPTH-1:0] stored_data [0:`SCREEN_HEIGHT*`SCREEN_WIDTH-1];
    always@(posedge rd_clk) begin
        read_data <= stored_data[rd_addr];
    end
    always@(posedge wr_clk) begin
        if(write_en) stored_data[wr_addr]<= write_data;
    end
endmodule