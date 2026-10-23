//
// Phase-1 candidate TARGET assertions for tasks/nyuzi_l2_ring_coherence.
//
// The subsystem is two Nyuzi L1 agents against one shared L2 and system
// memory. A request crosses four buffers before its response comes back:
//
//   the requesting core's l1_load_miss_queue / l1_store_queue
//     -> l2_cache_arb_stage's round-robin grant across the two cores
//        -> l2_cache_tag_stage -> l2_cache_read_stage
//           -> (on a miss) pending_fill_fifo, an AXI burst, and RE-INJECTION
//              at the arb stage, out of order with the other core's traffic
//              -> l2_cache_update_stage
//                 -> the three-stage response pipeline in BOTH cores
//
// so the two observation points these assertions use --
//
//   A  admission:  l2i_request_valid[c] && l2_ready[c]
//   B  response:   l2_response_valid, broadcast to every core
//
// -- are separated by everything above. Nothing stated between A and B is a
// local fact about any one block, which is the point of the package.
//
// The oracle is an independent outstanding-request table keyed on
// (core, id, class). It is NOT a copy of any RTL structure: the design has no
// such table anywhere. `id` is `l1_miss_entry_idx_t`, which is the requesting
// THREAD index, and the same id is used by three independent L1 queues at
// once, so `class` is needed to make the key unique:
//
//   class 0  d-cache load   (L2REQ_LOAD / L2REQ_LOAD_SYNC, CT_DCACHE)
//   class 1  i-cache load   (L2REQ_LOAD, CT_ICACHE)
//   class 2  store or cache-control (STORE, STORE_SYNC, FLUSH, I/DINVALIDATE)
//
// and the classes are exactly how `l1_l2_interface` demultiplexes a response
// back onto `dcache_l2_response_valid` / `icache_l2_response_valid` /
// `storebuf_l2_response_valid`.
//
// Several targets are focussed on ONE symbolic slot, byte, lane or line.
// Those are registers with no driver but themselves: under any reset scheme
// they hold their arbitrary initial value for the whole trace, which is a
// symbolic constant obtained WITHOUT writing an assumption. The diag declares
// no assumptions and neither does this file.
//
// Every counter bound below is stated as an inequality that can be argued from
// the RTL, and the argument is in the target's oracle comment.
//
`include "defines.svh"

import defines::*;

`define NYZ nyuzi_l2_ring_coherence_ft

module nyuzi_l2_targets(input clk, input reset);

    localparam int NCORE = `NUM_CORES;                  // 2
    localparam int NID   = `THREADS_PER_CORE;           // 4
    localparam int NCLS  = 3;
    localparam int CIDW  = $clog2(`NUM_CORES);          // 1
    localparam int IDW   = $clog2(`THREADS_PER_CORE);   // 2
    localparam int BURST_BEATS = CACHE_LINE_BITS / `AXI_DATA_WIDTH;  // 4
    localparam int BEATW = $clog2(BURST_BEATS);         // 2
    localparam int FILL_FIFO_SIZE = 8;                  // l2_axi_bus_interface
    localparam int BYTEW = $clog2(CACHE_LINE_BYTES);    // 6

    // ------------------------------------------------------------ classes
    function automatic logic[1:0] req_class(input l2req_packet_t r);
        if (r.cache_type == CT_ICACHE)
            return 2'd1;
        else if (r.packet_type == L2REQ_LOAD || r.packet_type == L2REQ_LOAD_SYNC)
            return 2'd0;
        else
            return 2'd2;
    endfunction

    function automatic logic[1:0] rsp_class(input l2rsp_packet_t r);
        if (r.cache_type == CT_ICACHE)
            return 2'd1;
        else if (r.packet_type == L2RSP_LOAD_ACK)
            return 2'd0;
        else
            return 2'd2;
    endfunction

    // ------------------------------------------------- boundary shorthands
    logic[NCORE - 1:0] adm;                 // A: request accepted by the L2
    logic[NCORE - 1:0] rdy;
    logic[NCORE - 1:0] rqv;

    always_comb
    begin
        for (int i = 0; i < NCORE; i++)
        begin
            rqv[i] = `NYZ.l2i_request_valid[i];
            rdy[i] = `NYZ.l2_ready[i];
            adm[i] = `NYZ.l2i_request_valid[i] && `NYZ.l2_ready[i];
        end
    end

    wire                rsp_v      = `NYZ.l2_response_valid;
    wire                rsp_legal  = `NYZ.l2_response.core < core_id_t'(NCORE);
    wire[CIDW - 1:0]    rsp_core   = `NYZ.l2_response.core[CIDW - 1:0];
    wire[IDW - 1:0]     rsp_id     = `NYZ.l2_response.id;
    wire[1:0]           rsp_cls    = rsp_class(`NYZ.l2_response);

    // ---------------------------------------------------- L2 interior taps
    wire arb_can_accept = `NYZ.l2_cache.l2_cache_arb_stage.can_accept_request;
    wire l2a_valid      = `NYZ.l2_cache.l2_cache_arb_stage.l2a_request_valid;
    wire l2t_valid      = `NYZ.l2_cache.l2_cache_tag_stage.l2t_request_valid;
    wire l2r_valid      = `NYZ.l2_cache.l2_cache_read_stage.l2r_request_valid;
    wire l2r_hit        = `NYZ.l2_cache.l2_cache_read_stage.l2r_cache_hit;
    wire l2r_fill       = `NYZ.l2_cache.l2_cache_read_stage.l2r_l2_fill;
    l2req_packet_t    l2r_req  = `NYZ.l2_cache.l2_cache_read_stage.l2r_request;
    cache_line_data_t l2r_data = `NYZ.l2_cache.l2_cache_read_stage.l2r_data;

    wire bi_req_valid   = `NYZ.l2_cache.l2_axi_bus_interface.l2bi_request_valid;
    wire bi_stall       = `NYZ.l2_cache.l2_axi_bus_interface.l2bi_stall;
    wire bi_collided    = `NYZ.l2_cache.l2_axi_bus_interface.l2bi_collided_miss;
    wire enq_fill       = `NYZ.l2_cache.l2_axi_bus_interface.enqueue_fill_request;
    wire enq_wb         = `NYZ.l2_cache.l2_axi_bus_interface.enqueue_writeback_request;
    wire deq_fill       = `NYZ.l2_cache.l2_axi_bus_interface.fill_dequeue_en;
    wire wb_complete    = `NYZ.l2_cache.l2_axi_bus_interface.writeback_complete;
    wire fill_empty     = `NYZ.l2_cache.l2_axi_bus_interface.fill_queue_empty;
    wire wb_empty       = `NYZ.l2_cache.l2_axi_bus_interface.writeback_fifo_empty;
    wire fill_pending   = `NYZ.l2_cache.l2_axi_bus_interface.fill_request_pending;
    wire wbq_pending    = `NYZ.l2_cache.l2_axi_bus_interface.writeback_pending;
    wire fill_full      = `NYZ.l2_cache.l2_axi_bus_interface.pending_fill_fifo.full;
    wire wbq_full       = `NYZ.l2_cache.l2_axi_bus_interface.pending_writeback_fifo.full;
    wire[3:0] fill_cnt  = `NYZ.l2_cache.l2_axi_bus_interface.pending_fill_fifo.count;
    wire[15:0] cam_free = `NYZ.l2_cache.l2_axi_bus_interface.l2_cache_pending_miss_cam.empty_entries;
    l2req_packet_t     lmq_out  = `NYZ.l2_cache.l2_axi_bus_interface.lmq_out_request;
    cache_line_data_t  bi_mem   = `NYZ.l2_cache.l2_axi_bus_interface.l2bi_data_from_memory;
    cache_line_index_t wb_out_a = `NYZ.l2_cache.l2_axi_bus_interface.writeback_address;
    cache_line_index_t wb_in_a  = `NYZ.l2_cache.l2_axi_bus_interface.writeback_fifo_in.address;
    wire[BEATW - 1:0] bo_ff     = `NYZ.l2_cache.l2_axi_bus_interface.burst_offset_ff;
    wire bus_rd_xfer = `NYZ.l2_cache.l2_axi_bus_interface.state_ff
                    == `NYZ.l2_cache.l2_axi_bus_interface.STATE_READ_TRANSFER;

    // ------------------------------------------------------------- AXI tap
    wire w_acc = `NYZ.axi_bus.m_wvalid && `NYZ.axi_bus.s_wready;
    wire r_acc = `NYZ.axi_bus.s_rvalid && `NYZ.axi_bus.m_rready;
    wire ar_acc = `NYZ.axi_bus.m_arvalid && `NYZ.axi_bus.s_arready;
    wire aw_acc = `NYZ.axi_bus.m_awvalid && `NYZ.axi_bus.s_awready;
    wire[BEATW - 1:0] mem_w_beat = `NYZ.u_mem.w_beat;

    // ----------------------------------------- per-core L1 interior taps
    // A generate block, because a hierarchical reference through an instance
    // ARRAY needs an elaboration-time index; a for loop inside always_comb
    // would not compile.
    logic[NCORE - 1:0]                  c_r2_valid;
    l2rsp_packet_t                      c_r2 [NCORE];
    logic[NCORE - 1:0][`L1D_WAYS - 1:0] c_snoop_hit;
    logic[NCORE - 1:0][`L1D_WAYS - 1:0] c_dtag_upd;
    logic[NCORE - 1:0]                  c_ddata_upd;
    logic[NCORE - 1:0][2:0]             c_deq_src;

    genvar gc, gw, gt;
    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : tap_core
            assign c_r2_valid[gc] =
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.response_stage2_valid;
            assign c_r2[gc] =
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.response_stage2;
            assign c_snoop_hit[gc] =
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.snoop_hit_way_oh;
            assign c_dtag_upd[gc] =
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l2i_dtag_update_en_oh;
            assign c_ddata_upd[gc] =
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l2i_ddata_update_en;
            assign c_deq_src[gc] = {
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.dcache_dequeue_ack,
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.icache_dequeue_ack,
                `NYZ.core_gen[gc].l1_agent.l1_l2_interface.storebuf_dequeue_ack};
        end
    endgenerate

    // ==================================================================
    //  Oracle 1 -- the outstanding-request table
    // ==================================================================
    logic os_valid[NCORE][NID][NCLS];
    logic os_any;

    always_comb
    begin
        os_any = 1'b0;
        for (int i = 0; i < NCORE; i++)
            for (int j = 0; j < NID; j++)
                for (int k = 0; k < NCLS; k++)
                    if (os_valid[i][j][k])
                        os_any = 1'b1;
    end

    // Was the response's slot outstanding when the response arrived?
    wire rsp_slot_open = rsp_legal && os_valid[rsp_core][rsp_id][rsp_cls];

    // Was the admitted slot already outstanding? (per core, before the update)
    logic[NCORE - 1:0] adm_collides;
    always_comb
        for (int i = 0; i < NCORE; i++)
            adm_collides[i] = adm[i]
                && os_valid[i][`NYZ.l2i_request[i].id][req_class(`NYZ.l2i_request[i])];

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            for (int i = 0; i < NCORE; i++)
                for (int j = 0; j < NID; j++)
                    for (int k = 0; k < NCLS; k++)
                        os_valid[i][j][k] <= 1'b0;
        end
        else
        begin
            // Clear on the response, then set on the admission: if both name
            // the same slot in one cycle the slot ends up outstanding, which
            // is the truthful answer.
            if (rsp_v && rsp_legal)
                os_valid[rsp_core][rsp_id][rsp_cls] <= 1'b0;

            for (int i = 0; i < NCORE; i++)
                if (adm[i])
                    os_valid[i][`NYZ.l2i_request[i].id][req_class(`NYZ.l2i_request[i])] <= 1'b1;
        end
    end

    // ==================================================================
    //  Oracle 2 -- ONE symbolic slot, followed in detail
    // ==================================================================
    logic[CIDW - 1:0]   f_core;
    logic[IDW - 1:0]    f_id;
    logic[1:0]          f_cls;
    logic[BYTEW - 1:0]  f_byte;
    logic[BEATW - 1:0]  f_lane;

    always_ff @(posedge clk)
    begin
        f_core <= f_core;
        f_id   <= f_id;
        f_cls  <= f_cls;
        f_byte <= f_byte;
        f_lane <= f_lane;
    end

    wire       f_legal = f_cls < 2'd3;
    wire[1:0]  f_cls_c = f_legal ? f_cls : 2'd0;   // clamped, for indexing only

    logic f_adm;
    always_comb
    begin
        f_adm = 1'b0;
        for (int i = 0; i < NCORE; i++)
            if (adm[i] && (CIDW'(i) == f_core)
                && (`NYZ.l2i_request[i].id == f_id)
                && (req_class(`NYZ.l2i_request[i]) == f_cls))
                f_adm = 1'b1;
    end

    l2req_packet_t f_req;
    always_comb
    begin
        f_req = `NYZ.l2i_request[0];
        for (int i = 0; i < NCORE; i++)
            if (CIDW'(i) == f_core)
                f_req = `NYZ.l2i_request[i];
    end

    wire f_rsp = rsp_v && rsp_legal && (rsp_core == f_core) && (rsp_id == f_id)
                 && (rsp_cls == f_cls);

    l2_addr_t            f_addr;
    l2req_packet_type_t  f_type;
    cache_type_t         f_ctype;
    logic[7:0]           f_adm_cnt;
    logic[7:0]           f_rsp_cnt;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            f_addr    <= '0;
            f_type    <= L2REQ_LOAD;
            f_ctype   <= CT_ICACHE;
            f_adm_cnt <= '0;
            f_rsp_cnt <= '0;
        end
        else
        begin
            if (f_adm)
            begin
                f_addr  <= f_req.address;
                f_type  <= f_req.packet_type;
                f_ctype <= f_req.cache_type;
                if (f_adm_cnt != 8'hff)
                    f_adm_cnt <= f_adm_cnt + 8'd1;
            end
            if (f_rsp && f_rsp_cnt != 8'hff)
                f_rsp_cnt <= f_rsp_cnt + 8'd1;
        end
    end

    // The ack the recorded request type must come back as.
    function automatic l2rsp_packet_type_t expected_ack(input l2req_packet_type_t t);
        case (t)
            L2REQ_LOAD, L2REQ_LOAD_SYNC:   return L2RSP_LOAD_ACK;
            L2REQ_STORE, L2REQ_STORE_SYNC: return L2RSP_STORE_ACK;
            L2REQ_FLUSH:                   return L2RSP_FLUSH_ACK;
            L2REQ_IINVALIDATE:             return L2RSP_IINVALIDATE_ACK;
            default:                       return L2RSP_DINVALIDATE_ACK;
        endcase
    endfunction

    // ==================================================================
    //  Oracle 3 -- in-flight accounting at the two boundaries
    // ==================================================================
    logic[7:0] inflight;
    logic[2:0] adm_n;

    always_comb
    begin
        adm_n = '0;
        for (int i = 0; i < NCORE; i++)
            if (adm[i])
                adm_n = adm_n + 3'd1;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            inflight <= '0;
        else
            inflight <= inflight + 8'(adm_n) - 8'(rsp_v ? 1 : 0);
    end

    // ==================================================================
    //  Oracle 4 -- an independent reassembly of the AXI read burst
    // ==================================================================
    cache_line_data_t   rd_shadow;
    logic[BEATW - 1:0]  rd_cnt;
    logic               rd_fresh;      // a whole burst has landed, unconsumed
    logic[31:0]         rd_lane_base;

    assign rd_lane_base = (32'(BURST_BEATS) - 32'd1 - 32'(rd_cnt)) * `AXI_DATA_WIDTH;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            rd_cnt   <= '0;
            rd_fresh <= 1'b0;
        end
        else
        begin
            if (ar_acc)
            begin
                rd_cnt   <= '0;
                rd_fresh <= 1'b0;
            end
            else if (r_acc)
            begin
                rd_shadow[rd_lane_base+:`AXI_DATA_WIDTH] <= `NYZ.axi_bus.s_rdata;
                rd_cnt <= rd_cnt + BEATW'(1);
                if (rd_cnt == BEATW'(BURST_BEATS - 1))
                    rd_fresh <= 1'b1;
            end
            else if (deq_fill)
                rd_fresh <= 1'b0;
        end
    end

    // The same shadow, carried down the four registered stages the fill data
    // travels through: l2bi -> l2a -> l2t -> l2r -> l2_response.
    cache_line_data_t fl_d0, fl_d1, fl_d2, fl_d3;
    logic             fl_v0, fl_v1, fl_v2, fl_v3;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            fl_v0 <= 1'b0;
            fl_v1 <= 1'b0;
            fl_v2 <= 1'b0;
            fl_v3 <= 1'b0;
        end
        else
        begin
            fl_v0 <= deq_fill && rd_fresh && !bi_collided;
            fl_d0 <= rd_shadow;
            fl_v1 <= fl_v0;   fl_d1 <= fl_d0;
            fl_v2 <= fl_v1;   fl_d2 <= fl_d1;
            fl_v3 <= fl_v2;   fl_d3 <= fl_d2;
        end
    end

    // ==================================================================
    //  Oracle 5 -- a shadow queue for the pending-fill FIFO
    // ==================================================================
    localparam int SHW = CIDW + IDW + 2;
    logic[SHW - 1:0] shq[FILL_FIFO_SIZE];
    logic[2:0]       sh_wr;
    logic[2:0]       sh_rd;
    logic[3:0]       sh_cnt;

    wire[SHW - 1:0] sh_push_val = {`NYZ.l2_cache.l2_cache_read_stage.l2r_request.core[CIDW - 1:0],
                                   `NYZ.l2_cache.l2_cache_read_stage.l2r_request.id,
                                   req_class(`NYZ.l2_cache.l2_cache_read_stage.l2r_request)};
    wire[SHW - 1:0] sh_pop_exp  = {lmq_out.core[CIDW - 1:0], lmq_out.id, req_class(lmq_out)};

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            sh_wr  <= '0;
            sh_rd  <= '0;
            sh_cnt <= '0;
        end
        else
        begin
            if (enq_fill && sh_cnt != 4'(FILL_FIFO_SIZE))
            begin
                shq[sh_wr] <= sh_push_val;
                sh_wr <= sh_wr + 3'd1;
            end

            if (deq_fill && sh_cnt != 4'd0)
                sh_rd <= sh_rd + 3'd1;

            if (enq_fill && !deq_fill && sh_cnt != 4'(FILL_FIFO_SIZE))
                sh_cnt <= sh_cnt + 4'd1;
            else if (deq_fill && !enq_fill && sh_cnt != 4'd0)
                sh_cnt <= sh_cnt - 4'd1;
        end
    end

    // ==================================================================
    //  Oracle 6 -- one probed writeback beat
    // ==================================================================
    logic[`AXI_DATA_WIDTH - 1:0] wb_word;
    logic[3:0]                   wb_probe_cnt;
    logic                        wb_word_ok;
    logic[31:0]                  wb_word_base;

    assign wb_word_base = 32'(f_lane) * `AXI_DATA_WIDTH;

    wire wb_in_is_probe  = wb_in_a == `NYZ.mem_probe_line;
    wire wb_out_is_probe = wb_out_a == `NYZ.mem_probe_line;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            wb_probe_cnt <= '0;
            wb_word_ok   <= 1'b0;
        end
        else
        begin
            if (enq_wb && wb_in_is_probe)
            begin
                wb_probe_cnt <= wb_probe_cnt + 4'd1;
                if (wb_probe_cnt == 4'd0)
                begin
                    // NOT a variable-base part-select. Slang accepts
                    // `l2r_data[wb_word_base+:`AXI_DATA_WIDTH]`;
                    // Verific rejects it as VERI-1103 "range index
                    // value is not constant" on a hierarchical
                    // reference, which killed the first screen. A
                    // shift-and-truncate is the same value.
                    wb_word    <= `AXI_DATA_WIDTH'(l2r_data >> wb_word_base);
                    wb_word_ok <= 1'b1;
                end
                else
                    wb_word_ok <= 1'b0;
            end

            if (wb_complete && wb_out_is_probe)
            begin
                wb_probe_cnt <= wb_probe_cnt - 4'd1;
                wb_word_ok   <= 1'b0;
            end
        end
    end

    // ==================================================================
    //  Oracle 7 -- arbitration wait, and a global progress counter
    // ==================================================================
    logic[3:0] fair_cnt[NCORE];

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            for (int i = 0; i < NCORE; i++)
                fair_cnt[i] <= '0;
        end
        else
        begin
            for (int i = 0; i < NCORE; i++)
            begin
                if (rdy[i])
                    fair_cnt[i] <= '0;
                else if (rqv[i] && arb_can_accept && fair_cnt[i] != 4'hf)
                    fair_cnt[i] <= fair_cnt[i] + 4'd1;
            end
        end
    end

    // "The memory is answering." With every throttle high the slave accepts an
    // address every cycle and sources a beat every cycle, so the bus interface
    // cannot be waiting on anything outside the design.
    wire mem_granting = `NYZ.mem_awready_free && `NYZ.mem_wready_free
                     && `NYZ.mem_arready_free && `NYZ.mem_rvalid_free;

    wire progress_event = rsp_v || (|adm) || enq_fill || enq_wb || deq_fill
                       || wb_complete || ar_acc || aw_acc || w_acc || r_acc;

    logic[7:0] stall_cnt;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            stall_cnt <= '0;
        else if (!mem_granting || !os_any || progress_event)
            stall_cnt <= '0;
        else if (stall_cnt != 8'hff)
            stall_cnt <= stall_cnt + 8'd1;
    end

    // ==================================================================
    //  Oracle 8 -- the invalidate broadcast, followed into both L1s
    // ==================================================================
    // A response at T is in `response_stage2` at T+1, the L1 tag write happens
    // on the T+1 -> T+2 edge, so the earliest cycle at which the tag state has
    // settled is T+2. The next response can only land at T+1 at the earliest
    // and would not change a tag before T+3, so T+2 is a clean sample point.
    logic       dinv_p1, dinv_p2;
    logic       iinv_p1, iinv_p2;
    l1d_set_idx_t dinv_set_1, dinv_set_2;
    l1d_tag_t     dinv_tag_1, dinv_tag_2;
    l1i_set_idx_t iinv_set_1, iinv_set_2;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            dinv_p1 <= 1'b0;
            dinv_p2 <= 1'b0;
            iinv_p1 <= 1'b0;
            iinv_p2 <= 1'b0;
        end
        else
        begin
            dinv_p1 <= rsp_v && `NYZ.l2_response.packet_type == L2RSP_DINVALIDATE_ACK;
            dinv_p2 <= dinv_p1;
            iinv_p1 <= rsp_v && `NYZ.l2_response.packet_type == L2RSP_IINVALIDATE_ACK;
            iinv_p2 <= iinv_p1;

            dinv_set_1 <= `NYZ.l2_response.address[$clog2(`L1D_SETS) - 1:0];
            dinv_set_2 <= dinv_set_1;
            dinv_tag_1 <= `NYZ.l2_response.address[$bits(l2_addr_t) - 1-:DCACHE_TAG_BITS];
            dinv_tag_2 <= dinv_tag_1;
            iinv_set_1 <= `NYZ.l2_response.address[$clog2(`L1I_SETS) - 1:0];
            iinv_set_2 <= iinv_set_1;
        end
    end

    logic[NCORE - 1:0][`L1D_WAYS - 1:0] dinv_live;
    logic[NCORE - 1:0][`L1I_WAYS - 1:0] iinv_live;

    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : coh_core
            for (gw = 0; gw < `L1D_WAYS; gw++)
            begin : coh_dway
                assign dinv_live[gc][gw] =
                    `NYZ.core_gen[gc].l1_agent.dcache_tag_stage.way_tag_gen[gw].line_valid[dinv_set_2]
                    && (`NYZ.core_gen[gc].l1_agent.dcache_tag_stage.way_tag_gen[gw].sram_tags.data[dinv_set_2]
                        == dinv_tag_2);
            end
            for (gw = 0; gw < `L1I_WAYS; gw++)
            begin : coh_iway
                assign iinv_live[gc][gw] =
                    `NYZ.core_gen[gc].l1_agent.ifetch_tag_stage.way_tag_gen[gw].line_valid[iinv_set_2];
            end
        end
    endgenerate

    // ==================================================================
    //  Oracle 9 -- store-merge probe on one symbolic byte lane
    // ==================================================================
    logic       sm_v;
    logic[7:0]  sm_byte;
    logic[31:0] sm_base;

    assign sm_base = 32'(f_byte) * 32'd8;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            sm_v <= 1'b0;
        else
        begin
            sm_v <= l2r_valid && (l2r_req.packet_type == L2REQ_STORE)
                    && (l2r_hit || l2r_fill) && l2r_req.store_mask[f_byte];
            sm_byte <= l2r_req.data[sm_base+:8];
        end
    end

    // ==================================================================
    //  Oracle 10 -- L1 miss-queue allocation
    // ==================================================================
    logic[NCORE - 1:0][NID - 1:0] mq_double_alloc;

    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : alloc_core
            for (gt = 0; gt < NID; gt++)
            begin : alloc_entry
                assign mq_double_alloc[gc][gt] =
                    `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l1_load_miss_queue_dcache.cache_miss
                    && `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l1_load_miss_queue_dcache.miss_thread_oh[gt]
                    && `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l1_load_miss_queue_dcache.request_unique
                    && `NYZ.core_gen[gc].l1_agent.l1_l2_interface.l1_load_miss_queue_dcache.pending_entries[gt].valid;
            end
        end
    endgenerate

    // ==================================================================
    //  Combinational verdicts used by more than one assertion
    // ==================================================================
    logic snoop_onehot_ok;
    logic dtag_onehot_ok;
    logic deq_src_onehot_ok;
    logic store_ack_update_ok;

    always_comb
    begin
        snoop_onehot_ok   = 1'b1;
        dtag_onehot_ok    = 1'b1;
        deq_src_onehot_ok = 1'b1;
        store_ack_update_ok = 1'b1;
        for (int i = 0; i < NCORE; i++)
        begin
            if (c_r2_valid[i] && c_r2[i].cache_type == CT_DCACHE
                && !$onehot0(c_snoop_hit[i]))
                snoop_onehot_ok = 1'b0;
            if (!$onehot0(c_dtag_upd[i]))
                dtag_onehot_ok = 1'b0;
            if (!$onehot0(c_deq_src[i]))
                deq_src_onehot_ok = 1'b0;
        end
    end

    // The write-update leg of the protocol, one cycle later.
    logic[NCORE - 1:0] store_ack_hit_q;
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            store_ack_hit_q <= '0;
        else
            for (int i = 0; i < NCORE; i++)
                store_ack_hit_q[i] <= c_r2_valid[i]
                    && (c_r2[i].packet_type == L2RSP_STORE_ACK)
                    && (|c_snoop_hit[i]);
    end

    logic store_ack_wrote_ok;
    always_comb
    begin
        store_ack_wrote_ok = 1'b1;
        for (int i = 0; i < NCORE; i++)
            if (store_ack_hit_q[i] && !c_ddata_upd[i])
                store_ack_wrote_ok = 1'b0;
    end

    // ==================================================================
    //                        TARGET ASSERTIONS
    // ==================================================================

    // ---- request-response correspondence -----------------------------
    // ORACLE: every response the L2 broadcasts carries the (core, id,
    // cache_type, packet_type) of the packet that was accepted at the arb
    // stage. The identity survives the arb register, the tag stage, the read
    // stage, a possible detour through pending_fill_fifo and an AXI burst, and
    // the update stage, none of which is allowed to invent or relabel one.
    // Nothing in one block can establish this: the table is filled at A and
    // read at B.
    T_REQRSP_NO_UNSOLICITED_RESPONSE: assert property (@(posedge clk)
        disable iff (reset) rsp_v |-> rsp_slot_open);

    // ORACLE: the response's address field is the request's address field,
    // carried unchanged. `l2_cache_update_stage` assigns
    // `l2_response.address <= l2r_request.address`, and every stage above it
    // copies the packet forward, INCLUDING the round trip through the fill
    // FIFO, where `l2bi_request` is the FIFO's stored copy of the same packet.
    T_REQRSP_RESPONSE_ADDRESS_MATCHES: assert property (@(posedge clk)
        disable iff (reset) (f_rsp && f_legal) |-> `NYZ.l2_response.address == f_addr);

    // ORACLE: `l2_cache_update_stage`'s response_type case is a total function
    // of the request's packet_type, and the packet type is carried unchanged,
    // so the ack a slot receives is the ack its recorded request type maps to.
    T_REQRSP_RESPONSE_TYPE_MATCHES: assert property (@(posedge clk)
        disable iff (reset)
        (f_rsp && f_legal) |-> `NYZ.l2_response.packet_type == expected_ack(f_type));

    // ORACLE: `l2_response.cache_type <= l2r_request.cache_type`, unchanged all
    // the way. This is the field `l1_l2_interface` demultiplexes on, so getting
    // it wrong would wake the wrong L1 queue.
    T_REQRSP_RESPONSE_CACHE_TYPE_MATCHES: assert property (@(posedge clk)
        disable iff (reset) (f_rsp && f_legal) |-> `NYZ.l2_response.cache_type == f_ctype);

    // ORACLE: only `ifetch_data_stage`'s miss queue issues CT_ICACHE requests,
    // so a CT_ICACHE response must have an outstanding i-cache-class slot.
    T_REQRSP_ICACHE_RESPONSE_HAS_REQUEST: assert property (@(posedge clk)
        disable iff (reset)
        (rsp_v && rsp_legal && `NYZ.l2_response.cache_type == CT_ICACHE)
            |-> os_valid[rsp_core][rsp_id][1]);

    // ---- uniqueness / no duplication ---------------------------------
    // ORACLE: `l1_load_miss_queue` sets `request_sent` on the cycle it is
    // dequeued and `arbiter_request` requires `!request_sent`; `l1_store_queue`
    // does the same with `send_request`. So one entry cannot be offered to the
    // L2 twice before its response clears it, and the entry index IS the id.
    T_UNIQ_NO_REISSUE_WHILE_OUTSTANDING: assert property (@(posedge clk)
        disable iff (reset) adm_collides == '0);

    // ORACLE: a slot's response clears its L1 queue entry on the same edge, and
    // the shortest path from a re-issue back to a response is admission plus
    // four registered stages, so two responses to one slot cannot be adjacent.
    T_UNIQ_NO_BACK_TO_BACK_SAME_SLOT: assert property (@(posedge clk)
        disable iff (reset) (f_rsp && f_legal) |=> !f_rsp);

    // ORACLE: `l2_axi_bus_interface` is a single-transaction state machine --
    // it leaves STATE_READ_ISSUE_ADDRESS only on s_arready and does not return
    // until STATE_READ_COMPLETE -- so it never has two read bursts open.
    T_UNIQ_AXI_SINGLE_READ_BURST: assert property (@(posedge clk)
        disable iff (reset) !(`NYZ.axi_bus.m_arvalid && `NYZ.mem_rd_active));

    // ---- mutual exclusion / one-hot ----------------------------------
    // ORACLE: `l2_ready[i] = grant_oh[i] && can_accept_request` and grant_oh
    // comes from one `rr_arbiter`, so at most one core may put a packet into
    // the arb register in a cycle. Two would silently drop one.
    T_MUTEX_L2_READY_ONEHOT: assert property (@(posedge clk)
        disable iff (reset) $onehot0(rdy));

    // ORACLE: `l1_l2_interface`'s request block is one if/else-if chain over
    // the d-cache queue, the i-cache queue and the store queue, so exactly one
    // of the three dequeue acks can fire -- there is only one request port.
    T_MUTEX_L1_ONE_DEQUEUE_SOURCE: assert property (@(posedge clk)
        disable iff (reset) deq_src_onehot_ok);

    // ORACLE: `l2i_dtag_update_en_oh = dupdate_way_oh & {dcache_update_en}` and
    // `dupdate_way_oh` comes from `idx_to_oh`, so at most one L1D way is
    // written per cycle. Two would put one line in two ways of a set.
    T_MUTEX_DTAG_UPDATE_ONEHOT: assert property (@(posedge clk)
        disable iff (reset) dtag_onehot_ok);

    // ORACLE: `dcache_tag_stage` guarantees a physical line lives in at most
    // one way of its set, so the snoop comparison can hit at most one way.
    T_MUTEX_SNOOP_HIT_ONEHOT: assert property (@(posedge clk)
        disable iff (reset) snoop_onehot_ok);

    // ---- occupancy and bounds ----------------------------------------
    // ORACLE: `l2bi_stall` is raised at ALMOST_FULL_THRESHOLD = SIZE - 4 = 4
    // and clears `can_accept_request` in the arb stage. Once it is up, only the
    // packets already in the three stages below the arb register can still
    // enqueue, which is at most three more, so the fill FIFO tops out at 7 of
    // 8. This is the reason the threshold is SIZE minus the pipeline depth, and
    // checking it needs the arb stage, the three pipe stages and the FIFO at
    // once.
    T_OCC_FILL_FIFO_NEVER_FULL: assert property (@(posedge clk)
        disable iff (reset) !fill_full);

    // ORACLE: same argument on the writeback FIFO, which shares `l2bi_stall`.
    T_OCC_WRITEBACK_FIFO_NEVER_FULL: assert property (@(posedge clk)
        disable iff (reset) !wbq_full);

    // ORACLE: `l2_cache_pending_miss_cam` is sized QUEUE_SIZE = 16 >= fill FIFO
    // depth + pipeline stages, exactly so that it cannot run out of rows while
    // the FIFO is bounded. If it did, `next_empty` would be meaningless and two
    // misses for one line would both go to memory.
    T_OCC_PENDING_MISS_CAM_NOT_FULL: assert property (@(posedge clk)
        disable iff (reset) cam_free != 16'd0);

    // ORACLE: the shadow queue is pushed on `enqueue_fill_request` and popped
    // on `fill_dequeue_en`, which are the design FIFO's own enable signals, so
    // an independent count of the same events must agree with `count`.
    T_OCC_FILL_SHADOW_COUNT_MATCHES: assert property (@(posedge clk)
        disable iff (reset) sh_cnt == fill_cnt);

    // ORACLE: an admitted request is answered exactly once, so in-flight is
    // admissions minus responses. It is bounded by what the L2 can hold: three
    // pipeline stages, the fill FIFO (<= 7), the writeback FIFO's flush entries
    // (<= 7) and the one packet in the l2bi restart register.
    T_OCC_INFLIGHT_LE_24: assert property (@(posedge clk)
        disable iff (reset) inflight <= 8'd24);

    // ORACLE: the tighter bound. The two FIFOs cannot both be near full at the
    // same time for long, because `l2bi_stall` shuts the arb stage as soon as
    // either passes its threshold. Stated as the candidate it is: this is the
    // inequality that has to be argued, not the one that is obvious.
    T_OCC_INFLIGHT_LE_12: assert property (@(posedge clk)
        disable iff (reset) inflight <= 8'd12);

    // ---- no loss / conservation --------------------------------------
    // ORACLE: a response with nothing in flight would be a response with no
    // request, which the outstanding table denies. This is the counting form of
    // T_REQRSP_NO_UNSOLICITED_RESPONSE and fails on a different witness.
    T_CONSERV_NO_RESPONSE_WHEN_EMPTY: assert property (@(posedge clk)
        disable iff (reset) (rsp_v && adm_n == 3'd0) |-> inflight != 8'd0);

    // ORACLE: one slot cannot be answered more times than it was asked, at any
    // point in the trace. Every response for the slot must be paid for by an
    // earlier admission of that slot.
    T_CONSERV_FOCUS_RSP_LE_ADM: assert property (@(posedge clk)
        disable iff (reset) f_rsp_cnt <= f_adm_cnt);

    // ORACLE: and never more than one of them may be open at a time, because
    // the L1 queue entry that owns the id is marked `request_sent` until the
    // response arrives.
    T_CONSERV_FOCUS_AT_MOST_ONE_OPEN: assert property (@(posedge clk)
        disable iff (reset) (f_adm_cnt - f_rsp_cnt) <= 8'd1);

    // ---- protocol conformance ----------------------------------------
    // ORACLE: `l2_ready[i] = grant_oh[i] && can_accept_request` and grant_oh
    // is driven from `request(l2i_request_valid)`, so a grant without a request
    // cannot happen. It would clock a garbage packet into the arb register.
    T_PROTO_NO_READY_WITHOUT_REQUEST: assert property (@(posedge clk)
        disable iff (reset) (rdy & ~rqv) == '0);

    // ORACLE: the three L1 queues only clear an entry on a response, so a
    // request that was offered and not taken is still offered next cycle unless
    // the L2 answered something in the meantime. Withdrawing it would leave the
    // arb stage's round-robin priority rotated for a request that never was.
    T_PROTO_REQUEST_NOT_WITHDRAWN: assert property (@(posedge clk)
        disable iff (reset)
        (rqv[0] && !rdy[0] && !rsp_v) |=> rqv[0]);

    // ORACLE: `m_wlast` is registered as `burst_offset_nxt == BURST_BEATS - 1`,
    // so it must coincide with the last beat an independent counter of accepted
    // beats has seen. A `wlast` off by one leaves the slave and the master
    // disagreeing about where the next line starts.
    T_PROTO_AXI_WLAST_ON_LAST_BEAT: assert property (@(posedge clk)
        disable iff (reset)
        (w_acc && `NYZ.axi_bus.m_wlast) |-> mem_w_beat == BEATW'(BURST_BEATS - 1));

    // ORACLE: `l1_l2_interface` assigns `l2i_request.core = CORE_ID`, and the
    // core field is carried unchanged to the response, so a response can only
    // name a core that exists. A response naming core 2 would be delivered to
    // nobody and its L1 entry would never be freed.
    T_PROTO_RESPONSE_CORE_LEGAL: assert property (@(posedge clk)
        disable iff (reset) rsp_v |-> rsp_legal);

    // ORACLE: `can_accept_request = !l2bi_request_valid && !l2bi_stall`, so a
    // packet being re-injected from the bus interface takes the arb register
    // for itself. A core grant in the same cycle would overwrite it and the
    // fill would be lost after its memory read had already been paid for.
    T_PROTO_NO_GRANT_DURING_RESTART: assert property (@(posedge clk)
        disable iff (reset) bi_req_valid |-> rdy == '0);

    // ---- data integrity ----------------------------------------------
    // ORACLE: `fill_buffer` is written beat by beat from `s_rdata` and flattened
    // into `l2bi_data_from_memory` in reverse beat order. The checker reassembles
    // the same beats independently, in its own order, from the AXI wires. At the
    // cycle the fill is handed back to the pipeline the two must be equal --
    // this is where a lane swap or an off-by-one in the burst offset shows up.
    T_DATA_FILL_MATCHES_AXI_BEATS: assert property (@(posedge clk)
        disable iff (reset) (deq_fill && rd_fresh && !bi_collided) |-> bi_mem == rd_shadow);

    // ORACLE: end to end. The line the memory sent, carried through the fill
    // buffer, the arb register, the tag stage, the read stage and the update
    // stage, is the line the response delivers to the cores -- for a load,
    // where `update_data` is false and the store-mask merge is the identity.
    // Four registered stages and one FIFO separate the two observations.
    T_DATA_LOAD_FILL_RESPONSE_MATCHES_AXI: assert property (@(posedge clk)
        disable iff (reset)
        (fl_v3 && rsp_v && `NYZ.l2_response.packet_type == L2RSP_LOAD_ACK)
            |-> `NYZ.l2_response.data == fl_d3);

    // ORACLE: the other direction. `writeback_fifo_in.data` is `l2r_data`, the
    // line read out of the L2 array; the FIFO holds it while earlier writebacks
    // drain; the state machine slices it into beats in reverse order. When
    // exactly one writeback for the probed line is outstanding, the beat that
    // carries the probed lane must carry the bytes the read stage put in.
    T_DATA_WRITEBACK_BEAT_MATCHES_L2_LINE: assert property (@(posedge clk)
        disable iff (reset)
        (w_acc && wb_word_ok && wb_probe_cnt == 4'd1
         && `NYZ.mem_wr_line == `NYZ.mem_probe_line
         && mem_w_beat == BEATW'(BURST_BEATS - 1) - f_lane)
            |-> `NYZ.axi_bus.m_wdata == wb_word);

    // ORACLE: `l2_cache_update_stage` merges byte lane by byte lane --
    // `store_mask[b] && update_data ? request.data[b] : original[b]`. A byte the
    // request masked in must appear in the response, otherwise a store is
    // acknowledged without having been applied.
    T_DATA_STORE_MERGE_APPLIES_MASK: assert property (@(posedge clk)
        disable iff (reset)
        (sm_v && rsp_v) |-> `NYZ.l2_response.data[sm_base+:8] == sm_byte);

    // ---- end-to-end ordering -----------------------------------------
    // ORACLE: `pending_fill_fifo` is a FIFO, so the identity of the request
    // re-injected at the arb stage is the identity of the OLDEST miss still
    // waiting for memory. The shadow queue records the same pushes and pops
    // independently. This is the one place in the design where a request leaves
    // the pipeline and comes back, and it is where a reorder would hide.
    T_ORDER_FILL_QUEUE_FIFO_ORDER: assert property (@(posedge clk)
        disable iff (reset) (deq_fill && sh_cnt != 4'd0) |-> shq[sh_rd] == sh_pop_exp);

    // ORACLE: the master's `burst_offset_ff` counts beats of the burst in
    // progress. An independent count of accepted read beats must agree with it
    // throughout the transfer, or a beat is being written to the wrong lane of
    // the fill buffer.
    T_ORDER_AXI_READ_BEATS_IN_SEQUENCE: assert property (@(posedge clk)
        disable iff (reset) bus_rd_xfer |-> bo_ff == rd_cnt);

    // ---- coherence ---------------------------------------------------
    // ORACLE: a d-cache invalidate is answered by ONE core but broadcast to
    // ALL of them. `response_dinvalidate` is not gated by `ack_for_me`, so every
    // core snoops the address, and any core that holds the line clears the
    // hitting way. Two cycles after the broadcast no L1D anywhere still holds
    // that (set, tag) valid. This crosses the L2 update stage, the shared
    // response wire, both cores' stage-1 snoop read and both cores' stage-2 tag
    // write -- it is the coherence claim the subsystem exists to make.
    T_COH_DINVALIDATE_CLEARS_ALL_L1D: assert property (@(posedge clk)
        disable iff (reset) dinv_p2 |-> dinv_live == '0);

    // ORACLE: `response_iinvalidate` drives `l2i_itag_update_en` to all ones
    // with `l2i_itag_update_valid` low, in every core, so the whole i-cache set
    // is invalidated everywhere. Self-modifying code depends on it.
    T_COH_IINVALIDATE_CLEARS_ALL_L1I: assert property (@(posedge clk)
        disable iff (reset) iinv_p2 |-> iinv_live == '0);

    // ORACLE: Nyuzi's L1D is write-UPDATE, not write-invalidate: a core that
    // snoop-hits a store ack must take the new data into its own array, or it
    // keeps serving the pre-store value from a line it still calls valid.
    T_COH_STORE_ACK_UPDATES_SNOOP_HITTER: assert property (@(posedge clk)
        disable iff (reset) store_ack_wrote_ok);

    // ---- arbitration fairness ----------------------------------------
    // ORACLE: `rr_arbiter` rotates `priority_oh` on every cycle where
    // `update_lru` (here `can_accept_request`) is high and any core is asking.
    // With two cores, a core that is passed over on one accepting cycle holds
    // top priority on the next, so it waits at most ONE accepting cycle. The
    // counter deliberately does not count cycles where the L2 is refusing
    // everyone: that is back pressure, not unfairness.
    T_FAIR_CORE0_GRANTED_WITHIN_1: assert property (@(posedge clk)
        disable iff (reset) fair_cnt[0] <= 4'd1);

    T_FAIR_CORE1_GRANTED_WITHIN_1: assert property (@(posedge clk)
        disable iff (reset) fair_cnt[1] <= 4'd1);

    // ---- bounded response --------------------------------------------
    // ORACLE: the L2 pipeline has no stall. `l2t_request_valid <=
    // l2a_request_valid` and `l2r_request_valid <= l2t_request_valid` are
    // unconditional, so a packet that entered the arb register is at the tag
    // stage the next cycle and the read stage the cycle after. Back pressure is
    // applied at the arb stage only, four stages early, via `l2bi_stall`.
    T_BOUNDRSP_PIPE_ARB_TO_TAG: assert property (@(posedge clk)
        disable iff (reset) l2a_valid |=> l2t_valid);

    T_BOUNDRSP_PIPE_TAG_TO_READ: assert property (@(posedge clk)
        disable iff (reset) l2t_valid |=> l2r_valid);

    // ORACLE: a fill dequeued from `pending_fill_fifo` re-enters at the arb
    // register on the next cycle with `l2a_l2_fill` set, and `l2_cache_update_
    // stage` responds unconditionally on `l2r_l2_fill`. So the memory round
    // trip ends in a response exactly four cycles after the dequeue -- the
    // bounded-response statement about the deepest path in the subsystem.
    T_BOUNDRSP_FILL_ANSWERED_IN_4: assert property (@(posedge clk)
        disable iff (reset) (deq_fill && !bi_collided) |-> ##4 rsp_v);

    // ORACLE: a hit that is not a flush satisfies the update stage's response
    // condition directly, so it is acknowledged on the very next cycle. No
    // buffer sits between the read stage and the update stage.
    T_BOUNDRSP_HIT_ANSWERED_NEXT_CYCLE: assert property (@(posedge clk)
        disable iff (reset)
        (l2r_valid && l2r_hit && l2r_req.packet_type != L2REQ_FLUSH) |=> rsp_v);

    // ---- deadlock freedom (bounded safety) ---------------------------
    // ORACLE: the liveness question, written as a bound. While system memory is
    // answering every cycle and at least one request is outstanding somewhere,
    // SOMETHING must happen: the bus interface leaves IDLE within a cycle, an
    // address burst is one cycle, a data burst is BURST_BEATS cycles, and the
    // response follows four cycles after the dequeue. A generous 32-cycle
    // window covers a writeback and a fill back to back. If this counter can be
    // driven past the bound with the memory always granting, the buffers are
    // waiting on each other and that is a deadlock -- which is exactly the
    // failure mode that four buffers in a cycle can produce.
    T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_32: assert property (@(posedge clk)
        disable iff (reset) stall_cnt <= 8'd32);

    // ORACLE: `l2bi_stall` is `fill_queue_almost_full || writeback_fifo_almost_
    // full`, and ALMOST_FULL_THRESHOLD is 4, so it cannot be asserted while both
    // FIFOs are empty. Back pressure with nothing queued would stop the whole
    // subsystem with no work in it -- a deadlock with no cause.
    T_DEADLOCK_STALL_IMPLIES_WORK_PENDING: assert property (@(posedge clk)
        disable iff (reset) bi_stall |-> (fill_pending || wbq_pending));

    // ---- allocator discipline ----------------------------------------
    // ORACLE: `fill_dequeue_en` is asserted only in STATE_READ_COMPLETE, which
    // is only reachable from IDLE with `fill_request_pending`. Popping an empty
    // `sync_fifo` would hand the pipeline a stale packet and free a CAM row
    // that belongs to a live miss.
    T_ALLOC_NO_FILL_DEQUEUE_WHEN_EMPTY: assert property (@(posedge clk)
        disable iff (reset) deq_fill |-> !fill_empty);

    // ORACLE: `writeback_complete` is asserted only at the end of a burst the
    // state machine started because `writeback_pending` was high.
    T_ALLOC_NO_WB_COMPLETE_WHEN_EMPTY: assert property (@(posedge clk)
        disable iff (reset) wb_complete |-> !wb_empty);

    // ORACLE: `l1_load_miss_queue` allocates entry t only for thread t, and a
    // thread cannot have two loads outstanding because it is suspended until the
    // wake. Allocating over a live entry would drop the first miss and hang the
    // thread that was waiting on it.
    T_ALLOC_MISS_QUEUE_NO_DOUBLE_ALLOC: assert property (@(posedge clk)
        disable iff (reset) mq_double_alloc == '0);

    // ---- reset / initialisation --------------------------------------
    // ORACLE: every stage's valid bit has an asynchronous reset, so nothing is
    // in the L2 pipeline while reset is held.
    T_RESET_L2_PIPE_EMPTY: assert property (@(posedge clk)
        reset |-> !(l2a_valid || l2t_valid || l2r_valid || rsp_v));

    // ORACLE: `pending_entries` and `pending_stores` are asynchronously cleared,
    // so no queue can be offering a request while reset is held.
    T_RESET_NO_L1_REQUEST: assert property (@(posedge clk)
        reset |-> rqv == '0);

    // ORACLE: `sync_fifo`'s head, tail and count are asynchronously cleared.
    T_RESET_FIFOS_EMPTY: assert property (@(posedge clk)
        reset |-> (fill_empty && wb_empty));

endmodule

bind nyuzi_l2_ring_coherence_ft nyuzi_l2_targets u_targets(.clk(clk), .reset(reset));

`undef NYZ
