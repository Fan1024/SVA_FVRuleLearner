// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_0
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_0
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic cvt_valid,
    input wire logic cvt_ready,
    input wire logic p1_valid,
    input wire logic p2_valid
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_ORDER_CVT_PAIR_ENTERS_BOTH_PIPES_TOGETHER: assert property (@(posedge clk)
      disable iff (!reset_n)
      (cvt_valid  && cvt_ready) |=> (p1_valid && p2_valid));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_0
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_5
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_5
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 6 : 0 ] d_wr_count,
    input wire logic [ 6 : 0 ] d_wr_adr,
    input wire logic [ 6 : 0 ] d_rd_adr
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_UNIQ_DATA_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((d_wr_count == 7'd80) ? ($unsigned(8'((d_wr_adr >= d_rd_adr) ? ({1'b0, d_wr_adr} - {1'b0, d_rd_adr})
                                             : ({1'b0, d_wr_adr} + 8'd80 - {1'b0, d_rd_adr}))) == 8'd0) : ($unsigned(8'((d_wr_adr >= d_rd_adr) ? ({1'b0, d_wr_adr} - {1'b0, d_rd_adr})
                                             : ({1'b0, d_wr_adr} + 8'd80 - {1'b0, d_rd_adr}))) == {1'b0, d_wr_count})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_5
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_6
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_6
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 6 : 0 ] i_wr_count,
    input wire logic [ 6 : 0 ] i_wr_adr,
    input wire logic [ 6 : 0 ] i_rd_adr
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_UNIQ_INFO_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((i_wr_count == 7'd80) ? ($unsigned(8'((i_wr_adr >= i_rd_adr) ? ({1'b0, i_wr_adr} - {1'b0, i_rd_adr})
                                             : ({1'b0, i_wr_adr} + 8'd80 - {1'b0, i_rd_adr}))) == 8'd0) : ($unsigned(8'((i_wr_adr >= i_rd_adr) ? ({1'b0, i_wr_adr} - {1'b0, i_rd_adr})
                                             : ({1'b0, i_wr_adr} + 8'd80 - {1'b0, i_rd_adr}))) == {1'b0, i_wr_count})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_6
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_7
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_7
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 5 : 0 ] s_wr_count,
    input wire logic [ 5 : 0 ] s_wr_adr,
    input wire logic [ 5 : 0 ] s_rd_adr
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_UNIQ_SUM_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((s_wr_count == 6'd60) ? ($unsigned(8'((s_wr_adr >= s_rd_adr) ? ({2'd0, s_wr_adr} - {2'd0, s_rd_adr})
                                             : ({2'd0, s_wr_adr} + 8'd60 - {2'd0, s_rd_adr}))) == 8'd0) : ($unsigned(8'((s_wr_adr >= s_rd_adr) ? ({2'd0, s_wr_adr} - {2'd0, s_rd_adr})
                                             : ({2'd0, s_wr_adr} + 8'd60 - {2'd0, s_rd_adr}))) == {2'd0, s_wr_count})));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_7
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_8
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_8
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic cvt_valid,
    input wire logic cvt_ready,
    input wire logic mul_valid,
    input wire logic mul_ready,
    input wire logic p1_valid,
    input wire logic [ 6 : 0 ] d_rd_count
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

wire  cvt_fire = cvt_valid && cvt_ready ;

wire  mul_fire = mul_valid && mul_ready ;

reg [ 7 : 0 ] data_held ;

always @ ( posedge clk or negedge reset_n ) begin if ( ! reset_n ) begin data_held <= 8 'd 0 ; end else begin data_held <= data_held + ( cvt_fire ? 8 'd 1 : 8 'd 0 ) - ( mul_fire ? 8 'd 1 : 8 'd 0 ) ; end end

T_CONSERV_DATA_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (data_held == $unsigned(8'({7'd0, p1_valid} + {1'b0, d_rd_count} + {7'd0, mul_valid}))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_8
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_9
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_9
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic cvt_valid,
    input wire logic cvt_ready,
    input wire logic ocvt_valid,
    input wire logic ocvt_ready,
    input wire logic p2_valid,
    input wire logic [ 6 : 0 ] i_rd_count
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

wire  cvt_fire = cvt_valid && cvt_ready ;

wire  ocvt_fire = ocvt_valid && ocvt_ready ;

reg [ 7 : 0 ] info_held ;

always @ ( posedge clk or negedge reset_n ) begin if ( ! reset_n ) begin info_held <= 8 'd 0 ; end else begin info_held <= info_held + ( cvt_fire ? 8 'd 1 : 8 'd 0 ) - ( ocvt_fire ? 8 'd 1 : 8 'd 0 ) ; end end

T_CONSERV_INFO_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (info_held == $unsigned(8'({7'd0, p2_valid} + {1'b0, i_rd_count} + {7'd0, ocvt_valid}))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_9
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_10
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_10
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic sum_valid,
    input wire logic sum_ready,
    input wire logic itp_valid,
    input wire logic itp_ready,
    input wire logic [ 5 : 0 ] s_rd_count
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

wire  sum_fire = sum_valid && sum_ready ;

wire  itp_fire = itp_valid && itp_ready ;

reg [ 7 : 0 ] sum_held ;

always @ ( posedge clk or negedge reset_n ) begin if ( ! reset_n ) begin sum_held <= 8 'd 0 ; end else begin sum_held <= sum_held + ( sum_fire ? 8 'd 1 : 8 'd 0 ) - ( itp_fire ? 8 'd 1 : 8 'd 0 ) ; end end

T_CONSERV_SUM_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sum_held == $unsigned(8'({2'd0, s_rd_count} + {7'd0, itp_valid}))));
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_10
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_29
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_29
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic mul_valid,
    input wire logic mul_ready,
    input wire logic [ 71 : 0 ] mul_pd
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_PROTO_MUL_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
    $past(reset_n && (mul_valid && !mul_ready)) |-> $stable(mul_pd)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_29
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_31
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_31
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic ocvt_valid,
    input wire logic ocvt_ready,
    input wire logic [ 14 : 0 ] ocvt_pd
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_PROTO_OCVT_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
    $past(reset_n && (ocvt_valid && !ocvt_ready)) |-> $stable(ocvt_pd)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_31
`endif

`ifdef BLOCK_HARD_CASE_nvdla_cdp_syncfifo_order_33
// BEGIN BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_33
`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic itp_valid,
    input wire logic itp_ready,
    input wire logic [ 167 : 0 ] itp_pd
);

localparam [ 7 : 0 ] N_CVT_PATH = 8 'd 82 ;

localparam [ 7 : 0 ] N_SUM_PATH = 8 'd 61 ;

localparam [ 9 : 0 ] N_DELIVER = 10 'd 32 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 64 ;

T_PROTO_ITP_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
    $past(reset_n && (itp_valid && !itp_ready)) |-> $stable(itp_pd)
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_33
`endif
