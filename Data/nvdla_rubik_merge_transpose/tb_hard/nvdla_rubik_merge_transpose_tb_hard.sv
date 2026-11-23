// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_nvdla_rubik_merge_transpose_11
// BEGIN BLOCK_HARD_CASE nvdla_rubik_merge_transpose_11
`timescale 1ns/1ps
`default_nettype none

module nvdla_rubik_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic [ 1 : 0 ] wptr,
    input wire logic [ 1 : 0 ] rptr,
    input wire logic wr_odone,
    input wire logic rd_odone
);

localparam [ 9 : 0 ] N_OUT_WAIT = 10 'd 8 ;

localparam [ 9 : 0 ] N_POP_WAIT = 10 'd 16 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 32 ;

reg [ 1 : 0 ] banks_ready ;

always @ ( posedge clk or negedge reset_n ) begin if ( ! reset_n ) begin banks_ready <= 2 'd 0 ; end else begin banks_ready <= banks_ready + ( wr_odone ? 2 'd 1 : 2 'd 0 ) - ( rd_odone ? 2 'd 1 : 2 'd 0 ) ; end end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_rubik_merge_transpose_11
`endif

`ifdef BLOCK_HARD_CASE_nvdla_rubik_merge_transpose_27
// BEGIN BLOCK_HARD_CASE nvdla_rubik_merge_transpose_27
`timescale 1ns/1ps
`default_nettype none

module nvdla_rubik_targets (
    input wire  clk,
    input wire  reset_n,
    input wire logic out_valid,
    input wire logic out_ready,
    input wire logic [ 513 : 0 ] out_pd
);

localparam [ 9 : 0 ] N_OUT_WAIT = 10 'd 8 ;

localparam [ 9 : 0 ] N_POP_WAIT = 10 'd 16 ;

localparam [ 9 : 0 ] N_STALL = 10 'd 32 ;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE nvdla_rubik_merge_transpose_27
`endif
