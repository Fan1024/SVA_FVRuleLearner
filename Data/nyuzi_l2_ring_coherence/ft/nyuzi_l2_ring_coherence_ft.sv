//
// nyuzi_l2_ring_coherence_ft -- the formal top for tasks/nyuzi_l2_ring_coherence.
//
// TASK-AUTHORED. The cut is TWO L1 agents against ONE shared L2, with system
// memory behind it:
//
//   nyuzi_l1_agent#(0)  ---\                                  /--- axi read
//   (L1I, L1D, TLBs,        >-- l2_cache --- l2_axi_bus_if ---<
//    2 load miss queues,    /   arb/tag/     pending_fill_fifo \--- axi write
//    1 store queue,     ---/    read/update  pending_wb_fifo
//    3-stage rsp pipe)
//   nyuzi_l1_agent#(1)  ---/          |                          nyuzi_axi_mem
//                                     `--- l2_response broadcast to BOTH
//
// A transaction crosses FOUR buffers before it comes back:
//
//   1. `l1_load_miss_queue` / `l1_store_queue` in the requesting core, which
//      hold it until the core's own request arbiter dequeues it;
//   2. the `l2_cache_arb_stage` grant, which is a round-robin across the two
//      cores and is pre-empted by anything coming back from memory;
//   3. `pending_fill_fifo` inside `l2_axi_bus_interface`, on a miss -- the
//      request leaves the L2 pipeline entirely, waits for an AXI burst, and is
//      RE-INJECTED at the arb stage, out of order with respect to everything
//      the other core did meanwhile;
//   4. the three-stage response pipeline inside each `l1_l2_interface`, which
//      snoops the L1D tags a cycle before it updates them.
//
// so nothing observable at the response boundary is a local fact about any one
// block. That is the whole reason for this package.
//
// Everything the absent instruction pipeline would drive is an unconstrained
// input, per core. There are no assumptions here and none in the diag.
//
`include "defines.svh"

import defines::*;

module nyuzi_l2_ring_coherence_ft(
    input                               clk,
    input                               reset,

    // --- free stimulus, per core: the instruction pipeline this cut omits ---
    input local_thread_bitmap_t         ts_fetch_en[`NUM_CORES],
    input scalar_t                      wb_rollback_pc[`NUM_CORES],
    input logic                         wb_rollback_en[`NUM_CORES],
    input local_thread_idx_t            wb_rollback_thread_idx[`NUM_CORES],
    input pipeline_sel_t                wb_rollback_pipeline[`NUM_CORES],
    input logic                         cr_mmu_en[`NUM_CORES][`THREADS_PER_CORE],
    input logic                         cr_supervisor_en[`NUM_CORES][`THREADS_PER_CORE],
    input logic[ASID_WIDTH - 1:0]       cr_current_asid[`NUM_CORES][`THREADS_PER_CORE],
    input logic                         ocd_halt[`NUM_CORES],
    input local_thread_idx_t            ocd_thread[`NUM_CORES],
    input logic                         core_selected_debug[`NUM_CORES],
    input scalar_t                      ocd_inject_inst[`NUM_CORES],
    input logic                         ocd_inject_en[`NUM_CORES],
    input vector_t                      of_operand1[`NUM_CORES],
    input vector_mask_t                 of_mask_value[`NUM_CORES],
    input vector_t                      of_store_value[`NUM_CORES],
    input logic                         of_instruction_valid[`NUM_CORES],
    input decoded_instruction_t         of_instruction[`NUM_CORES],
    input local_thread_idx_t            of_thread_idx[`NUM_CORES],
    input subcycle_t                    of_subcycle[`NUM_CORES],

    // --- free stimulus: system memory latency and the data it returns ------
    input                               mem_awready_free,
    input                               mem_wready_free,
    input                               mem_arready_free,
    input                               mem_rvalid_free,
    input [`AXI_DATA_WIDTH - 1:0]       mem_rdata_free);

    // ---------------------------------------------------------- L1 <-> L2
    logic[`NUM_CORES - 1:0]             l2i_request_valid;
    l2req_packet_t                      l2i_request[`NUM_CORES];
    logic                               l2_ready[`NUM_CORES];
    logic                               l2_response_valid;
    l2rsp_packet_t                      l2_response;
    logic[L2_PERF_EVENTS - 1:0]         l2_perf_events;

    // ---------------------------------------------------------- L2 <-> mem
    axi4_interface axi_bus();

    cache_line_index_t                  mem_probe_line;
    cache_line_data_t                   mem_probe_data;
    logic                               mem_probe_valid;
    logic                               mem_wr_active;
    logic                               mem_rd_active;
    cache_line_index_t                  mem_wr_line;
    cache_line_index_t                  mem_rd_line;

    genvar core_idx;
    generate
        for (core_idx = 0; core_idx < `NUM_CORES; core_idx++)
        begin : core_gen
            nyuzi_l1_agent #(.CORE_ID(core_idx)) l1_agent(
                .clk(clk),
                .reset(reset),
                .ts_fetch_en(ts_fetch_en[core_idx]),
                .wb_rollback_pc(wb_rollback_pc[core_idx]),
                .wb_rollback_en(wb_rollback_en[core_idx]),
                .wb_rollback_thread_idx(wb_rollback_thread_idx[core_idx]),
                .wb_rollback_pipeline(wb_rollback_pipeline[core_idx]),
                .cr_mmu_en(cr_mmu_en[core_idx]),
                .cr_supervisor_en(cr_supervisor_en[core_idx]),
                .cr_current_asid(cr_current_asid[core_idx]),
                .ocd_halt(ocd_halt[core_idx]),
                .ocd_thread(ocd_thread[core_idx]),
                .core_selected_debug(core_selected_debug[core_idx]),
                .ocd_inject_inst(ocd_inject_inst[core_idx]),
                .ocd_inject_en(ocd_inject_en[core_idx]),
                .of_operand1(of_operand1[core_idx]),
                .of_mask_value(of_mask_value[core_idx]),
                .of_store_value(of_store_value[core_idx]),
                .of_instruction_valid(of_instruction_valid[core_idx]),
                .of_instruction(of_instruction[core_idx]),
                .of_thread_idx(of_thread_idx[core_idx]),
                .of_subcycle(of_subcycle[core_idx]),
                .l2_ready(l2_ready[core_idx]),
                .l2_response_valid(l2_response_valid),
                .l2_response(l2_response),
                .l2i_request_valid(l2i_request_valid[core_idx]),
                .l2i_request(l2i_request[core_idx]));
        end
    endgenerate

    l2_cache l2_cache(
        .clk(clk),
        .reset(reset),
        .l2i_request_valid(l2i_request_valid),
        .l2i_request(l2i_request),
        .l2_ready(l2_ready),
        .l2_response_valid(l2_response_valid),
        .l2_response(l2_response),
        .axi_bus(axi_bus),
        .l2_perf_events(l2_perf_events));

    nyuzi_axi_mem u_mem(
        .clk(clk),
        .reset(reset),
        .mem_awready_free(mem_awready_free),
        .mem_wready_free(mem_wready_free),
        .mem_arready_free(mem_arready_free),
        .mem_rvalid_free(mem_rvalid_free),
        .mem_rdata_free(mem_rdata_free),
        .axi_bus(axi_bus),
        .mem_probe_line(mem_probe_line),
        .mem_probe_data(mem_probe_data),
        .mem_probe_valid(mem_probe_valid),
        .mem_wr_active(mem_wr_active),
        .mem_rd_active(mem_rd_active),
        .mem_wr_line(mem_wr_line),
        .mem_rd_line(mem_rd_line));
endmodule
