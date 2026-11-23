// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_8
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_8
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic [ 2 : 0 ] idq_cnt_q,
    input wire logic [ 1 : 0 ] decode_slot_valid
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_8
`endif

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_13
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_13
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic [ 3 : 0 ] sb_cnt_q,
    input wire logic [ 1 : 0 ] dut_issue_ack,
    input wire logic [ 1 : 0 ] dut_issue_valid,
    input wire logic flush_unissued
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_13
`endif

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_22
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_22
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic st_req,
    input wire logic [ 31 : 0 ] dut_store_data,
    input wire logic [ 9 : 0 ] dut_store_index,
    input wire logic raw_store_grant
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_22
`endif

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_26
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_26
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic [ 7 : 0 ] dut_issued
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

reg out_of_reset_q ;

always @ ( posedge clk_i or negedge rst_ni ) if ( ! rst_ni ) out_of_reset_q <= 1 'b 0 ; else out_of_reset_q <= 1 'b 1 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_26
`endif

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_27
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_27
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic [ 2 : 0 ] dut_issue_pointer,
    input wire logic [ 1 : 0 ] [ 2 : 0 ] dut_commit_pointer
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

reg out_of_reset_q ;

always @ ( posedge clk_i or negedge rst_ni ) if ( ! rst_ni ) out_of_reset_q <= 1 'b 0 ; else out_of_reset_q <= 1 'b 1 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_27
`endif

`ifdef BLOCK_HARD_CASE_cva6_frontend_issue_commit_28
// BEGIN BLOCK_HARD_CASE cva6_frontend_issue_commit_28
`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input wire logic clk_i,
    input wire logic rst_ni,
    input wire logic [ 1 : 0 ] dut_load_buffer_valid
);

localparam bit [ 31 : 0 ] FETCH_FIFO_DEPTH = 32 'h 4 ;

localparam bit signed [ 31 : 0 ] NSB = 32 'sh 8 ;

localparam bit signed [ 31 : 0 ] TIDW = 32 'sh 3 ;

localparam bit signed [ 31 : 0 ] NLD = 32 'sh 2 ;

localparam bit signed [ 31 : 0 ] FETCH_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] LOAD_BOUND = 32 'sh 20 ;

localparam bit signed [ 31 : 0 ] STORE_BOUND = 32 'sh 20 ;

reg out_of_reset_q ;

always @ ( posedge clk_i or negedge rst_ni ) if ( ! rst_ni ) out_of_reset_q <= 1 'b 0 ; else out_of_reset_q <= 1 'b 1 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE cva6_frontend_issue_commit_28
`endif
