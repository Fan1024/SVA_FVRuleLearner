//
// nyuzi_l1_agent -- ONE core's L1 side of the L1/L2 subsystem.
//
// TASK-AUTHORED. Nyuzi's own `core.sv` wraps these five blocks together with
// the whole instruction pipeline, the floating point units, the scoreboard and
// the I/O queue. None of that is in this cut, so this file is the same wrapper
// with only the memory-side blocks in it:
//
//     ifetch_tag_stage   L1I tags + ITLB + per-thread fetch arbitration
//     ifetch_data_stage  L1I data, drives ifd_cache_miss
//     dcache_tag_stage   L1D tags + DTLB + the SNOOP port the L2 broadcast uses
//     dcache_data_stage  L1D data, drives dd_cache_miss / dd_store_en
//     l1_l2_interface    the two load miss queues, the store queue, the
//                        request arbiter and the three-stage response pipeline
//
// The pipeline-facing inputs (`of_*`, `cr_*`, `wb_*`, `ts_*`, `ocd_*`) are
// unconstrained. That is deliberate: an arbitrary instruction stream is a
// STRONGER environment for the L1/L2 protocol than a real decoder, and it is
// what makes the miss queues and the store queue fill.
//
// `.*` is used exactly as upstream `core.sv` uses it, and every signal it has
// to resolve is declared below.
//
`include "defines.svh"

import defines::*;

module nyuzi_l1_agent
    #(parameter CORE_ID = 0)

    (input                                        clk,
    input                                         reset,

    // Free stimulus: the instruction pipeline, the control registers and
    // the on-chip debugger are outside this cut, so everything they would
    // drive is an unconstrained input of the formal top.
    input local_thread_bitmap_t ts_fetch_en,
    input scalar_t wb_rollback_pc,
    input logic wb_rollback_en,
    input local_thread_idx_t wb_rollback_thread_idx,
    input pipeline_sel_t wb_rollback_pipeline,
    input logic cr_mmu_en[`THREADS_PER_CORE],
    input logic cr_supervisor_en[`THREADS_PER_CORE],
    input logic[ASID_WIDTH - 1:0] cr_current_asid[`THREADS_PER_CORE],
    input logic ocd_halt,
    input local_thread_idx_t ocd_thread,
    input logic core_selected_debug,
    input scalar_t ocd_inject_inst,
    input logic ocd_inject_en,
    input vector_t of_operand1,
    input vector_mask_t of_mask_value,
    input vector_t of_store_value,
    input logic of_instruction_valid,
    input decoded_instruction_t of_instruction,
    input local_thread_idx_t of_thread_idx,
    input subcycle_t of_subcycle,

    // From l2_cache (the shared response broadcast and the arbiter grant)
    input logic l2_ready,
    input logic l2_response_valid,
    input l2rsp_packet_t l2_response,

    // To l2_cache
    output logic l2i_request_valid,
    output l2req_packet_t l2i_request);

    // Everything the five blocks exchange with each other. Declared here so
    // the `.*` connections below resolve; the names and types are the upstream
    // port names and types, unchanged.

    logic ifd_update_lru_en;
    l1i_way_idx_t ifd_update_lru_way;
    logic ifd_cache_miss;
    logic ifd_near_miss;
    local_thread_idx_t ifd_cache_miss_thread_idx;
    logic ift_instruction_requested;
    l1i_addr_t ift_pc_paddr;
    scalar_t ift_pc_vaddr;
    local_thread_idx_t ift_thread_idx;
    logic ift_tlb_hit;
    logic ift_tlb_present;
    logic ift_tlb_executable;
    logic ift_tlb_supervisor;
    l1i_tag_t ift_tag[`L1I_WAYS];
    logic ift_valid[`L1I_WAYS];
    logic l2i_icache_lru_fill_en;
    l1i_set_idx_t l2i_icache_lru_fill_set;
    logic[`L1I_WAYS - 1:0] l2i_itag_update_en;
    l1i_set_idx_t l2i_itag_update_set;
    l1i_tag_t l2i_itag_update_tag;
    logic l2i_itag_update_valid;
    local_thread_bitmap_t l2i_icache_wake_bitmap;
    l1i_way_idx_t ift_fill_lru;
    logic dt_invalidate_tlb_en;
    logic dt_invalidate_tlb_all_en;
    logic[ASID_WIDTH - 1:0] dt_update_itlb_asid;
    page_index_t dt_update_itlb_vpage_idx;
    logic dt_update_itlb_en;
    logic dt_update_itlb_supervisor;
    logic dt_update_itlb_global;
    logic dt_update_itlb_present;
    logic dt_update_itlb_executable;
    page_index_t dt_update_itlb_ppage_idx;
    logic l2i_idata_update_en;
    l1i_way_idx_t l2i_idata_update_way;
    l1i_set_idx_t l2i_idata_update_set;
    cache_line_data_t l2i_idata_update_data;
    cache_line_index_t ifd_cache_miss_paddr;
    scalar_t ifd_instruction;
    logic ifd_instruction_valid;
    scalar_t ifd_pc;
    local_thread_idx_t ifd_thread_idx;
    logic ifd_alignment_fault;
    logic ifd_tlb_miss;
    logic ifd_supervisor_fault;
    logic ifd_page_fault;
    logic ifd_executable_fault;
    logic ifd_inst_injected;
    logic ifd_perf_icache_hit;
    logic ifd_perf_icache_miss;
    logic ifd_perf_itlb_miss;
    logic dd_update_lru_en;
    l1d_way_idx_t dd_update_lru_way;
    logic dt_instruction_valid;
    decoded_instruction_t dt_instruction;
    vector_mask_t dt_mask_value;
    local_thread_idx_t dt_thread_idx;
    l1d_addr_t dt_request_vaddr;
    l1d_addr_t dt_request_paddr;
    logic dt_tlb_hit;
    logic dt_tlb_writable;
    vector_t dt_store_value;
    subcycle_t dt_subcycle;
    logic dt_valid[`L1D_WAYS];
    l1d_tag_t dt_tag[`L1D_WAYS];
    logic dt_tlb_supervisor;
    logic dt_tlb_present;
    logic l2i_dcache_lru_fill_en;
    l1d_set_idx_t l2i_dcache_lru_fill_set;
    logic[`L1D_WAYS - 1:0] l2i_dtag_update_en_oh;
    l1d_set_idx_t l2i_dtag_update_set;
    l1d_tag_t l2i_dtag_update_tag;
    logic l2i_dtag_update_valid;
    logic l2i_snoop_en;
    l1d_set_idx_t l2i_snoop_set;
    logic dt_snoop_valid[`L1D_WAYS];
    l1d_tag_t dt_snoop_tag[`L1D_WAYS];
    l1d_way_idx_t dt_fill_lru;
    local_thread_bitmap_t dd_load_sync_pending;
    logic dd_io_write_en;
    logic dd_io_read_en;
    local_thread_idx_t dd_io_thread_idx;
    scalar_t dd_io_addr;
    scalar_t dd_io_write_value;
    logic dd_instruction_valid;
    decoded_instruction_t dd_instruction;
    vector_mask_t dd_lane_mask;
    local_thread_idx_t dd_thread_idx;
    l1d_addr_t dd_request_vaddr;
    subcycle_t dd_subcycle;
    logic dd_rollback_en;
    scalar_t dd_rollback_pc;
    cache_line_data_t dd_load_data;
    logic dd_suspend_thread;
    logic dd_io_access;
    logic dd_trap;
    trap_cause_t dd_trap_cause;
    logic dd_creg_write_en;
    logic dd_creg_read_en;
    control_register_t dd_creg_index;
    scalar_t dd_creg_write_val;
    logic l2i_ddata_update_en;
    l1d_way_idx_t l2i_ddata_update_way;
    l1d_set_idx_t l2i_ddata_update_set;
    cache_line_data_t l2i_ddata_update_data;
    logic dd_cache_miss;
    cache_line_index_t dd_cache_miss_addr;
    local_thread_idx_t dd_cache_miss_thread_idx;
    logic dd_cache_miss_sync;
    logic dd_store_en;
    logic dd_flush_en;
    logic dd_membar_en;
    logic dd_iinvalidate_en;
    logic dd_dinvalidate_en;
    logic[CACHE_LINE_BYTES - 1:0] dd_store_mask;
    cache_line_index_t dd_store_addr;
    cache_line_data_t dd_store_data;
    local_thread_idx_t dd_store_thread_idx;
    logic dd_store_sync;
    cache_line_index_t dd_store_bypass_addr;
    local_thread_idx_t dd_store_bypass_thread_idx;
    logic dd_perf_dcache_hit;
    logic dd_perf_dcache_miss;
    logic dd_perf_dtlb_miss;
    local_thread_bitmap_t sq_store_sync_pending;
    local_thread_bitmap_t l2i_dcache_wake_bitmap;
    logic[CACHE_LINE_BYTES - 1:0] sq_store_bypass_mask;
    logic sq_store_sync_success;
    cache_line_data_t sq_store_bypass_data;
    logic sq_rollback_en;
    logic l2i_perf_store;

    ifetch_tag_stage ifetch_tag_stage(.*);
    ifetch_data_stage ifetch_data_stage(.*);
    dcache_tag_stage dcache_tag_stage(.*);
    dcache_data_stage dcache_data_stage(.*);
    l1_l2_interface #(.CORE_ID(CORE_ID)) l1_l2_interface(.*);
endmodule
