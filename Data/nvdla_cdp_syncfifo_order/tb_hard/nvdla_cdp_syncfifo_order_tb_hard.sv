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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
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

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_cdp_syncfifo_order_33
`endif
