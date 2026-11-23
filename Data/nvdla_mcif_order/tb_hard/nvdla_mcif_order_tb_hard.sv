// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nvdla_mcif_order_9
// BEGIN BLOCK_HARD_CASE nvdla_mcif_order_9
`timescale 1ns/1ps
`default_nettype none

module nvdla_mcif_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 3 : 0 ] rsp_valid,
    input wire logic [ 3 : 0 ] rsp_ready
);

localparam integer NC = 4 ;

localparam integer QD = 8 ;

localparam [ 9 : 0 ] N_OS_WINDOW = 10 'd 16 ;

localparam [ 9 : 0 ] N_CLIENT_HOLD = 10 'd 20 ;

localparam [ 5 : 0 ] N_ARB_BYPASS = 6 'd 12 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_mcif_order_9
`endif

`ifdef BLOCK_HARD_CASE_nvdla_mcif_order_10
// BEGIN BLOCK_HARD_CASE nvdla_mcif_order_10
`timescale 1ns/1ps
`default_nettype none

module nvdla_mcif_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 3 : 0 ] rsp_valid,
    input wire logic [ 3 : 0 ] rsp_ready,
    input wire logic [ 2055 : 0 ] rsp_pd
);

localparam integer NC = 4 ;

localparam integer QD = 8 ;

localparam [ 9 : 0 ] N_OS_WINDOW = 10 'd 16 ;

localparam [ 9 : 0 ] N_CLIENT_HOLD = 10 'd 20 ;

localparam [ 5 : 0 ] N_ARB_BYPASS = 6 'd 12 ;

localparam [ 9 : 0 ] N_DRAIN = 10 'd 128 ;

localparam [ 9 : 0 ] N_ISSUE = 10 'd 128 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 256 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_mcif_order_10
`endif
