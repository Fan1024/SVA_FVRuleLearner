// One source file per design; select exactly one case with its macro.
// The Python loader selects the matching context using task_id.

`ifdef BLOCK_HARD_CASE_openpiton_two_tile_coherence_3
// BEGIN BLOCK_HARD_CASE openpiton_two_tile_coherence_3
`timescale 1ns/1ps
`default_nettype none

module two_tile_targets (
    input wire logic clk,
    input wire logic reset_n,
    input wire logic t_ready,
    input wire logic [ 1 : 0 ] l2_state_e [ 0 : 1 ] [ 0 : 7 ]
);



// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_two_tile_coherence_3
`endif

`ifdef BLOCK_HARD_CASE_openpiton_two_tile_coherence_4
// BEGIN BLOCK_HARD_CASE openpiton_two_tile_coherence_4
`timescale 1ns/1ps
`default_nettype none

module two_tile_targets (
    input wire logic clk,
    input wire logic reset_n,
    input wire logic t_ready,
    input wire logic [ 1 : 0 ] ld_val [ 0 : 1 ],
    input wire logic [ 1 : 0 ] st_val [ 0 : 1 ],
    input wire logic [ 1 : 0 ] if_val [ 0 : 1 ]
);



// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_two_tile_coherence_4
`endif

`ifdef BLOCK_HARD_CASE_openpiton_two_tile_coherence_6
// BEGIN BLOCK_HARD_CASE openpiton_two_tile_coherence_6
`timescale 1ns/1ps
`default_nettype none

module two_tile_targets (
    input wire logic clk,
    input wire logic reset_n,
    input wire logic [ 1 : 0 ] l2_state_e [ 0 : 1 ] [ 0 : 7 ]
);



// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_two_tile_coherence_6
`endif
