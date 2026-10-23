// ===========================================================================
// Candidate target assertions for the OpenPiton L1.5 <-> L2 subsystem.
//
// ORACLE-FREE ARM.  This file declares NO STATE.  There is no `always` block
// of any kind in it, no shadow FIFO, no outstanding-request set, no packet
// framer and no wait counter.  Every wire below is a combinational view of a
// register that already exists in the RTL or in the formal top, and every
// property is stated over those registers directly.
//
// Where the parent file compared the design against a model it had built,
// this one states the same obligation as a relation the design's own
// bookkeeping must satisfy:
//
//   * one-hot and mutual exclusion over `l2_mshr_wrap.state_mem_f` and
//     `l2_mshr_wrap.data_mem_f`, pairwise and register-free;
//   * the L1.5 NOC1 command buffer's valid array checked against its own
//     `command_wrindex` / `command_rdindex`, and against its own push and pop
//     one cycle earlier via `$past`;
//   * lifecycle facts written at the MSHR write port (`wr_data_en`,
//     `wr_index_in`, `data_in`, `data_mask_in`), which is where an entry can
//     change, rather than against a remembered copy of what it held;
//   * fairness, bounded response and deadlock freedom written as SVA
//     consecutive repetition -- `p[*N] |=> !p` -- which is the same safety
//     obligation the parent wrote with a saturating counter, without the
//     counter.
//
// Three properties are marked ENVIRONMENT-DERIVED.  Their subject is the set
// of memory requests that have left the L2 and not been answered, and the
// design does not name that set: the L2 keeps an MSHR entry in WAIT for
// reasons other than a memory miss.  They read it from the formal top's own
// memory responder queue (`u_mem.q_wr_f`, `u_mem.q_rd_f`, `u_mem.hdr_q`,
// `u_mem.tx_state_f`), which is existing environment state.  No new register
// is declared for them either.
//
// Field positions used, from define.tmp.h: MSG_MSHRID lives in flit 0 of a
// packet.  L2 MSHR field positions are from l2.tmp.h.
// ===========================================================================

module l15_l2_targets (input wire clk, input wire reset_n);

    genvar ge, ga, gb;

    // ------------------------------------------------------- NOC boundaries
    // NOC1: L1.5 -> L2 (requests)
    wire        n1_val  = openpiton_l15l2_deadlock_ft.l15_noc1_val;
    wire        n1_rdy  = openpiton_l15l2_deadlock_ft.l15_noc1_rdy;
    wire [63:0] n1_dat  = openpiton_l15l2_deadlock_ft.l15_noc1_data;

    // NOC2: L2 -> (L1.5 | memory)
    wire [63:0] n2_dat  = openpiton_l15l2_deadlock_ft.l2_noc2_data;
    wire [7:0]  n2_mid  = n2_dat[`MSG_MSHRID];

    // NOC3 egress of the L1.5, before the merge with the memory responder
    wire        l3_val  = openpiton_l15l2_deadlock_ft.l15_noc3_val;
    wire        l3_rdy  = openpiton_l15l2_deadlock_ft.l15_noc3_rdy;

    // =====================================================================
    // The L2 MSHR pool, flattened.  Every bit here is a slice of a register
    // that l2_mshr_wrap already holds.
    // =====================================================================
    wire [271:0] l2_line_flat;    // `L2_TAG_PLUS_INDEX = 39:6, 34 bits x 8
    wire [23:0]  l2_key_flat;     // `L2_MSHR_CMP_ADDR = `L2_TAG_INDEX, 3 x 8
    wire [15:0]  l2_way_flat;     // `L2_MSHR_WAY, 2 bits x 8
    wire [7:0]   l2_busy;
    wire [7:0]   l2_pend;

    generate
        for (ge = 0; ge < 8; ge = ge + 1) begin : g_l2e
            assign l2_line_flat[34*ge +: 34] =
                openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.data_mem_f[ge][`L2_TAG_PLUS_INDEX];
            assign l2_key_flat[3*ge +: 3] =
                openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_CMP_ADDR];
            assign l2_way_flat[2*ge +: 2] =
                openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_WAY];
            assign l2_busy[ge] =
                (openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.state_mem_f[ge]
                    != `L2_MSHR_STATE_INVAL);
            assign l2_pend[ge] =
                (openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.state_mem_f[ge]
                    == `L2_MSHR_STATE_PENDING);
        end
    endgenerate

    wire [3:0] l2_busy_cnt  = l2_busy[0] + l2_busy[1] + l2_busy[2] + l2_busy[3]
                            + l2_busy[4] + l2_busy[5] + l2_busy[6] + l2_busy[7];
    wire       l2_pool_full = (openpiton_l15l2_deadlock_ft.u_l2.mshr_empty_slots == 4'd0);

    // Pairwise duplicate detectors, register-free.  Bit 8*a+b is set when
    // entries a and b are both busy and collide; the diagonal is held at 0
    // and each unordered pair therefore appears twice, which is harmless.
    wire [63:0] l2_line_dup;
    wire [63:0] l2_setway_dup;
    generate
        for (ga = 0; ga < 8; ga = ga + 1) begin : g_dup_a
            for (gb = 0; gb < 8; gb = gb + 1) begin : g_dup_b
                assign l2_line_dup[8*ga + gb] = (ga == gb) ? 1'b0 :
                    (l2_busy[ga] && l2_busy[gb] &&
                     (l2_line_flat[34*ga +: 34] == l2_line_flat[34*gb +: 34]));
                assign l2_setway_dup[8*ga + gb] = (ga == gb) ? 1'b0 :
                    (l2_busy[ga] && l2_busy[gb] &&
                     (l2_key_flat[3*ga +: 3] == l2_key_flat[3*gb +: 3]) &&
                     (l2_way_flat[2*ga +: 2] == l2_way_flat[2*gb +: 2]));
            end
        end
    endgenerate

    // ---- the MSHR write port, after the pipe1 / pipe2 mux ------------------
    // This is the only place an entry's contents can move, so a lifecycle
    // obligation can be written here instead of against a remembered copy.
    wire        l2_wr_en  = openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.wr_data_en;
    wire [2:0]  l2_wr_idx = openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.wr_index_in;
    wire [33:0] l2_wr_line_in =
        openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.data_in[`L2_TAG_PLUS_INDEX];
    wire [33:0] l2_wr_line_msk =
        openpiton_l15l2_deadlock_ft.u_l2.mshr_wrap.data_mask_in[`L2_TAG_PLUS_INDEX];
    wire [33:0] l2_wr_line_old = l2_line_flat[34*l2_wr_idx +: 34];
    // the value the entry will hold after this masked write, computed the way
    // l2_mshr_wrap computes it
    wire [33:0] l2_wr_line_new = (l2_wr_line_old & ~l2_wr_line_msk)
                               | (l2_wr_line_in  &  l2_wr_line_msk);

    // =====================================================================
    // The L1.5 NOC1 command buffer, its own valid array and its own pointers.
    // =====================================================================
    wire       nb_push = openpiton_l15l2_deadlock_ft.u_l15.noc1buffer.l15_noc1buffer_req_val;
    wire       nb_pop  = openpiton_l15l2_deadlock_ft.u_l15.noc1buffer.noc1encoder_noc1buffer_req_ack;
    wire [2:0] nb_wr   = openpiton_l15l2_deadlock_ft.u_l15.noc1buffer.command_wrindex;
    wire [2:0] nb_rd   = openpiton_l15l2_deadlock_ft.u_l15.noc1buffer.command_rdindex;

    wire [7:0] nb_valid;
    generate
        for (ge = 0; ge < 8; ge = ge + 1) begin : g_nbv
            assign nb_valid[ge] =
                openpiton_l15l2_deadlock_ft.u_l15.noc1buffer.command_buffer_val[ge];
        end
    endgenerate

    wire [3:0] nb_occ = nb_valid[0] + nb_valid[1] + nb_valid[2] + nb_valid[3]
                      + nb_valid[4] + nb_valid[5] + nb_valid[6] + nb_valid[7];

    // The slots a FIFO of this occupancy would be holding, counted from the
    // design's own read pointer.  At occupancy 0 this is empty and at
    // occupancy 8 it is every slot, so the wrap case needs no special form.
    wire [7:0] nb_run;
    generate
        for (ge = 0; ge < 8; ge = ge + 1) begin : g_nbrun
            localparam [2:0] SLOT = ge;
            assign nb_run[ge] = ({1'b0, (SLOT - nb_rd)} < nb_occ);
        end
    endgenerate

    // =====================================================================
    // ENVIRONMENT-DERIVED.  The requests the memory responder has taken off
    // NOC2 and not yet begun to answer.  `q_wr_f`, `q_rd_f`, `hdr_q` and
    // `tx_state_f` are the formal top's existing registers; the head slot is
    // excluded once the responder starts driving its ack onto NOC3, which is
    // the moment the L2 learns of it.
    // =====================================================================
    wire       mem_tx        = (openpiton_l15l2_deadlock_ft.u_mem.tx_state_f != 2'd0);
    wire [3:0] mem_q_cnt     = openpiton_l15l2_deadlock_ft.u_mem.q_wr_f
                             - openpiton_l15l2_deadlock_ft.u_mem.q_rd_f;
    wire [3:0] mem_live_cnt  = mem_q_cnt - (mem_tx ? 4'd1 : 4'd0);
    wire [2:0] mem_live_base = openpiton_l15l2_deadlock_ft.u_mem.q_rd_f[2:0]
                             + (mem_tx ? 3'd1 : 3'd0);

    wire [7:0]  mem_live;
    wire [23:0] mem_id_flat;
    generate
        for (ge = 0; ge < 8; ge = ge + 1) begin : g_memq
            localparam [2:0] MSLOT = ge;
            wire [7:0] mid = openpiton_l15l2_deadlock_ft.u_mem.hdr_q[ge][`MSG_MSHRID];
            assign mem_id_flat[3*ge +: 3] = mid[2:0];
            assign mem_live[ge] = ({1'b0, (MSLOT - mem_live_base)} < mem_live_cnt);
        end
    endgenerate

    // two live requests collide when they name one MSHR entry, or when the
    // two entries they name carry one L2 set index
    wire [63:0] mem_key_dup;
    generate
        for (ga = 0; ga < 8; ga = ga + 1) begin : g_mdup_a
            for (gb = 0; gb < 8; gb = gb + 1) begin : g_mdup_b
                assign mem_key_dup[8*ga + gb] = (ga == gb) ? 1'b0 :
                    (mem_live[ga] && mem_live[gb] &&
                     ((mem_id_flat[3*ga +: 3] == mem_id_flat[3*gb +: 3]) ||
                      (l2_key_flat[3*mem_id_flat[3*ga +: 3] +: 3] ==
                       l2_key_flat[3*mem_id_flat[3*gb +: 3] +: 3])));
            end
        end
    endgenerate

    // the header flit of a memory request, framed by the formal top's own
    // NOC2 demultiplexer rather than by a framer written here
    wire mem_req_hdr = openpiton_l15l2_deadlock_ft.mem_req_val
                    && openpiton_l15l2_deadlock_ft.mem_req_rdy
                    && !openpiton_l15l2_deadlock_ft.n2_in_body_f;
    wire [2:0] mem_req_id = n2_mid[2:0];

    // =====================================================================
    // 1 -- MUTUAL EXCLUSION / ONE-HOT
    // =====================================================================
    T_MUTEX_L2_MSHR_LINE_ONEHOT: assert property (@(posedge clk)
        disable iff (!reset_n)
        (l2_line_dup == 64'd0));

    // ENVIRONMENT-DERIVED: the outstanding set is the formal top's memory
    // responder queue.  Changed from the parent: the set index is read from
    // the MSHR entry each request names, not from an address captured off
    // NOC2, because nothing here remembers a flit.
    T_MUTEX_MEM_OUTSTANDING_KEY_ONEHOT: assert property (@(posedge clk)
        disable iff (!reset_n)
        (mem_key_dup == 64'd0));

    // =====================================================================
    // 2 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_L2_MSHR_SETWAY_ONEHOT: assert property (@(posedge clk)
        disable iff (!reset_n)
        (l2_setway_dup == 64'd0));

    T_UNIQ_NOC1BUF_SLOT_NOT_OVERWRITTEN: assert property (@(posedge clk)
        disable iff (!reset_n)
        nb_push |-> (!nb_valid[nb_wr] || (nb_pop && (nb_rd == nb_wr))));

    // =====================================================================
    // 3 -- NO LOSS / CONSERVATION
    // =====================================================================
    // Changed from the parent: occupancy is no longer a shadow count.  The
    // claim is that the design's valid bits are exactly the run of slots its
    // own read pointer and its own population say they should be, so the
    // valid array and the two pointers cannot drift apart.
    T_CONSERV_NOC1BUF_OCC_EQ_VALIDS: assert property (@(posedge clk)
        disable iff (!reset_n)
        (nb_valid == nb_run));

    // Changed from the parent: pushes and pops are no longer accumulated in
    // counters of this file's own.  The conservation law is stated one cycle
    // at a time -- the population moves by exactly one on a push, by exactly
    // one the other way on a pop, and not at all otherwise -- which is the
    // same statement that nothing is lost or invented.
    T_CONSERV_NOC1BUF_PUSH_MINUS_POP: assert property (@(posedge clk)
        disable iff (!reset_n)
        (((nb_push && !nb_pop) |=> (nb_occ == ($past(nb_occ) + 4'd1))) and
         ((nb_pop && !nb_push) |=> ($past(nb_occ) == (nb_occ + 4'd1)))  and
         ((nb_push == nb_pop)  |=> (nb_occ == $past(nb_occ)))));

    // =====================================================================
    // 4 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    // ENVIRONMENT-DERIVED: the outstanding count is the formal top's memory
    // responder queue depth, less the request it has already begun to answer.
    T_BOUND_MEM_OUTSTANDING_LE_BUSY: assert property (@(posedge clk)
        disable iff (!reset_n)
        (mem_live_cnt <= l2_busy_cnt));

    // =====================================================================
    // 5 -- ALLOCATOR DISCIPLINE
    // =====================================================================
    // Changed from the parent: fullness is the design's own valid array.
    T_ALLOC_NOC1BUF_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
        disable iff (!reset_n)
        (nb_push && (nb_valid == 8'hff)) |-> nb_pop);

    // Changed from the parent: emptiness is judged by the design's own
    // pointers.  Stating it over the valid array instead would be trivial,
    // since noc1buffer gates the request it presents on
    // command_buffer_val[command_rdindex] combinationally.
    T_ALLOC_NOC1BUF_NO_POP_WHEN_EMPTY: assert property (@(posedge clk)
        disable iff (!reset_n)
        nb_pop |-> ((nb_rd != nb_wr) || (nb_valid == 8'hff)));

    // =====================================================================
    // 6 -- REQUEST / RESPONSE CORRESPONDENCE
    // =====================================================================
    T_REQRSP_MEM_REQ_HAS_BUSY_ENTRY: assert property (@(posedge clk)
        disable iff (!reset_n)
        mem_req_hdr |-> l2_busy[mem_req_id]);

    // =====================================================================
    // 7 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_NOC1_VAL_STABLE: assert property (@(posedge clk)
        disable iff (!reset_n)
        (n1_val && !n1_rdy) |=> n1_val);

    T_PROTO_NOC1_DATA_STABLE: assert property (@(posedge clk)
        disable iff (!reset_n)
        (n1_val && !n1_rdy) |=> $stable(n1_dat));

    // =====================================================================
    // 8 -- ARBITRATION FAIRNESS (bounded-safety form)
    // =====================================================================
    // Same bound as the parent, 192 cycles.  Written as consecutive
    // repetition instead of a saturating counter.
    T_FAIR_L15_NOC3_ADMITTED_WITHIN_N: assert property (@(posedge clk)
        disable iff (!reset_n)
        (l3_val && !l3_rdy)[*192] |=> !(l3_val && !l3_rdy));

    // =====================================================================
    // 9 -- BOUNDED RESPONSE (bounded-safety form)
    // =====================================================================
    // Changed from the parent: with no record of when each request left, the
    // obligation is written on the entry's own state.  An MSHR entry enters
    // PENDING when its memory ack has come back and leaves it when pipe1
    // retires it, and deallocation passes through INVAL, so a run of PENDING
    // on one entry is one request waiting.  Same bound, 128 cycles.
    T_BOUNDRSP_MEM_ROUND_TRIP_WITHIN_N: assert property (@(posedge clk)
        disable iff (!reset_n)
        ((((l2_pend[0])[*128]) |=> !l2_pend[0]) and
         (((l2_pend[1])[*128]) |=> !l2_pend[1]) and
         (((l2_pend[2])[*128]) |=> !l2_pend[2]) and
         (((l2_pend[3])[*128]) |=> !l2_pend[3]) and
         (((l2_pend[4])[*128]) |=> !l2_pend[4]) and
         (((l2_pend[5])[*128]) |=> !l2_pend[5]) and
         (((l2_pend[6])[*128]) |=> !l2_pend[6]) and
         (((l2_pend[7])[*128]) |=> !l2_pend[7])));

    // =====================================================================
    // 10 -- DEADLOCK FREEDOM (bounded-safety form)
    // =====================================================================
    // Same bound as the parent, 256 cycles.
    T_DEADLOCK_L2_MSHR_POOL_DRAINS_WITHIN_N: assert property (@(posedge clk)
        disable iff (!reset_n)
        (l2_pool_full[*256]) |=> !l2_pool_full);

    // =====================================================================
    // 11 -- LIFECYCLE / ACCESS CONTROL
    // =====================================================================
    // Changed from the parent: "outstanding to memory" is replaced by "busy",
    // which is the design's own word for it, and the write port watched is
    // the muxed one, so pipe2's writes are covered as well as pipe1's.  The
    // claim is that no write moves the line address of an entry that is
    // already allocated; allocation itself is excluded because the entry is
    // still INVAL in the cycle it is written.
    T_LIFECYCLE_MSHR_ENTRY_NOT_REWRITTEN_WHILE_OUTSTANDING: assert property (
        @(posedge clk) disable iff (!reset_n)
        (l2_wr_en && l2_busy[l2_wr_idx]) |-> (l2_wr_line_new == l2_wr_line_old));

    // Changed from the parent: the entry that "stayed outstanding" is the
    // entry that was busy last cycle and is busy now.  Deallocation passes
    // through INVAL, so that pair of conditions is the same allocation on
    // both cycles, and its CAM key may not have moved between them.
    T_LIFECYCLE_MSHR_KEY_STABLE_WHILE_OUTSTANDING: assert property (
        @(posedge clk) disable iff (!reset_n)
        ((!(l2_busy[0] && $past(l2_busy[0])) ||
          (l2_key_flat[ 0 +: 3] == $past(l2_key_flat[ 0 +: 3]))) &&
         (!(l2_busy[1] && $past(l2_busy[1])) ||
          (l2_key_flat[ 3 +: 3] == $past(l2_key_flat[ 3 +: 3]))) &&
         (!(l2_busy[2] && $past(l2_busy[2])) ||
          (l2_key_flat[ 6 +: 3] == $past(l2_key_flat[ 6 +: 3]))) &&
         (!(l2_busy[3] && $past(l2_busy[3])) ||
          (l2_key_flat[ 9 +: 3] == $past(l2_key_flat[ 9 +: 3]))) &&
         (!(l2_busy[4] && $past(l2_busy[4])) ||
          (l2_key_flat[12 +: 3] == $past(l2_key_flat[12 +: 3]))) &&
         (!(l2_busy[5] && $past(l2_busy[5])) ||
          (l2_key_flat[15 +: 3] == $past(l2_key_flat[15 +: 3]))) &&
         (!(l2_busy[6] && $past(l2_busy[6])) ||
          (l2_key_flat[18 +: 3] == $past(l2_key_flat[18 +: 3]))) &&
         (!(l2_busy[7] && $past(l2_busy[7])) ||
          (l2_key_flat[21 +: 3] == $past(l2_key_flat[21 +: 3])))));

    // =====================================================================
    // COVERS -- one or more per category above, showing that the scenario
    // each target constrains is reachable.  All of them are combinational
    // over the same registers the targets use.
    // =====================================================================
    C_MUTEX_TWO_L2_MSHR_BUSY: cover property (@(posedge clk)
        disable iff (!reset_n) (l2_busy_cnt >= 4'd2));
    C_MUTEX_FOUR_L2_MSHR_BUSY: cover property (@(posedge clk)
        disable iff (!reset_n) (l2_busy_cnt >= 4'd4));
    C_MUTEX_L2_MSHR_POOL_FULL: cover property (@(posedge clk)
        disable iff (!reset_n) l2_pool_full);

    C_UNIQ_NOC1BUF_PUSH: cover property (@(posedge clk)
        disable iff (!reset_n) nb_push);
    C_UNIQ_NOC1BUF_PUSH_AND_POP: cover property (@(posedge clk)
        disable iff (!reset_n) (nb_push && nb_pop));

    C_OCC_NOC1BUF_HALF: cover property (@(posedge clk)
        disable iff (!reset_n) (nb_occ >= 4'd4));
    C_OCC_NOC1BUF_FULL: cover property (@(posedge clk)
        disable iff (!reset_n) (nb_valid == 8'hff));
    C_OCC_NOC1BUF_WRAPPED: cover property (@(posedge clk)
        disable iff (!reset_n) ((nb_occ != 4'd0) && (nb_rd > nb_wr)));

    C_REQRSP_MEM_REQ_ISSUED: cover property (@(posedge clk)
        disable iff (!reset_n) mem_req_hdr);
    C_REQRSP_TWO_MEM_OUTSTANDING: cover property (@(posedge clk)
        disable iff (!reset_n) (mem_live_cnt >= 4'd2));
    C_REQRSP_FOUR_MEM_OUTSTANDING: cover property (@(posedge clk)
        disable iff (!reset_n) (mem_live_cnt >= 4'd4));

    C_PROTO_NOC1_BACKPRESSURE: cover property (@(posedge clk)
        disable iff (!reset_n) (n1_val && !n1_rdy));
    C_FAIR_L15_NOC3_BLOCKED_EIGHT: cover property (@(posedge clk)
        disable iff (!reset_n) (l3_val && !l3_rdy)[*8]);

    C_LIFECYCLE_MSHR_PENDING: cover property (@(posedge clk)
        disable iff (!reset_n) (l2_pend != 8'd0));
    C_LIFECYCLE_MSHR_WRITE_TO_BUSY: cover property (@(posedge clk)
        disable iff (!reset_n) (l2_wr_en && l2_busy[l2_wr_idx]));

endmodule

bind openpiton_l15l2_deadlock_ft l15_l2_targets l15_l2_targets (
    .clk(clk), .reset_n(reset_n));
