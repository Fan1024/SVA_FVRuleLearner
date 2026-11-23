// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_2
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_2
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 23 : 0 ] sq_data [ 0 : 1 ],
    input wire logic [ 15 : 0 ] sq_push_cnt,
    input wire logic [ 15 : 0 ] sq_pop_cnt,
    input wire logic [ 23 : 0 ] dut_sck_sw_status,
    input wire logic dut_sck_sw_we,
    input wire logic dut_sck_sw_ack
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_DATA_STATUS_SYNC_POP_EQ_PUSH: assert property (@(posedge clk_i) disable iff (!rst_ni) ((started & dut_sck_sw_we & dut_sck_sw_ack) && (sq_push_cnt != sq_pop_cnt)) |->
      (dut_sck_sw_status == sq_data[sq_pop_cnt[0]]));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_2
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_3
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_3
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 7 : 0 ] pl_idx,
    input wire logic rst_spi_n,
    input wire logic [ 7 : 0 ] dut_payload_wdata,
    input wire logic dut_payload_wvalid,
    input wire logic dut_payload_wready,
    input wire logic [ 31 : 0 ] raw_payload_sram_wdata
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_DATA_PAYLOAD_SRAM_LANE_IS_PUSHED_BYTE: assert property (@(posedge clk_i) disable iff (!rst_ni)
    ((started & dut_payload_wvalid & dut_payload_wready) && rst_spi_n) |->
      ($unsigned(8'(raw_payload_sram_wdata >> (8 * {30'd0, pl_idx[1:0]}))) == dut_payload_wdata)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_3
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_4
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_4
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 7 : 0 ] pl_idx,
    input wire logic rst_spi_n,
    input wire logic [ 9 : 0 ] dut_sck_sram_addr [ 0 : 2 ],
    input wire logic dut_payload_wvalid,
    input wire logic dut_payload_wready
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_DATA_PAYLOAD_SRAM_ADDR_IS_INDEX: assert property (@(posedge clk_i) disable iff (!rst_ni) ((started & dut_payload_wvalid & dut_payload_wready) && rst_spi_n) |->
      (dut_sck_sram_addr[2] == (SramPayloadIdx + SramAw'({2'd0, pl_idx[7:2]}))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_4
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_5
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_5
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic dut_payload_wvalid,
    input wire logic dut_payload_wready,
    input wire logic [ 31 : 0 ] raw_payload_sram_wmask
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_UNIQ_PAYLOAD_LANE_STRB_ONEHOT: assert property (@(posedge clk_i) disable iff (!rst_ni)
    (started & dut_payload_wvalid & dut_payload_wready) |-> $onehot({(&raw_payload_sram_wmask[31:24]), (&raw_payload_sram_wmask[23:16]), (&raw_payload_sram_wmask[15:8]), (&raw_payload_sram_wmask[7:0])})
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_5
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_11
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_11
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 15 : 0 ] sq_push_cnt,
    input wire logic [ 15 : 0 ] sq_pop_cnt
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_BOUND_STATUS_SYNC_OCC_LE_DEPTH: assert property (@(posedge clk_i) disable iff (!rst_ni) started |-> ($unsigned(16'(sq_push_cnt - sq_pop_cnt)) <= 16'(SDepth)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_11
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_12
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_12
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 4 : 0 ] dut_cmd_wptr,
    input wire logic dut_cmd_wvalid,
    input wire logic dut_cmd_wready
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_ALLOC_CMDFIFO_WPTR_ONLY_ON_PUSH: assert property (@(posedge clk_i) disable iff (!rst_ni) (started && !(started & dut_cmd_wvalid & dut_cmd_wready)) |=> $stable(dut_cmd_wptr));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_12
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_13
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_13
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic [ 4 : 0 ] dut_cmd_wptr,
    input wire logic dut_cmd_wvalid,
    input wire logic dut_cmd_wready
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_ALLOC_CMDFIFO_WPTR_STEPS_BY_ONE: assert property (@(posedge clk_i) disable iff (!rst_ni) (started & dut_cmd_wvalid & dut_cmd_wready) |=> (dut_cmd_wptr == ($past(dut_cmd_wptr) + 5'd1)));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_13
`endif

`ifdef BLOCK_HARD_CASE_opentitan_spi_device_fifo_14
// BEGIN BLOCK_HARD_CASE opentitan_spi_device_fifo_14
`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic started,
    input wire logic rst_spi_n,
    input wire logic dut_payload_wvalid,
    input wire logic [ 7 : 0 ] dut_payload_fifo_ptr,
    input wire logic dut_payload_wready
);

localparam bit [ 31 : 0 ] SramAw = 32 'h a ;

localparam logic [ 9 : 0 ] SramIngressIdx = 10 'h 380 ;

localparam logic [ 9 : 0 ] SramPayloadIdx = 10 'h 380 ;

localparam bit [ 31 : 0 ] SDepth = 32 'h 2 ;

localparam bit [ 31 : 0 ] IngressWords = 32 'h 70 ;

T_ALLOC_PAYLOAD_FIFOPTR_STEPS_BY_ONE: assert property (@(posedge clk_i) disable iff (!rst_ni) ((started & dut_payload_wvalid & dut_payload_wready) && rst_spi_n) |=>
      (!rst_spi_n
       || (dut_payload_fifo_ptr == (($past(dut_payload_fifo_ptr) == 8'd255)
                              ? 8'd0 : ($past(dut_payload_fifo_ptr) + 8'd1)))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE opentitan_spi_device_fifo_14
`endif
