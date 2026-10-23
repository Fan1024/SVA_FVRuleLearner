//
// nyuzi_axi_mem -- the system memory behind the L2.
//
// TASK-AUTHORED. Nyuzi's own testbench answers the L2's AXI master with a
// behavioural SDRAM model that is not part of `hardware/core`, so this cut
// needs a responder of its own.
//
// It is deliberately the WEAKEST responder that is still AXI-legal:
//
//   * every ready/valid is gated by an unconstrained input, so the memory may
//     stall the address phase, the write beats and the read beats for any
//     number of cycles. Bounded-response and deadlock targets have to survive
//     that, which is the point.
//   * read data is unconstrained EXCEPT on one line. `probe_line` is a
//     register with no driver but itself: under any reset scheme it keeps its
//     arbitrary initial value forever, which is the standard way to get a
//     symbolic constant without writing an assumption. For that one line the
//     model is a real memory -- the beats of a write burst are stored and
//     replayed on a read burst -- so a line can be written back by the L2 and
//     read in again, and the round trip is checkable.
//
// Beat-to-lane mapping. The L2 master is big-endian over the burst:
//   write: `m_wdata <= writeback_lanes[~burst_offset_nxt]`, and
//          `writeback_lanes[i] = writeback_data[i*W +: W]`
//   read:  `fill_buffer[burst_offset_ff] <= s_rdata`, and
//          `l2bi_data_from_memory[i*W +: W] = fill_buffer[BURST_BEATS-i-1]`
// so beat n carries line lane (BURST_BEATS - 1 - n) in BOTH directions. This
// model stores and replays at that lane, which is what makes the round trip
// the identity and lets T_DATA_* say something.
//
`include "defines.svh"

import defines::*;

module nyuzi_axi_mem(
    input                               clk,
    input                               reset,

    // Unconstrained throttles. These are top-level inputs, not registers, so
    // the memory's latency profile is whatever the proof needs it to be.
    input                               mem_awready_free,
    input                               mem_wready_free,
    input                               mem_arready_free,
    input                               mem_rvalid_free,
    input [`AXI_DATA_WIDTH - 1:0]       mem_rdata_free,

    axi4_interface.slave                axi_bus,

    // Observation ports for the checker. Not part of AXI.
    output cache_line_index_t           mem_probe_line,
    output cache_line_data_t            mem_probe_data,
    output logic                        mem_probe_valid,
    output logic                        mem_wr_active,
    output logic                        mem_rd_active,
    output cache_line_index_t           mem_wr_line,
    output cache_line_index_t           mem_rd_line);

    localparam BURST_BEATS = CACHE_LINE_BITS / `AXI_DATA_WIDTH;
    localparam BEAT_IDX_WIDTH = $clog2(BURST_BEATS);

    logic[BEAT_IDX_WIDTH - 1:0] w_beat;
    logic[BEAT_IDX_WIDTH - 1:0] r_beat;
    logic[31:0] w_lane_base;
    logic[31:0] r_lane_base;
    logic b_pending;
    logic w_accept;
    logic r_accept;

    // The symbolic constant. No reset branch and no other driver: it holds
    // whatever value it started with, for the whole trace.
    cache_line_index_t probe_line;
    always_ff @(posedge clk)
        probe_line <= probe_line;

    assign mem_probe_line = probe_line;

    // Lane the current beat maps to (big-endian over the burst, see header).
    assign w_lane_base = (32'(BURST_BEATS) - 32'd1 - 32'(w_beat)) * `AXI_DATA_WIDTH;
    assign r_lane_base = (32'(BURST_BEATS) - 32'd1 - 32'(r_beat)) * `AXI_DATA_WIDTH;

    assign w_accept = axi_bus.m_wvalid && axi_bus.s_wready;
    assign r_accept = axi_bus.s_rvalid && axi_bus.m_rready;

    // ------------------------------------------------------------- write
    assign axi_bus.s_awready = mem_awready_free;
    assign axi_bus.s_wready = mem_wready_free;
    assign axi_bus.s_bvalid = b_pending;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            w_beat <= '0;
            b_pending <= '0;
            mem_wr_line <= '0;
            mem_wr_active <= '0;
        end
        else
        begin
            if (axi_bus.m_awvalid && axi_bus.s_awready)
            begin
                mem_wr_line <= axi_bus.m_awaddr[31:CACHE_LINE_OFFSET_WIDTH];
                mem_wr_active <= 1'b1;
                w_beat <= '0;
            end

            if (w_accept)
            begin
                w_beat <= w_beat + BEAT_IDX_WIDTH'(1);
                if (axi_bus.m_wlast)
                begin
                    w_beat <= '0;
                    b_pending <= 1'b1;
                    mem_wr_active <= 1'b0;
                end
            end

            if (b_pending && axi_bus.m_bready)
                b_pending <= 1'b0;
        end
    end

    // The one modelled line.
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            mem_probe_valid <= '0;
        else if (w_accept && mem_wr_line == probe_line)
        begin
            mem_probe_data[w_lane_base+:`AXI_DATA_WIDTH] <= axi_bus.m_wdata;
            if (axi_bus.m_wlast)
                mem_probe_valid <= 1'b1;
        end
    end

    // -------------------------------------------------------------- read
    assign axi_bus.s_arready = !mem_rd_active && mem_arready_free;
    assign axi_bus.s_rvalid = mem_rd_active && mem_rvalid_free;
    assign axi_bus.s_rdata = (mem_rd_line == probe_line && mem_probe_valid)
        ? mem_probe_data[r_lane_base+:`AXI_DATA_WIDTH]
        : mem_rdata_free;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            mem_rd_active <= '0;
            r_beat <= '0;
            mem_rd_line <= '0;
        end
        else if (!mem_rd_active)
        begin
            if (axi_bus.m_arvalid && axi_bus.s_arready)
            begin
                mem_rd_active <= 1'b1;
                r_beat <= '0;
                mem_rd_line <= axi_bus.m_araddr[31:CACHE_LINE_OFFSET_WIDTH];
            end
        end
        else if (r_accept)
        begin
            r_beat <= r_beat + BEAT_IDX_WIDTH'(1);
            if (r_beat == BEAT_IDX_WIDTH'(BURST_BEATS - 1))
                mem_rd_active <= 1'b0;
        end
    end
endmodule
