`timescale 1ns/1ps
`default_nettype none

module targets_openpiton_pmesh_order (
    input logic clk,
    input logic rst_ok,
    input logic first_cycle,
    input logic dlv,
    input logic [3:0] crd,
    input logic [4:0] e_t0_p,
    input logic [4:0] e_t1_p,
    input logic [4:0] e_t2_p,
    input logic [4:0] e_t5_p,
    input logic [2:0] e_t1_w,
    input logic [2:0] e_t2_w,
    input logic [2:0] e_t5_n,
    input logic [2:0] e_t8_n,
    input logic lv_t0e,
    input logic lv_t1e,
    input logic lv_t2s,
    input logic lv_t5s,
    input logic [4:0] c_src0,
    input logic [4:0] c_src1,
    input logic [4:0] c_src2,
    input logic [4:0] c_src3,
    input logic [134:0] nib_ne,
    input logic [134:0] nib_ptr_bad,
    input logic [134:0] nib_deq_empty,
    input logic [134:0] rq_multi,
    input logic [134:0] arb_bad,
    input logic [134:0] arb_enc_bad,
    input logic [134:0] arb_idle,
    input logic [134:0] sp_bad,
    input logic [134:0] sp_full,
    input logic [26:0] loc_bad,
    input logic [9:0] in_flight,
    input logic [4:0] e_t0_p_d,
    input logic [4:0] e_t1_p_d,
    input logic [4:0] e_t2_p_d,
    input logic [4:0] e_t5_p_d,
    input logic dut_route_req_n_to_n,
    input logic dut_thanks_n_to_n,
    input logic dut_route_req_n_to_e,
    input logic dut_thanks_e_to_n,
    input logic dut_route_req_n_to_s,
    input logic dut_thanks_s_to_n,
    input logic dut_route_req_n_to_w,
    input logic dut_thanks_w_to_n,
    input logic dut_route_req_n_to_p,
    input logic dut_thanks_p_to_n
);

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
