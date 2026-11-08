`timescale 1ns/1ps
`default_nettype none

module cva6_pipe_targets (
    input logic clk_i,
    input logic rst_ni,
    input logic [1:0] alloc,
    input logic [1:0] retire,
    input logic flush_if,
    input logic [2:0] sb_iptr_q,
    input logic [2:0] sb_cptr_q,
    input logic [7:0] sb_live_q,
    input logic [3:0] sb_cnt_q,
    input logic [3:0] sb_fu_q [0:7],
    input logic [2:0] retire_id0,
    input logic [7:0] dut_issued,
    input logic [4:0] sym_rd_q,
    input logic [31:0] rf_shadow_q,
    input logic rf_seen_q,
    input logic [1:0] rf_hit,
    input logic [2:0] idq_cnt_q,
    input logic [1:0] dut_id_occ,
    input logic ld_gnt,
    input logic ld_rvalid,
    input logic st_req,
    input logic st_gnt,
    input logic [2:0] ld_out_q,
    input logic [1:0] ld_id_live_q,
    input logic [3:0] st_q_cnt_q,
    input logic [9:0] fetch_wait_q,
    input logic [9:0] load_wait_q,
    input logic [9:0] store_wait_q,
    input logic ic_rsp,
    input logic first_cycle,
    input logic [2:0] dut_issue_pointer,
    input logic [1:0][2:0] dut_commit_pointer,
    input logic [2:0] dut_commit0_trans_id,
    input logic [2:0] dut_commit1_trans_id,
    input logic [1:0] dut_issue_ack,
    input logic [3:0] dut_commit0_fu,
    input logic [31:0][31:0] dut_gpr,
    input logic dut_ld_id,
    input logic [1:0] dut_load_buffer_valid,
    input logic [2:0] dut_store_commit_count,
    input logic [3:0] dut_instr_queue_select,
    input logic dut_lsu_load_valid,
    input logic dut_lsu_store_valid,
    input logic [2:0] dut_instr_fifo_count,
    input logic dut_ld_response_id,
    input logic dut_icache_pending,
    input logic [1:0] dut_issue_valid,
    input logic [31:0] dut_issue0_pc,
    input logic [1:0] dut_fetch_valid,
    input logic [1:0] dut_fetch_ready,
    input logic [31:0] dut_fetch0_addr,
    input logic [31:0] dut_store_data,
    input logic [9:0] dut_store_index,
    input logic [1:0] dut_commit_drop,
    input logic [1:0] dut_gpr_write
);
localparam bit [31:0] FETCH_FIFO_DEPTH = 32'h4;
localparam bit signed [31:0] NSB = 32'sh8;
localparam bit signed [31:0] TIDW = 32'sh3;
localparam bit signed [31:0] NLD = 32'sh2;
localparam bit signed [31:0] FETCH_BOUND = 32'sh20;
localparam bit signed [31:0] LOAD_BOUND = 32'sh20;
localparam bit signed [31:0] STORE_BOUND = 32'sh20;
// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
