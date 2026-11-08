`timescale 1ns/1ps
`default_nettype none

module two_tile_targets (
    input logic clk,
    input logic reset_n,
    input logic t_ready,
    input logic [1:0] l15_n3_val,
    input logic [1:0] l15_n3_rdy,
    input logic [1:0] l2_n2_val,
    input logic [1:0] l2_n2_rdy,
    input logic [15:0] sh_excl0,
    input logic [15:0] sh_excl1,
    input logic [15:0] sh_shared0,
    input logic [15:0] sh_shared1,
    input logic [15:0] l2_busy,
    input logic [11:0] l15_trk,
    input logic [1:0] ld_val [0:1],
    input logic [1:0] st_val [0:1],
    input logic [1:0] if_val [0:1],
    input logic [1:0] ld_alloc [0:1],
    input logic [1:0] st_alloc [0:1],
    input logic [1:0] if_alloc [0:1],
    input logic [1:0] ld_free [0:1],
    input logic [1:0] st_free [0:1],
    input logic [1:0] if_free [0:1],
    input logic r_ev [0:1],
    input logic [3:0] r_key [0:1],
    input logic l2_state_illegal,
    input logic dut_pop_inv_t0
);

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
