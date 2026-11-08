`timescale 1ns/1ps
`default_nettype none

module nyuzi_l2_targets (
    input logic clk,
    input logic reset,
    input logic [1:0] rdy,
    input logic [1:0] rqv,
    input logic rsp_v,
    input logic l2a_valid,
    input logic l2t_valid,
    input logic l2r_valid,
    input logic l2r_hit,
    input logic bi_req_valid,
    input logic bi_stall,
    input logic bi_collided,
    input logic deq_fill,
    input logic wb_complete,
    input logic fill_empty,
    input logic wb_empty,
    input logic fill_pending,
    input logic wbq_pending,
    input logic fill_full,
    input logic wbq_full,
    input logic [3:0] fill_cnt,
    input logic [1:0] bo_ff,
    input logic bus_rd_xfer,
    input logic w_acc,
    input logic [1:0] mem_w_beat,
    input logic [1:0] rd_cnt,
    input logic [4:0] shq [0:7],
    input logic [2:0] sh_rd,
    input logic [3:0] sh_cnt,
    input logic [4:0] sh_pop_exp,
    input logic [3:0] fair_cnt [0:1],
    input logic iinv_p2,
    input logic [1:0] [3:0] iinv_live,
    input logic sm_v,
    input logic [7:0] sm_byte,
    input logic [31:0] sm_base,
    input logic dtag_onehot_ok,
    input logic deq_src_onehot_ok,
    input logic store_ack_wrote_ok,
    input logic dut_axi_arvalid,
    input logic dut_mem_read_active,
    input logic dut_axi_wlast,
    input logic [511:0] dut_l2_response_data,
    input logic [2:0] l2r_req_packet_type
);
localparam logic [2:0] L2REQ_FLUSH = 3'h4;
localparam bit signed [31:0] BURST_BEATS = 32'sh4;
localparam bit signed [31:0] BEATW = 32'sh2;
// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
