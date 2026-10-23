//
// ORACLE-FREE TARGET assertions for tasks/nyuzi_l2_ring_coherence_oraclefree.
// Authored 2026-08-20 from the parent package's twelve hard targets.
//
// WHY THIS FILE EXISTS. The parent states most of its targets against a
// REFERENCE MODEL kept in the checker: an outstanding-request table keyed on
// (core, id, class), an in-flight counter, a shadow copy of the pending-fill
// FIFO, an independent re-assembly of the AXI read burst. That model IS the
// modelling work we want to measure an agent doing, so this file carries none
// of it. There is no state here at all -- no clocked block, no counter, no
// shadow queue, no "expected value" register. Every assertion below is a
// property of registers the DESIGN already has, and the FRA cut consequently
// has nothing of this checker's to keep.
//
// WHAT THE DESIGN GIVES US TO SAY THINGS WITH:
//
//   l1_load_miss_queue.pending_entries[t]  .valid .request_sent .address
//   l1_store_queue.pending_stores[t]       .valid .request_sent .address
//                                          .response_received
//                                          .flush .iinvalidate .dinvalidate
//   dcache_tag_stage.way_tag_gen[w]        .line_valid[set]
//                                          .sram_tags.data[set]
//   l2_cache_pending_miss_cam              .empty_entries        (16 rows)
//   l2_axi_bus_interface                   .pending_fill_fifo.{count,head,data}
//                                          .pending_writeback_fifo.count
//   l2a_request_valid / l2t_request_valid / l2r_request_valid / l2_response_valid
//
// The L1 queues' own record of what a core asked for is the table the parent
// modelled; the CAM and the two FIFO occupancy counters are the in-flight
// counter it modelled. Both are the design's, not ours.
//
// ONE RESTRICTION, AND IT IS NOT A STYLE CHOICE. This cut has no
// thread_select_stage, so nothing suspends a thread that is waiting on a
// D-CACHE load. A thread may therefore miss a second time and OVERWRITE
// l1_load_miss_queue_dcache.pending_entries[t] while its first request is
// still outstanding: valid stays 1, request_sent goes back to 0, the address
// changes, and the entry can even be cleared by the first response while the
// second request is still in the L2. Any per-slot claim about the d-cache load
// queue is false for that reason and not because of anything the L2 does --
// which is why the parent's admission-side targets (no-unsolicited-response,
// no-reissue-while-outstanding, at-most-one-open, no-double-alloc) are the
// ones MISSING from hard_targets.txt. The other two request sources are safe
// and are what the per-slot targets below are anchored on:
//
//   * l1_store_queue refuses to re-allocate an entry that is outstanding
//     (update_store_entry needs !valid, a write-combine -- which itself needs
//     !request_sent -- or a response this cycle; enqueue_cache_control needs
//     !valid or a response this cycle), and
//   * ifetch_tag_stage masks a thread out of fetch arbitration through
//     icache_wait_threads for as long as its i-cache miss is unanswered, and
//     squashes the one fetch already selected when the miss is detected.
//
// $past, $onehot0 and $countones are SVA sampled-value functions, not a
// model. The `logic` vectors declared below are combinational verdicts
// (assign / always_comb only) over design signals, gathered that way because a
// hierarchical reference through an instance array needs an elaboration-time
// index.
//
// Twelve targets keep their parent LABEL, one for each of the parent's twelve
// hard rows; two more are NEW, in categories the parent already had. Where the
// statement is no longer the parent's statement the comment above the label
// says RESTATED and says what changed.
//
`include "defines.svh"

import defines::*;

`define NYZ nyuzi_l2_ring_coherence_ft
`define L1X(c)     `NYZ.core_gen[c].l1_agent.l1_l2_interface
`define L1I(c)     `L1X(c).l1_load_miss_queue_icache
`define L1S(c)     `L1X(c).l1_store_queue
`define DWAY(c,w)  `NYZ.core_gen[c].l1_agent.dcache_tag_stage.way_tag_gen[w]
`define BI         `NYZ.l2_cache.l2_axi_bus_interface
`define LIVE(c,w,s,t) (`DWAY(c,w).line_valid[s] \
                       && `DWAY(c,w).sram_tags.data[s] == (t))

module nyuzi_l2_targets(input clk, input reset);

    localparam int NCORE = `NUM_CORES;                  // 2
    localparam int NID   = `THREADS_PER_CORE;           // 4
    localparam int CIDW  = $clog2(`NUM_CORES);          // 1
    localparam int IDW   = $clog2(`THREADS_PER_CORE);   // 2
    localparam int FIFO_SIZE = 8;                       // l2_axi_bus_interface
    localparam int CAM_ROWS  = 16;                      // l2_cache_pending_miss_cam
    localparam int KEYW  = $bits(core_id_t) + IDW + 2;

    // The class a request belongs to, which is how l1_l2_interface routes the
    // response back: 0 d-cache load, 1 i-cache load, 2 store or cache control.
    // A pure function of the packet -- no state.
    function automatic logic[1:0] req_class(input l2req_packet_t r);
        if (r.cache_type == CT_ICACHE)
            return 2'd1;
        else if (r.packet_type == L2REQ_LOAD || r.packet_type == L2REQ_LOAD_SYNC)
            return 2'd0;
        else
            return 2'd2;
    endfunction

    // Is (set, tag) still valid in ANY way of ANY core's L1D? Unrolled over
    // cores and ways because both are generate-block indices and must be
    // elaboration-time constants; `NUM_CORES` is 2 and `L1D_WAYS` is 4 here.
    function automatic logic dcache_line_live(input l2_addr_t a);
        l1d_tag_t t;
        l1d_set_idx_t s;
        {t, s} = a;
        return `LIVE(0,0,s,t) || `LIVE(0,1,s,t) || `LIVE(0,2,s,t) || `LIVE(0,3,s,t)
            || `LIVE(1,0,s,t) || `LIVE(1,1,s,t) || `LIVE(1,2,s,t) || `LIVE(1,3,s,t);
    endfunction

    // ------------------------------------------------- boundary shorthands
    logic[NCORE - 1:0] rqv;
    logic[NCORE - 1:0] rdy;
    logic[NCORE - 1:0] adm;

    always_comb
    begin : boundary
        for (int i = 0; i < NCORE; i++)
        begin
            rqv[i] = `NYZ.l2i_request_valid[i];
            rdy[i] = `NYZ.l2_ready[i];
            adm[i] = `NYZ.l2i_request_valid[i] && `NYZ.l2_ready[i];
        end
    end

    wire             rsp_v     = `NYZ.l2_response_valid;
    wire             rsp_legal = `NYZ.l2_response.core < core_id_t'(NCORE);
    wire[CIDW - 1:0] rsp_core  = `NYZ.l2_response.core[CIDW - 1:0];
    wire[IDW - 1:0]  rsp_id    = `NYZ.l2_response.id;

    l2rsp_packet_type_t rsp_type;
    cache_type_t        rsp_ctype;
    assign rsp_type  = `NYZ.l2_response.packet_type;
    assign rsp_ctype = `NYZ.l2_response.cache_type;

    // The two response families, split by the L1 queue that owns them. Every
    // non-LOAD_ACK ack is a store-queue ack: storebuf_l2_response_valid is
    // exactly STORE_ACK | FLUSH_ACK | IINVALIDATE_ACK | DINVALIDATE_ACK.
    wire rsp_icache = rsp_v && rsp_legal && rsp_ctype == CT_ICACHE;
    wire rsp_store  = rsp_v && rsp_legal && rsp_type != L2RSP_LOAD_ACK;
    wire dinv_ack   = rsp_v && rsp_type == L2RSP_DINVALIDATE_ACK;

    // ---------------------------------------------------- L2 interior taps
    wire l2a_valid = `NYZ.l2_cache.l2_cache_arb_stage.l2a_request_valid;
    wire l2t_valid = `NYZ.l2_cache.l2_cache_tag_stage.l2t_request_valid;
    wire l2r_valid = `NYZ.l2_cache.l2_cache_read_stage.l2r_request_valid;

    l2req_packet_t l2r_req;
    assign l2r_req = `NYZ.l2_cache.l2_cache_read_stage.l2r_request;

    wire             l2r_core_legal = l2r_req.core < core_id_t'(NCORE);
    wire[CIDW - 1:0] l2r_core       = l2r_req.core[CIDW - 1:0];
    wire[IDW - 1:0]  l2r_id         = l2r_req.id;
    wire             l2r_store_cls  = req_class(l2r_req) == 2'd2;

    wire bi_req_valid = `BI.l2bi_request_valid;
    wire enq_fill     = `BI.enqueue_fill_request;
    wire enq_wb       = `BI.enqueue_writeback_request;
    wire deq_fill     = `BI.fill_dequeue_en;
    wire wb_complete  = `BI.writeback_complete;
    wire fill_pending = `BI.fill_request_pending;
    wire wbq_pending  = `BI.writeback_pending;

    wire[3:0] fill_cnt = `BI.pending_fill_fifo.count;
    wire[3:0] wb_cnt   = `BI.pending_writeback_fifo.count;
    wire[2:0] ff_head  = `BI.pending_fill_fifo.head;

    wire[CAM_ROWS - 1:0] cam_free = `BI.l2_cache_pending_miss_cam.empty_entries;
    wire[4:0]            cam_used = 5'($countones(~cam_free));

    // The three occupancy registers the L2 keeps, added up. Naively this can
    // be 16 + 8 + 8; what makes an inequality out of it is the argument below.
    wire[7:0] l2_occupancy = 8'(cam_used) + 8'(fill_cnt) + 8'(wb_cnt);

    // ------------------------------------------------------------- AXI tap
    wire w_acc  = `NYZ.axi_bus.m_wvalid && `NYZ.axi_bus.s_wready;
    wire r_acc  = `NYZ.axi_bus.s_rvalid && `NYZ.axi_bus.m_rready;
    wire ar_acc = `NYZ.axi_bus.m_arvalid && `NYZ.axi_bus.s_arready;
    wire aw_acc = `NYZ.axi_bus.m_awvalid && `NYZ.axi_bus.s_awready;

    // "The memory is answering." With every throttle high the slave accepts an
    // address every cycle and sources a beat every cycle, so the bus interface
    // cannot be waiting on anything outside the design.
    wire mem_granting = `NYZ.mem_awready_free && `NYZ.mem_wready_free
                     && `NYZ.mem_arready_free && `NYZ.mem_rvalid_free;

    // Anything at all moved in the subsystem this cycle.
    wire progress_event = rsp_v || (|adm) || enq_fill || enq_wb || deq_fill
                       || wb_complete || ar_acc || aw_acc || w_acc || r_acc;

    // Something is asking, in flight, or queued -- stated over the design's
    // own valid bits and queue-empty flags, not over a model's table.
    wire work_pending = (|rqv) || l2a_valid || l2t_valid || l2r_valid
                     || rsp_v || bi_req_valid || fill_pending || wbq_pending;

    // ----------------------------------------- per-core L1 queue taps
    // A generate block, because a hierarchical reference through an instance
    // ARRAY needs an elaboration-time index; a for loop inside always_comb
    // would not compile.
    logic[NCORE - 1:0] iq_open;      // i-cache miss queue entry [rsp_id] open
    logic[NCORE - 1:0] iq_addr_ok;   // ... and it recorded this address
    logic[NCORE - 1:0] sq_open;      // store queue entry [rsp_id] open
    logic[NCORE - 1:0] sq_addr_ok;
    logic[NCORE - 1:0] sq_flush;
    logic[NCORE - 1:0] sq_iinv;
    logic[NCORE - 1:0] sq_dinv;
    logic[NCORE - 1:0] l2r_sq_open;  // store queue entry [l2r_id] open
    logic[NCORE - 1:0] snoop_ok;

    genvar gc, gs, gw, gv;
    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : tap_core
            // An i-cache miss queue entry is open from the cycle it is
            // allocated until the response clears `valid`; `request_sent`
            // separates "waiting for the arbiter" from "asked the L2".
            assign iq_open[gc] = `L1I(gc).pending_entries[rsp_id].valid
                              && `L1I(gc).pending_entries[rsp_id].request_sent;
            assign iq_addr_ok[gc] =
                `L1I(gc).pending_entries[rsp_id].address == `NYZ.l2_response.address;

            // A store queue entry stays valid after a SYNCHRONIZED store is
            // answered -- the thread has to come back for the result -- so
            // `response_received` is what says the transaction is still open.
            assign sq_open[gc] = `L1S(gc).pending_stores[rsp_id].valid
                              && `L1S(gc).pending_stores[rsp_id].request_sent
                              && !`L1S(gc).pending_stores[rsp_id].response_received;
            assign sq_addr_ok[gc] =
                `L1S(gc).pending_stores[rsp_id].address == `NYZ.l2_response.address;
            assign sq_flush[gc] = `L1S(gc).pending_stores[rsp_id].flush;
            assign sq_iinv[gc]  = `L1S(gc).pending_stores[rsp_id].iinvalidate;
            assign sq_dinv[gc]  = `L1S(gc).pending_stores[rsp_id].dinvalidate;

            assign l2r_sq_open[gc] = `L1S(gc).pending_stores[l2r_id].valid
                              && `L1S(gc).pending_stores[l2r_id].request_sent
                              && !`L1S(gc).pending_stores[l2r_id].response_received;

            assign snoop_ok[gc] =
                !(`L1X(gc).response_stage2_valid
                  && `L1X(gc).response_stage2.cache_type == CT_DCACHE)
                || $onehot0(`L1X(gc).snoop_hit_way_oh);
        end
    endgenerate

    wire snoop_onehot_ok = &snoop_ok;

    // The ack the response carries against the request the store queue
    // recorded. `pending_stores` holds one flag per cache-control kind and
    // none of them for a plain store, which is the design's own copy of the
    // field `l2_cache_update_stage`'s response_type case reads.
    wire rsp_kind_agrees =
           (!(rsp_store && rsp_type == L2RSP_STORE_ACK)
            || (sq_open[rsp_core] && !sq_flush[rsp_core]
                && !sq_iinv[rsp_core] && !sq_dinv[rsp_core]))
        && (!(rsp_store && rsp_type == L2RSP_FLUSH_ACK)
            || (sq_open[rsp_core] && sq_flush[rsp_core]))
        && (!(rsp_store && rsp_type == L2RSP_IINVALIDATE_ACK)
            || (sq_open[rsp_core] && sq_iinv[rsp_core]))
        && (!(rsp_store && rsp_type == L2RSP_DINVALIDATE_ACK)
            || (sq_open[rsp_core] && sq_dinv[rsp_core]))
        && (!rsp_icache || rsp_type == L2RSP_LOAD_ACK);

    // The address the response carries against the address the queue the
    // cache_type selects recorded at admission.
    //
    // FLUSH_ACK IS EXCLUDED, and this is a fact about the design, not a
    // weakening for convenience. A flush that has to write its line back is
    // answered on its SECOND pass, re-injected by `l2_axi_bus_interface` as
    //     l2bi_request = lmq_out_request;
    //     if (restart_flush_request) begin ... packet_type, core, id and
    //         cache_type are overridden, and the ADDRESS FIELD IS NOT ...
    // ("the other fields in the request packet are ignored. To avoid creating
    // a mux for them, we just leave them assigned to the load_request
    // fields"). So a FLUSH_ACK carries whatever address happened to be at the
    // head of the fill FIFO, and `l2_response.address <= l2r_request.address`
    // copies it out to the cores. Nothing reads it -- a FLUSH_ACK sets no
    // dcache_update_en -- but asserting it matches would be asserting
    // something false. Every other ack carries its request's address, through
    // the fill FIFO and back.
    wire rsp_store_addr = rsp_v && rsp_legal
                       && (rsp_type == L2RSP_STORE_ACK
                        || rsp_type == L2RSP_IINVALIDATE_ACK
                        || rsp_type == L2RSP_DINVALIDATE_ACK);

    wire rsp_addr_agrees = (!rsp_icache || iq_addr_ok[rsp_core])
                        && (!rsp_store_addr || sq_addr_ok[rsp_core]);

    // ---------------------------- one line in at most one L1D way, per core
    logic[NCORE - 1:0][`L1D_SETS - 1:0][`L1D_WAYS - 1:0][`L1D_WAYS - 1:0] dup_way;

    generate
        for (gc = 0; gc < NCORE; gc++)
        begin : dup_core
            for (gs = 0; gs < `L1D_SETS; gs++)
            begin : dup_set
                for (gw = 0; gw < `L1D_WAYS; gw++)
                begin : dup_way_a
                    for (gv = 0; gv < `L1D_WAYS; gv++)
                    begin : dup_way_b
                        assign dup_way[gc][gs][gw][gv] = (gw < gv)
                            && `DWAY(gc,gw).line_valid[gs]
                            && `DWAY(gc,gv).line_valid[gs]
                            && (`DWAY(gc,gw).sram_tags.data[gs]
                                == `DWAY(gc,gv).sram_tags.data[gs]);
                    end
                end
            end
        end
    endgenerate

    // ------------------------------- slot uniqueness inside the fill FIFO
    // The FIFO's own storage, read where the FIFO says it is live: entry i is
    // occupied when (i - head) mod SIZE < count. No shadow copy is kept; this
    // reads `data`, `head` and `count` of the design's `sync_fifo`.
    logic[FIFO_SIZE - 1:0]              ff_occ;
    logic[FIFO_SIZE - 1:0][1:0]         ff_cls;
    logic[FIFO_SIZE - 1:0][KEYW - 1:0]  ff_key;
    logic                               fifo_slot_dup;

    always_comb
    begin : fifo_scan
        l2req_packet_t p;
        logic[2:0] off;
        for (int i = 0; i < FIFO_SIZE; i++)
        begin
            p = l2req_packet_t'(
                `BI.pending_fill_fifo.data[i][$bits(l2req_packet_t) - 1:0]);
            off = 3'(i) - ff_head;
            ff_occ[i] = {1'b0, off} < fill_cnt;
            ff_cls[i] = req_class(p);
            ff_key[i] = {p.core, p.id, req_class(p)};
        end
    end

    always_comb
    begin : fifo_dup_scan
        fifo_slot_dup = 1'b0;
        for (int i = 0; i < FIFO_SIZE; i++)
            for (int j = i + 1; j < FIFO_SIZE; j++)
                // class 0 -- the d-cache load slots -- is excluded on purpose:
                // see the note about the missing thread_select_stage above.
                if (ff_occ[i] && ff_occ[j] && ff_cls[i] != 2'd0
                    && ff_cls[j] != 2'd0 && ff_key[i] == ff_key[j])
                    fifo_slot_dup = 1'b1;
    end

    // ==================================================================
    //                        TARGET ASSERTIONS
    // ==================================================================

    // ---- request-response correspondence -----------------------------
    // Only `ifetch_data_stage`'s miss queue issues CT_ICACHE requests, so a
    // CT_ICACHE response must name an i-cache miss queue entry that is
    // allocated AND has been sent. Stated on the design's own entry instead of
    // on a modelled outstanding table: the queue is the design's record of the
    // same fact, and it is separated from the response wire by the arb grant,
    // three L2 stages, a possible detour through the fill FIFO and an AXI
    // burst.
    T_REQRSP_ICACHE_RESPONSE_HAS_REQUEST: assert property (@(posedge clk)
        disable iff (reset) rsp_icache |-> iq_open[rsp_core]);

    // RESTATED. The parent compares the response's cache_type against a
    // symbolic slot's recorded request, which needs a model of the request.
    // The design already records the address of every request it has out: this
    // says the response's address is the one recorded IN THE QUEUE ITS
    // cache_type SELECTS -- i-cache miss queue for CT_ICACHE, store queue for
    // the store and invalidate acks (see rsp_store_addr above for why the
    // flush ack cannot be included). A response demultiplexed onto the wrong
    // queue, or relabelled anywhere between the arb register and the update
    // stage, fails here, which is the failure the parent's target watched for.
    T_REQRSP_RESPONSE_CACHE_TYPE_MATCHES: assert property (@(posedge clk)
        disable iff (reset) rsp_addr_agrees);

    // RESTATED. `l2_cache_update_stage`'s response_type case is a total
    // function of the request's packet_type. The design's own copy of that
    // packet_type, on the L1 side, is the kind flags in `pending_stores`:
    // flush, iinvalidate, dinvalidate, or none of them for a plain or
    // synchronized store. So the ack a slot receives must agree with the flags
    // its entry was allocated with -- the parent's claim, with the store
    // queue's record standing in for the model's `f_type`.
    T_REQRSP_RESPONSE_TYPE_MATCHES: assert property (@(posedge clk)
        disable iff (reset) rsp_kind_agrees);

    // ---- no loss / conservation --------------------------------------
    // RESTATED. "Answered no more often than asked" is a counter in the
    // parent. Here it is the design-state form: a store-class ack is only ever
    // delivered to a store queue entry that is allocated, has been sent, and
    // has not already been answered. An entry cannot be re-allocated or
    // re-sent while it is in that state, so a second ack for one slot has
    // nowhere to land and fails this. The d-cache load class is excluded for
    // the reason in the header.
    T_CONSERV_FOCUS_RSP_LE_ADM: assert property (@(posedge clk)
        disable iff (reset) rsp_store |-> sq_open[rsp_core]);

    // RESTATED. The parent asks whether anything was in flight when a response
    // arrived, counted by a model. The design-state form is stronger and needs
    // the same invariant: every store-class packet sitting in the L2 read
    // stage -- whether it came straight from the arb grant or came back out of
    // the fill FIFO after a memory round trip -- still has its L1 store queue
    // entry open behind it. A packet in the L2 that nobody is waiting for is
    // exactly the response-with-nothing-in-flight the parent was ruling out.
    T_CONSERV_NO_RESPONSE_WHEN_EMPTY: assert property (@(posedge clk)
        disable iff (reset)
        (l2r_valid && l2r_store_cls) |-> (l2r_core_legal && l2r_sq_open[l2r_core]));

    // ---- mutual exclusion / one-hot ----------------------------------
    // UNCHANGED from the parent. `dcache_tag_stage` guarantees a physical line
    // lives in at most one way of its set, so the snoop comparison can hit at
    // most one way. Already a property of the design's own registers.
    T_MUTEX_SNOOP_HIT_ONEHOT: assert property (@(posedge clk)
        disable iff (reset) snoop_onehot_ok);

    // ---- occupancy and bounds ----------------------------------------
    // UNCHANGED from the parent. `l2_cache_pending_miss_cam` is sized
    // QUEUE_SIZE = 16 >= fill FIFO depth + pipeline stages, exactly so that it
    // cannot run out of rows while the FIFO is bounded. If it did, `next_empty`
    // would be meaningless and two misses for one line would both go to memory.
    T_OCC_PENDING_MISS_CAM_NOT_FULL: assert property (@(posedge clk)
        disable iff (reset) cam_free != {CAM_ROWS{1'b0}});

    // RESTATED. The parent's tighter in-flight bound is admissions minus
    // responses, which is a counter. The same inequality over the design's own
    // state is the CAM's occupancy: a row is taken for each distinct line with
    // a miss outstanding and given back when that fill passes the read stage,
    // so occupied rows are bounded by what the fill FIFO holds (never 8, by the
    // ALMOST_FULL_THRESHOLD = SIZE - L2REQ_LATENCY argument) plus the fills
    // between the dequeue and the read stage (at most four). 12 is the bound
    // the RTL's own sizing comment argues for; the CAM is 16 rows, so nothing
    // structural gives it away.
    T_OCC_INFLIGHT_LE_12: assert property (@(posedge clk)
        disable iff (reset) cam_used <= 5'd12);

    // RESTATED. The looser bound, on everything the L2 holds at once: CAM rows
    // plus both FIFOs. Structurally that sum can be 32. It is really at most
    // about 22, and the argument is joint, not per-structure: `l2bi_stall`
    // shuts the arb stage as soon as EITHER FIFO passes its threshold, so
    // beyond that point only the packets already below the arb register -- at
    // most four -- can still enqueue, into one FIFO or the other but never
    // both. Adding the per-structure bounds alone gives 12 + 7 + 7 = 26 and
    // does not prove this.
    T_OCC_INFLIGHT_LE_24: assert property (@(posedge clk)
        disable iff (reset) l2_occupancy <= 8'd24);

    // ---- protocol conformance ----------------------------------------
    // UNCHANGED from the parent. `l1_l2_interface` assigns
    // `l2i_request.core = CORE_ID`, and the core field is carried unchanged to
    // the response, so a response can only name a core that exists. A response
    // naming core 2 would be delivered to nobody and its L1 entry would never
    // be freed.
    T_PROTO_RESPONSE_CORE_LEGAL: assert property (@(posedge clk)
        disable iff (reset) rsp_v |-> rsp_legal);

    // ---- end-to-end uniqueness ---------------------------------------
    // NEW, and the ring-slot uniqueness claim the parent made with a shadow
    // queue. Read the design's `pending_fill_fifo` where it says its own live
    // entries are -- (i - head) mod 8 < count -- and no two of them may name
    // the same (core, id, class). Two would mean one L1 entry had two memory
    // fetches outstanding at once, and the second fill would overwrite the
    // first's line after it had already been answered. i-cache and store slots
    // only; d-cache load slots are excluded per the header.
    T_UNIQ_FILL_FIFO_SLOT_UNIQUE: assert property (@(posedge clk)
        disable iff (reset) !fifo_slot_dup);

    // ---- coherence ---------------------------------------------------
    // Same statement as the parent, with $past where the parent used a
    // three-deep pipeline of its own registers. A d-cache invalidate is
    // answered by ONE core but broadcast to ALL of them: `response_dinvalidate`
    // is not gated by `ack_for_me`, so every core snoops the address and any
    // core that holds the line clears the hitting way. A response at T is in
    // `response_stage2` at T+1, the L1 tag write lands on the T+1 -> T+2 edge,
    // so T+2 is the first settled sample point. Two cycles after the broadcast
    // no L1D anywhere still holds that (set, tag) valid. This crosses the L2
    // update stage, the shared response wire, both cores' stage-1 snoop read
    // and both cores' stage-2 tag write.
    T_COH_DINVALIDATE_CLEARS_ALL_L1D: assert property (@(posedge clk)
        disable iff (reset)
        $past(dinv_ack, 2) |-> !dcache_line_live($past(`NYZ.l2_response.address, 2)));

    // NEW. The invariant that makes the whole invalidate path well defined and
    // that T_MUTEX_SNOOP_HIT_ONEHOT is a consequence of: within a core's L1D,
    // no physical line is valid in two ways of its set. `dupdate_way_idx`
    // picks the snoop-hit way when the line is already there and the LRU way
    // only when it is not, so a fill must never duplicate a line -- including
    // when two responses for one line land back to back and the second's snoop
    // read has to see the first's tag write through the bypass.
    T_COH_L1D_LINE_IN_ONE_WAY: assert property (@(posedge clk)
        disable iff (reset) dup_way == '0);

    // ---- deadlock freedom (bounded safety) ---------------------------
    // RESTATED as a bounded eventuality instead of the parent's stall counter,
    // which was a model. While system memory is answering every cycle and
    // there is work anywhere in the subsystem, SOMETHING must happen within 32
    // cycles: the bus interface leaves IDLE within a cycle, an address burst is
    // one cycle, a data burst is BURST_BEATS cycles, and the response follows
    // four cycles after the dequeue. A generous 32-cycle window covers a
    // writeback and a fill back to back. If the window can be run out with the
    // memory always granting, the buffers are waiting on each other -- which is
    // exactly the failure four buffers in a cycle can produce.
    T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_32: assert property (@(posedge clk)
        disable iff (reset)
        (mem_granting && work_pending && !progress_event)
            |-> ##[1:32] (progress_event || !mem_granting));

endmodule

bind nyuzi_l2_ring_coherence_ft nyuzi_l2_targets u_targets(.clk(clk), .reset(reset));

`undef LIVE
`undef BI
`undef DWAY
`undef L1S
`undef L1I
`undef L1X
`undef NYZ
