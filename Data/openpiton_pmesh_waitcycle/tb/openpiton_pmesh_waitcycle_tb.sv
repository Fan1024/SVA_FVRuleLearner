`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_waitcycle (
    input logic clk,
    input logic rst_ok,
    input logic first_cycle,
    input logic dlv,
    input logic [63:0] dlv_flit,
    input logic [2:0] sink_occ,
    input logic [4:0] e_p [0:8],
    input logic [2:0] e_w [0:8],
    input logic [2:0] e_n [0:8],
    input logic [63:0] h_p [0:8],
    input logic [63:0] h_w [0:8],
    input logic [63:0] h_n [0:8],
    input logic th_t8p_n,
    input logic th_t8p_w,
    input logic th_t8p_p,
    input logic link_overfill,
    input logic [134:0] nib_ne,
    input logic [134:0] nib_ptr_bad,
    input logic [134:0] nib_deq_empty,
    input logic [134:0] rq_multi,
    input logic [134:0] grant_empty,
    input logic [134:0] arb_idle,
    input logic [134:0] sp_bad,
    input logic [134:0] sp_full,
    input logic [26:0] loc_bad,
    input logic [11:0] w_drain,
    input logic [11:0] w_nospace,
    input logic credit_only_on_dequeue_ok,
    input logic source_credit_account_ok,
    input logic source_credit_full_ok
);
localparam logic signed [31:0] DRAIN_N = 32'sh8;
localparam logic signed [31:0] NOSPACE_N = 32'sh20;
// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
