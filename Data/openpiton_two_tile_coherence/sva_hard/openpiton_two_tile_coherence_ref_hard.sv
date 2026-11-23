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



T_RESET_L2_MSHR_ALL_INVAL: assert property (@(posedge clk) disable iff (!reset_n)
    !t_ready |-> ((l2_state_e[0][0] == 2'd0) &&
        (l2_state_e[0][1] == 2'd0) &&
        (l2_state_e[0][2] == 2'd0) &&
        (l2_state_e[0][3] == 2'd0) &&
        (l2_state_e[0][4] == 2'd0) &&
        (l2_state_e[0][5] == 2'd0) &&
        (l2_state_e[0][6] == 2'd0) &&
        (l2_state_e[0][7] == 2'd0) &&
        (l2_state_e[1][0] == 2'd0) &&
        (l2_state_e[1][1] == 2'd0) &&
        (l2_state_e[1][2] == 2'd0) &&
        (l2_state_e[1][3] == 2'd0) &&
        (l2_state_e[1][4] == 2'd0) &&
        (l2_state_e[1][5] == 2'd0) &&
        (l2_state_e[1][6] == 2'd0) &&
        (l2_state_e[1][7] == 2'd0))
);
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



T_RESET_L15_TRACKERS_IDLE: assert property (@(posedge clk) disable iff (!reset_n)
    !t_ready |-> ((ld_val[0] == 2'd0) &&
        (st_val[0] == 2'd0) &&
        (if_val[0] == 2'd0) &&
        (ld_val[1] == 2'd0) &&
        (st_val[1] == 2'd0) &&
        (if_val[1] == 2'd0))
);
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



T_LIFECYCLE_L2_MSHR_STATE_LEGAL: assert property (@(posedge clk) disable iff (!reset_n)
    ((l2_state_e[0][0] != 2'd3) &&
        (l2_state_e[0][1] != 2'd3) &&
        (l2_state_e[0][2] != 2'd3) &&
        (l2_state_e[0][3] != 2'd3) &&
        (l2_state_e[0][4] != 2'd3) &&
        (l2_state_e[0][5] != 2'd3) &&
        (l2_state_e[0][6] != 2'd3) &&
        (l2_state_e[0][7] != 2'd3) &&
        (l2_state_e[1][0] != 2'd3) &&
        (l2_state_e[1][1] != 2'd3) &&
        (l2_state_e[1][2] != 2'd3) &&
        (l2_state_e[1][3] != 2'd3) &&
        (l2_state_e[1][4] != 2'd3) &&
        (l2_state_e[1][5] != 2'd3) &&
        (l2_state_e[1][6] != 2'd3) &&
        (l2_state_e[1][7] != 2'd3))
);
endmodule

`default_nettype wire
// END BLOCK_HARD_CASE openpiton_two_tile_coherence_6
`endif
