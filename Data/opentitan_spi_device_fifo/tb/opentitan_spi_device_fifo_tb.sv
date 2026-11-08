`timescale 1ns/1ps
`default_nettype none

module spi_device_fifo_targets (
    input logic clk_i,
    input logic rst_ni,
    input logic started,
    input logic cmd_push,
    input logic pl_push,
    input logic st_pop,
    input logic [15:0] cq_push_cnt,
    input logic [15:0] cq_pop_cnt,
    input logic [15:0] aq_pop_cnt,
    input logic [7:0] pl_idx,
    input logic [23:0] sq_data [0:1],
    input logic [15:0] sq_push_cnt,
    input logic [15:0] sq_pop_cnt,
    input logic [15:0] sq_occ,
    input logic [7:0] fw_arb_wait,
    input logic [7:0] pl_arb_wait,
    input logic [9:0] dp_sel_bits,
    input logic [7:0] pl_sram_lane_byte,
    input logic [3:0] pl_sram_strb,
    input logic [4:0] dut_cmd_rptr,
    input logic [4:0] dut_addr_rptr,
    input logic [23:0] dut_sck_sw_status,
    input logic rst_spi_n,
    input logic [7:0] dut_payload_wdata,
    input logic [9:0] dut_sck_sram_addr [0:2],
    input logic [4:0] dut_cmd_wptr,
    input logic dut_cmd_wvalid,
    input logic dut_addr_wvalid,
    input logic dut_payload_wvalid,
    input logic [2:0] dut_sck_sram_gnt,
    input logic [2:0] dut_sys_sram_gnt,
    input logic [7:0] dut_payload_fifo_ptr,
    input logic dut_sck_sw_we,
    input logic dut_cmd_rvalid,
    input logic dut_cmd_rready,
    input logic [15:0] dut_cmd_rdata,
    input logic dut_addr_rvalid,
    input logic dut_addr_rready,
    input logic dut_mem_b_req,
    input logic dut_mem_b_write,
    input logic [9:0] dut_mem_b_addr,
    input logic [1:0] dut_upload_state,
    input logic [7:0] dut_payload_ptr,
    input logic [23:0] dut_sck_staged_status,
    input logic dut_cmd_sync_pulse,
    input logic dut_addr_4b_en
);
localparam bit [31:0] SramAw = 32'ha;
localparam logic [9:0] SramIngressIdx = 10'h380;
localparam logic [9:0] SramPayloadIdx = 10'h380;
localparam bit [31:0] SDepth = 32'h2;
localparam bit [31:0] IngressWords = 32'h70;
// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
