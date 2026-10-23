//
// Reachability covers for tasks/nyuzi_l2_ring_coherence.
//
// NOT targets. One per category the target file uses, showing that the
// scenario each target constrains is reachable -- a target whose scenario is
// unreachable is vacuous and the phase-1 screen drops it. `COVER_DEPTH` is what
// reads these.
//
// They are deliberately stated on the same signals the targets are stated on,
// so a cover that will not hit says the target above it is talking about
// nothing.
//
`include "defines.svh"

import defines::*;

`define NYZC nyuzi_l2_ring_coherence_ft

module nyuzi_l2_covers(input clk, input reset);

    localparam int NCORE = `NUM_CORES;
    localparam int BURST_BEATS = CACHE_LINE_BITS / `AXI_DATA_WIDTH;

    logic[NCORE - 1:0] adm;
    logic[NCORE - 1:0] rqv;

    always_comb
        for (int i = 0; i < NCORE; i++)
        begin
            rqv[i] = `NYZC.l2i_request_valid[i];
            adm[i] = `NYZC.l2i_request_valid[i] && `NYZC.l2_ready[i];
        end

    wire rsp_v      = `NYZC.l2_response_valid;
    wire enq_fill   = `NYZC.l2_cache.l2_axi_bus_interface.enqueue_fill_request;
    wire enq_wb     = `NYZC.l2_cache.l2_axi_bus_interface.enqueue_writeback_request;
    wire deq_fill   = `NYZC.l2_cache.l2_axi_bus_interface.fill_dequeue_en;
    wire wb_done    = `NYZC.l2_cache.l2_axi_bus_interface.writeback_complete;
    wire bi_stall   = `NYZC.l2_cache.l2_axi_bus_interface.l2bi_stall;
    wire[3:0] fill_cnt = `NYZC.l2_cache.l2_axi_bus_interface.pending_fill_fifo.count;
    wire l2r_valid  = `NYZC.l2_cache.l2_cache_read_stage.l2r_request_valid;
    wire l2r_hit    = `NYZC.l2_cache.l2_cache_read_stage.l2r_cache_hit;
    wire l2r_fill   = `NYZC.l2_cache.l2_cache_read_stage.l2r_l2_fill;

    logic[NCORE - 1:0] snoop_any;
    genvar gc;
    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : cov_core
            assign snoop_any[gc] =
                `NYZC.core_gen[gc].l1_agent.l1_l2_interface.response_stage2_valid
                && (|`NYZC.core_gen[gc].l1_agent.l1_l2_interface.snoop_hit_way_oh);
        end
    endgenerate

    // request-response: a load is admitted and later acknowledged.
    C_LOAD_ADMITTED_THEN_ACKED: cover property (@(posedge clk) disable iff (reset)
        (|adm) ##[1:$] (rsp_v && `NYZC.l2_response.packet_type == L2RSP_LOAD_ACK));

    // uniqueness: two different cores admitted in consecutive cycles.
    C_BOTH_CORES_ADMITTED: cover property (@(posedge clk) disable iff (reset)
        adm[0] ##[1:8] adm[1]);

    // mutual exclusion: both cores asking at once, so the arbiter must choose.
    C_ARB_CONTENTION: cover property (@(posedge clk) disable iff (reset)
        rqv[0] && rqv[1]);

    // occupancy: more than one miss waiting on memory at the same time.
    C_FILL_FIFO_BACKLOG: cover property (@(posedge clk) disable iff (reset)
        fill_cnt >= 4'd2);

    // conservation / bounded response: the full memory round trip.
    C_FILL_ROUNDTRIP: cover property (@(posedge clk) disable iff (reset)
        enq_fill ##[1:$] deq_fill ##4 rsp_v);

    // protocol: a complete AXI write burst.
    C_WRITE_BURST_COMPLETES: cover property (@(posedge clk) disable iff (reset)
        (`NYZC.axi_bus.m_awvalid && `NYZC.axi_bus.s_awready)
        ##[1:$] (`NYZC.axi_bus.m_wvalid && `NYZC.axi_bus.s_wready && `NYZC.axi_bus.m_wlast));

    // protocol: back pressure actually happens.
    C_L2_STALLS_THE_CORES: cover property (@(posedge clk) disable iff (reset) bi_stall);

    // data integrity: the probed line is written to memory and then read back.
    C_PROBE_LINE_WRITTEN_THEN_READ: cover property (@(posedge clk) disable iff (reset)
        (wb_done && `NYZC.mem_wr_line == `NYZC.mem_probe_line)
        ##[1:$] (deq_fill && `NYZC.mem_rd_line == `NYZC.mem_probe_line));

    // data integrity: a store that hits and is merged into the line.
    C_STORE_HIT_MERGED: cover property (@(posedge clk) disable iff (reset)
        l2r_valid && l2r_hit
        && `NYZC.l2_cache.l2_cache_read_stage.l2r_request.packet_type == L2REQ_STORE);

    // ordering: an eviction writeback and a fill queued at the same time, which
    // is where the two buffers interleave.
    C_WRITEBACK_AND_FILL_TOGETHER: cover property (@(posedge clk) disable iff (reset)
        enq_wb && enq_fill);

    // coherence: a d-cache invalidate reaches a core that holds the line.
    C_DINVALIDATE_SNOOP_HIT: cover property (@(posedge clk) disable iff (reset)
        (|snoop_any)
        && `NYZC.core_gen[0].l1_agent.l1_l2_interface.response_stage2.packet_type
           == L2RSP_DINVALIDATE_ACK);

    // coherence: an i-cache invalidate broadcast.
    C_IINVALIDATE_BROADCAST: cover property (@(posedge clk) disable iff (reset)
        rsp_v && `NYZC.l2_response.packet_type == L2RSP_IINVALIDATE_ACK);

    // coherence: a store ack that another core snoop-hits (write update).
    C_STORE_ACK_SNOOP_HIT: cover property (@(posedge clk) disable iff (reset)
        snoop_any[1]
        && `NYZC.core_gen[1].l1_agent.l1_l2_interface.response_stage2.packet_type
           == L2RSP_STORE_ACK
        && `NYZC.core_gen[1].l1_agent.l1_l2_interface.response_stage2.core != 4'd1);

    // fairness: a core asks on an accepting cycle and is not granted.
    C_CORE0_PASSED_OVER: cover property (@(posedge clk) disable iff (reset)
        rqv[0] && !`NYZC.l2_ready[0]
        && `NYZC.l2_cache.l2_cache_arb_stage.can_accept_request);

    // deadlock: the memory answers every cycle and there is work in flight.
    C_MEMORY_GRANTING_WITH_WORK: cover property (@(posedge clk) disable iff (reset)
        `NYZC.mem_awready_free && `NYZC.mem_wready_free && `NYZC.mem_arready_free
        && `NYZC.mem_rvalid_free && (|rqv));

    // allocator: a flush that goes out to memory and comes back to be answered.
    C_FLUSH_RESTARTED: cover property (@(posedge clk) disable iff (reset)
        `NYZC.l2_cache.l2_axi_bus_interface.restart_flush_request);

    // reset: the design leaves reset and does something.
    C_LEAVES_RESET_AND_REQUESTS: cover property (@(posedge clk)
        reset ##1 !reset ##[1:$] (|rqv));

endmodule

bind nyuzi_l2_ring_coherence_ft nyuzi_l2_covers u_covers(.clk(clk), .reset(reset));

`undef NYZC
