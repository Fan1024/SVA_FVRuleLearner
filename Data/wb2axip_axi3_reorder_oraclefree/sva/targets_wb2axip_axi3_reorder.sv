// ===========================================================================
// Candidate target assertions for wb2axip_axi3_reorder_oraclefree.
//
// ORACLE-FREE. There is no reference model in this file: no `always_ff`, no
// `always @`, no shadow counter, no arrival ring, no AW id queue, no packet
// framer, no saturating wait counter. Every declaration below is a `wire`
// whose value is a COMBINATIONAL FUNCTION OF THE DESIGN'S OWN STATE at the
// current cycle -- a mask, a population count, a bit-isolation -- and every
// assertion is a property of that state, of an SVA sampled value of it
// (`$past`, `$stable`, `$fell`), or of a bounded sequence over it.
//
// WHY. The parent package proves 44 of its 56 assertions against a reference
// model written in the same file. The modelling is the part we want to measure
// an agent doing, so a target set that ships the model measures the wrong
// thing. Here the agent gets the OBLIGATION without the machinery: the beat
// history, the per-ID arrival phase and the wait counters all have to come out
// of the agent's own FT notebook.
//
// WHAT THE DESIGN IS. `axi3reorder` with OPT_METHOD=1: a 16-station shift
// register holding every accepted W beat in ARRIVAL order (station 0 oldest),
// plus an 8-deep FIFO of accepted AW ids and one loaded `current_id`. A beat
// leaves from the LOWEST valid station whose `sr_id` equals `current_id`, and
// the stations above it shift down to close the hole. That is the whole AXI3
// story: responses reorder ACROSS ids, never WITHIN one, and the "never within
// one" is a structural fact about which station the design picks.
//
// WHAT THE ENVIRONMENT GUARANTEES. `ft/tb.sv` assumes AW/W stickiness and
// `A_FIXED_PACKET_LAST` -- every packet is exactly four beats per id, with
// WLAST on the fourth. Nothing constrains the ORDER of ids, nothing requires a
// packet's AW to arrive before its W beats, and M_AXI_WREADY is free.
//
// THE SHAPE OF THE HARD ROWS. Because every packet is four beats, the beats of
// one id resident in the shift register are a CONTIGUOUS RUN of that id's
// arrival stream: some tail of a packet, then whole packets, then some head of
// a packet. Writing L for that id's live station count and c for how many of
// those stations carry WLAST, the run structure forces
//
//     head + tail + 4c == L + 3      (c > 0),      L <= 3   (c == 0)
//
// with head <= 3 and tail <= 3, where head/tail count the live stations below
// the lowest and above the highest WLAST station of that id. Those identities
// are stated here over `sr_valid`, `sr_id` and `sr_last` alone. PROVING them
// needs the per-id arrival phase, which is NOT a design register -- that is
// the modelling the agent has to supply, and it is why these rows are the ones
// worth a screen slot.
//
// Configuration, from `ft/tb.sv`: 2-bit ids, 8-bit data, one strobe bit, an
// 8-deep AW FIFO, 16 shift-register stations, OPT_LOWPOWER=0.
// ===========================================================================

`default_nettype none

module axi3_reorder_targets (input wire clock, input wire reset);

    localparam integer NSREG = 16;

    // Drain windows. Under a held M_AXI_WREADY with no new W beat and no new
    // AW id, the design removes one beat per cycle while it has a beat of the
    // current id (at most 16 such cycles) and consumes one AW FIFO entry per
    // cycle while it has none loaded (at most 9). N_DRAIN covers both plus
    // headroom; N_WBLOCK is the AW-only half of the same argument.
    localparam integer N_DRAIN  = 28;
    localparam integer N_WBLOCK = 12;

    // ---------------------------------------------------------- port aliases
    wire       aw_val  = testbench.s_awvalid;
    wire       aw_rdy  = testbench.s_awready;
    wire       push_aw = aw_val && aw_rdy;

    wire       w_val   = testbench.s_wvalid;
    wire       w_rdy   = testbench.s_wready;
    wire [1:0] w_id    = testbench.s_wid;
    wire       push_w  = w_val && w_rdy;

    wire       m_val   = testbench.m_wvalid;
    wire       m_rdy   = testbench.m_wready;
    wire [1:0] m_id    = testbench.m_wid;
    wire [7:0] m_dat   = testbench.m_wdata;
    wire       m_stb   = testbench.m_wstrb;
    wire       m_lst   = testbench.m_wlast;
    wire       pop_w   = m_val && m_rdy;

    // ------------------------------------- the design's own state, unaltered
    wire [15:0] sr_valid   = testbench.dut.SHIFT_REGISTER.sr_valid;
    wire [15:0] sr_last    = testbench.dut.SHIFT_REGISTER.sr_last;
    wire [15:0] sr_adv     = testbench.dut.SHIFT_REGISTER.sr_advance;
    wire [15:0] sr_wrt     = testbench.dut.SHIFT_REGISTER.sr_write;
    wire        known_next = testbench.dut.SHIFT_REGISTER.known_next;
    wire [3:0]  sr_next    = testbench.dut.SHIFT_REGISTER.sr_next;
    wire        cid_valid  = testbench.dut.cid_valid;
    wire [1:0]  current_id = testbench.dut.current_id;
    wire        rd_awid    = testbench.dut.read_awid_fifo;
    wire        rd_beat    = testbench.dut.read_beat_fifo;
    wire        out_free   = !m_val || m_rdy;

    wire [3:0]  awf_fill   = testbench.dut.AWFIFO.awidfifo.o_fill;
    wire [3:0]  awf_wr     = testbench.dut.AWFIFO.awidfifo.wr_addr;
    wire [3:0]  awf_rd     = testbench.dut.AWFIFO.awidfifo.rd_addr;
    wire        awf_empty  = testbench.dut.AWFIFO.awidfifo.o_empty;
    wire        awf_full   = testbench.dut.AWFIFO.awidfifo.o_full;
    wire        awf_pop    = rd_awid && !awf_empty;

    // =====================================================================
    // COMBINATIONAL VIEWS OF THAT STATE.  Nothing here holds a value across a
    // cycle; each wire is a function of the same cycle's design registers.
    // =====================================================================
    wire [7:0] sr_fill = 8'(unsigned'($countones(sr_valid)));

    wire [15:0] live     [0:3];   // live stations carrying this id
    wire [15:0] lastm    [0:3];   // of those, the ones carrying WLAST
    wire [7:0]  n_live   [0:3];   // L
    wire [7:0]  n_last   [0:3];   // c
    wire [7:0]  n_head   [0:3];   // live stations BELOW this id's lowest WLAST
    wire [7:0]  n_tail   [0:3];   // live stations ABOVE this id's highest WLAST
    wire [7:0]  n_live_o [0:3];   // L, counting the master output register
    wire [7:0]  n_last_o [0:3];   // c, counting the master output register

    wire [3:0] id_frame_balance_ok;
    wire [3:0] id_frame_balance_out_ok;
    wire [3:0] id_frame_exact_ok;
    wire [3:0] id_head_run_ok;
    wire [3:0] id_tail_run_ok;
    wire [3:0] id_last_count_ok;
    wire [3:0] id_resume_ok;
    wire [3:0] id_open_run_ok;
    wire [3:0] id_two_packets;    // cover support

    genvar gk, gi;
    generate
        for (gk = 0; gk < 4; gk = gk + 1) begin : PERID
            for (gi = 0; gi < NSREG; gi = gi + 1) begin : STATION
                assign live[gk][gi] = sr_valid[gi]
                    && (testbench.dut.SHIFT_REGISTER.sr_id[gi] == gk[1:0]);
            end
            assign lastm[gk] = live[gk] & sr_last;

            // lowest set bit of `lastm`, and the mask of everything under it
            wire [15:0] lo_iso   = lastm[gk] & (~lastm[gk] + 16'd1);
            wire [15:0] below_lo = lo_iso - 16'd1;
            // smear the highest set bit downwards, then take what is above it
            wire [15:0] sm1      = lastm[gk] | (lastm[gk] >> 1);
            wire [15:0] sm2      = sm1 | (sm1 >> 2);
            wire [15:0] sm3      = sm2 | (sm2 >> 4);
            wire [15:0] smear    = sm3 | (sm3 >> 8);
            wire [15:0] above_hi = live[gk] & ~smear;

            assign n_live[gk] = 8'(unsigned'($countones(live[gk])));
            assign n_last[gk] = 8'(unsigned'($countones(lastm[gk])));
            assign n_head[gk] = 8'(unsigned'($countones(live[gk] & below_lo)));
            assign n_tail[gk] = 8'(unsigned'($countones(above_hi)));

            wire out_here = m_val && (m_id == gk[1:0]);
            assign n_live_o[gk] = n_live[gk] + (out_here ? 8'd1 : 8'd0);
            assign n_last_o[gk] = n_last[gk]
                                + ((out_here && m_lst) ? 8'd1 : 8'd0);

            // |L - 4c| <= 3
            assign id_frame_balance_ok[gk] =
                   ((n_live[gk] + 8'd3) >= (n_last[gk] << 2))
                && (((n_last[gk] << 2) + 8'd3) >= n_live[gk]);
            assign id_frame_balance_out_ok[gk] =
                   ((n_live_o[gk] + 8'd3) >= (n_last_o[gk] << 2))
                && (((n_last_o[gk] << 2) + 8'd3) >= n_live_o[gk]);
            // head + tail + 4c == L + 3, i.e. the WLAST stations of this id
            // sit exactly four beats apart
            assign id_frame_exact_ok[gk] = (n_last[gk] == 8'd0)
                ? (n_live[gk] <= 8'd3)
                : ((n_head[gk] + n_tail[gk] + (n_last[gk] << 2))
                        == (n_live[gk] + 8'd3));
            assign id_head_run_ok[gk] =
                (n_last[gk] == 8'd0) || (n_head[gk] <= 8'd3);
            assign id_tail_run_ok[gk] =
                (n_last[gk] == 8'd0) || (n_tail[gk] <= 8'd3);
            assign id_last_count_ok[gk] = (n_last[gk] <= 8'd4);
            // the master port is holding this id's WLAST, so what is left of
            // this id in the shift register starts a fresh packet
            assign id_resume_ok[gk] = !(out_here && m_lst)
                || ((n_last[gk] == 8'd0) ? (n_live[gk] <= 8'd3)
                                         : (n_head[gk] == 8'd3));
            // the master port is mid-packet for this id, so what is left of it
            // is strictly inside the packet
            assign id_open_run_ok[gk] = !(out_here && !m_lst)
                || ((n_last[gk] == 8'd0) ? (n_live[gk] <= 8'd2)
                                         : (n_head[gk] <= 8'd2));

            assign id_two_packets[gk] = (n_last[gk] >= 8'd2);
        end
    endgenerate

    wire [63:0] live_all = { live[3], live[2], live[1], live[0] };
    wire [7:0]  n_last_total = 8'(unsigned'($countones(sr_valid & sr_last)));

    wire [15:0] live_cur = (current_id == 2'd0) ? live[0]
                         : (current_id == 2'd1) ? live[1]
                         : (current_id == 2'd2) ? live[2] : live[3];
    wire        cur_match = cid_valid && (live_cur != 16'd0);

    // the design is wedged: it has a packet loaded but no beat of it, or no
    // packet loaded and no AW id left to load
    wire blocked = (cid_valid && (live_cur == 16'd0))
                || (!cid_valid && awf_empty);

    // =====================================================================
    // 1 -- END-TO-END ORDERING.  AXI3 reorders across ids and never within
    // one; every row here is that rule stated over the design's own stations.
    // =====================================================================
    T_ORDER_ID_FRAME_BALANCE: assert property (@(posedge clock) disable iff (reset) (id_frame_balance_ok == 4'hf));

    T_ORDER_ID_FRAME_BALANCE_WITH_OUT_REG: assert property (@(posedge clock) disable iff (reset) (id_frame_balance_out_ok == 4'hf));

    T_ORDER_ID_LAST_SPACING_EXACT: assert property (@(posedge clock) disable iff (reset) (id_frame_exact_ok == 4'hf));

    T_ORDER_ID_HEAD_RUN_LE_THREE: assert property (@(posedge clock) disable iff (reset) (id_head_run_ok == 4'hf));

    T_ORDER_ID_TAIL_RUN_LE_THREE: assert property (@(posedge clock) disable iff (reset) (id_tail_run_ok == 4'hf));

    T_ORDER_ID_RESUMES_AT_PACKET_START: assert property (@(posedge clock) disable iff (reset) (id_resume_ok == 4'hf));

    T_ORDER_OPEN_PACKET_RESIDUE_BOUNDED: assert property (@(posedge clock) disable iff (reset) (id_open_run_ok == 4'hf));

    T_ORDER_SHIFT_STARTS_AT_THE_OLDEST_OF_THE_ID: assert property (@(posedge clock) disable iff (reset) rd_beat |-> (sr_adv == (sr_valid & (16'hffff << sr_next))));

    T_ORDER_CURRENT_ID_STABLE_WITHIN_PACKET: assert property (@(posedge clock) disable iff (reset) (cid_valid && !(known_next && sr_last[sr_next])) |=> (cid_valid && $stable(current_id)));

    T_ORDER_OUT_ID_IS_CURRENT_WHILE_PACKET_OPEN: assert property (@(posedge clock) disable iff (reset) (m_val && !m_lst) |-> (m_id == current_id));

    // =====================================================================
    // 2 -- DATA INTEGRITY.  WLAST is a payload field; where it may sit inside
    // an id's residue, and that nothing rewrites a parked beat.
    // =====================================================================
    T_DATA_ID_LAST_COUNT_LE_FOUR: assert property (@(posedge clock) disable iff (reset) (id_last_count_ok == 4'hf));

    T_DATA_TOTAL_LAST_COUNT_LE_SEVEN: assert property (@(posedge clock) disable iff (reset) (n_last_total <= 8'd7));

    T_DATA_SR_HELD_WHILE_OUTPUT_STALLED: assert property (@(posedge clock) disable iff (reset) (m_val && !m_rdy && !push_w) |=> ($stable(sr_valid) && $stable(live_all) && ((sr_last & sr_valid) == $past(sr_last & sr_valid))));

    // =====================================================================
    // 3 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_SR_WRITE_IS_ONEHOT: assert property (@(posedge clock) disable iff (reset) push_w |-> $onehot(sr_wrt));

    T_UNIQ_SR_WRITE_IDLE_WITHOUT_PUSH: assert property (@(posedge clock) disable iff (reset) !push_w |-> (sr_wrt == 16'd0));

    T_UNIQ_SR_WRITE_SITS_ABOVE_THE_RUN: assert property (@(posedge clock) disable iff (reset) (((sr_wrt << 1) & sr_valid) == 16'd0));

    T_UNIQ_AT_MOST_ONE_BEAT_LEAVES_PER_CYCLE: assert property (@(posedge clock) disable iff (reset) 1'b1 |=> ((sr_fill + 8'd1) >= $past(sr_fill)));

    // =====================================================================
    // 4 -- NO LOSS / CONSERVATION
    // =====================================================================
    T_CONSERV_SR_FILL_TRACKS_HANDSHAKES: assert property (@(posedge clock) disable iff (reset) 1'b1 |=> (sr_fill == ($past(sr_fill) + {7'd0, $past(push_w)} - {7'd0, $past(rd_beat)})));

    T_CONSERV_AWFIFO_FILL_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset) (awf_fill == (awf_wr - awf_rd)));

    T_CONSERV_AWFIFO_FILL_TRACKS_HANDSHAKES: assert property (@(posedge clock) disable iff (reset) 1'b1 |=> (awf_fill == ($past(awf_fill) + {3'd0, $past(push_aw)} - {3'd0, $past(awf_pop)})));

    T_CONSERV_AW_POP_COINCIDES_WITH_LAST_BEAT: assert property (@(posedge clock) disable iff (reset) (cid_valid && rd_awid) |=> (m_val && m_lst));

    // =====================================================================
    // 5 -- MUTUAL EXCLUSION / ONE-HOT
    // =====================================================================
    T_MUTEX_SR_VALID_IS_CONTIGUOUS: assert property (@(posedge clock) disable iff (reset) ((sr_valid & (sr_valid + 16'd1)) == 16'd0));

    T_MUTEX_SR_ADVANCE_WITHIN_VALID: assert property (@(posedge clock) disable iff (reset) ((sr_adv & ~sr_valid) == 16'd0));

    T_MUTEX_SR_ADVANCE_IS_UPWARD_CLOSED: assert property (@(posedge clock) disable iff (reset) (((sr_adv << 1) & sr_valid & ~sr_adv) == 16'd0));

    T_MUTEX_SR_ADVANCE_IDLE_WITHOUT_READ: assert property (@(posedge clock) disable iff (reset) !rd_beat |-> (sr_adv == 16'd0));

    T_MUTEX_SR_ADVANCE_NONEMPTY_ON_READ: assert property (@(posedge clock) disable iff (reset) rd_beat |-> (sr_adv != 16'd0));

    // =====================================================================
    // 6 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    T_BOUND_AWFIFO_FILL_LE_EIGHT: assert property (@(posedge clock) disable iff (reset) (awf_fill <= 4'd8));

    T_BOUND_AWFIFO_EMPTY_IFF_FILL_ZERO: assert property (@(posedge clock) disable iff (reset) (awf_empty == (awf_fill == 4'd0)));

    // =====================================================================
    // 7 -- ALLOCATOR DISCIPLINE
    // =====================================================================
    T_ALLOC_NO_W_ACCEPT_WHEN_SR_FULL: assert property (@(posedge clock) disable iff (reset) (sr_valid == 16'hffff) |-> !push_w);

    T_ALLOC_NO_AW_ACCEPT_WHEN_FIFO_FULL: assert property (@(posedge clock) disable iff (reset) awf_full |-> !push_aw);

    T_ALLOC_WRITE_LANDS_AT_THE_TOP_OF_THE_RUN: assert property (@(posedge clock) disable iff (reset) push_w |-> (sr_wrt == (rd_beat ? ((sr_valid + 16'd1) >> 1) : (sr_valid + 16'd1))));

    // =====================================================================
    // 8 -- REQUEST / RESPONSE CORRESPONDENCE
    // =====================================================================
    T_REQRSP_OUT_BEAT_WITHOUT_CID_IS_LAST: assert property (@(posedge clock) disable iff (reset) (m_val && !cid_valid) |-> m_lst);

    T_REQRSP_CID_RELOADS_WHEN_AW_QUEUED: assert property (@(posedge clock) disable iff (reset) (!cid_valid && !awf_empty && out_free) |=> cid_valid);

    T_REQRSP_CID_STAYS_CLEAR_WHEN_AW_QUEUE_EMPTY: assert property (@(posedge clock) disable iff (reset) (!cid_valid && awf_empty) |=> !cid_valid);

    // =====================================================================
    // 9 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_OUT_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (m_val && !m_rdy) |=> m_val);

    T_PROTO_OUT_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (m_val && !m_rdy) |=> ($stable(m_dat) && $stable(m_stb) && $stable(m_lst) && $stable(m_id)));

    T_PROTO_W_PORT_REFUSES_ONLY_WHEN_SR_FULL: assert property (@(posedge clock) disable iff (reset) !w_rdy |-> (sr_valid == 16'hffff));

    T_PROTO_AW_PORT_REFUSES_ONLY_WHEN_FIFO_FULL: assert property (@(posedge clock) disable iff (reset) !aw_rdy |-> (awf_fill == 4'd8));

    // =====================================================================
    // 10 -- BOUNDED RESPONSE.  Bounded windows, written as SVA sequences over
    // the design's own signals rather than as saturating model counters.
    // =====================================================================
    T_BOUNDRSP_MATCHED_ID_LOADS_NEXT_CYCLE: assert property (@(posedge clock) disable iff (reset) (cur_match && out_free) |=> m_val);

    T_BOUNDRSP_SR_DRAINS_UNDER_READY: assert property (@(posedge clock) disable iff (reset) (m_rdy && !push_w && !push_aw)[*N_DRAIN] |-> !cur_match);

    // =====================================================================
    // 11 -- DEADLOCK FREEDOM
    // =====================================================================
    T_DEADLOCK_AW_QUEUE_EMPTY_OR_BLOCKED_ON_ID: assert property (@(posedge clock) disable iff (reset) (m_rdy && !push_w && !push_aw)[*N_DRAIN] |-> (awf_empty || (cid_valid && (live_cur == 16'd0))));

    T_DEADLOCK_W_PORT_BLOCKED_ONLY_BY_MISSING_ID: assert property (@(posedge clock) disable iff (reset) (m_rdy && !w_rdy && !push_aw)[*N_WBLOCK] |-> blocked);

    // =====================================================================
    // 12 -- RESET / INITIALISATION.  `$fell(reset)` replaces the parent's
    // `after_reset` register; a sampled value function is not a model.
    // =====================================================================
    T_RESET_SHIFT_REGISTER_EMPTY: assert property (@(posedge clock) disable iff (reset) $fell(reset) |-> ((sr_valid == 16'd0) && !m_val));

    T_RESET_AW_TRACKING_EMPTY: assert property (@(posedge clock) disable iff (reset) $fell(reset) |-> ((awf_fill == 4'd0) && (awf_wr == awf_rd) && awf_empty && !cid_valid));

    T_RESET_BOTH_SLAVE_PORTS_READY: assert property (@(posedge clock) disable iff (reset) $fell(reset) |-> (aw_rdy && w_rdy));

    // =====================================================================
    // COVERS -- the states the rows above are about, so a screen that proves
    // everything vacuously is visible as such.
    // =====================================================================
    C_SR_FULL: cover property (@(posedge clock) disable iff (reset) (sr_valid == 16'hffff));
    C_SR_HOLDS_EIGHT: cover property (@(posedge clock) disable iff (reset) (sr_fill >= 8'd8));

    C_TWO_IDS_LIVE: cover property (@(posedge clock) disable iff (reset) ((live[0] != 16'd0) && (live[1] != 16'd0)));
    C_THREE_IDS_LIVE: cover property (@(posedge clock) disable iff (reset) ((live[0] != 16'd0) && (live[1] != 16'd0) && (live[2] != 16'd0)));

    C_ID_HOLDS_TWO_PACKETS: cover property (@(posedge clock) disable iff (reset) (id_two_packets != 4'd0));
    C_FOUR_LAST_BEATS_RESIDENT: cover property (@(posedge clock) disable iff (reset) (n_last_total >= 8'd4));

    // the reorder itself: the beat that leaves is NOT the oldest beat overall
    C_REORDER_PULLS_ABOVE_STATION_ZERO: cover property (@(posedge clock) disable iff (reset) (rd_beat && (sr_next != 4'd0)));
    C_REORDER_PULLS_DEEP: cover property (@(posedge clock) disable iff (reset) (rd_beat && (sr_next >= 4'd4)));

    C_AWFIFO_FULL: cover property (@(posedge clock) disable iff (reset) (awf_fill == 4'd8));
    C_AW_PORT_BLOCKED: cover property (@(posedge clock) disable iff (reset) (aw_val && !aw_rdy));
    C_W_PORT_BLOCKED: cover property (@(posedge clock) disable iff (reset) (w_val && !w_rdy));
    C_OUT_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (m_val && !m_rdy));

    C_PACKET_LAST_DELIVERED: cover property (@(posedge clock) disable iff (reset) (pop_w && m_lst));
    C_BEATS_PARKED_WITH_NO_PACKET_LOADED: cover property (@(posedge clock) disable iff (reset) (!cid_valid && (sr_valid != 16'd0)));
    C_W_ID_DIFFERS_FROM_CURRENT: cover property (@(posedge clock) disable iff (reset) (push_w && cid_valid && (w_id != current_id)));

    C_DRAIN_WINDOW_OPENS: cover property (@(posedge clock) disable iff (reset) (m_rdy && !push_w && !push_aw)[*12]);
    C_W_BLOCK_WINDOW_OPENS: cover property (@(posedge clock) disable iff (reset) (m_rdy && !w_rdy && !push_aw)[*6]);

endmodule

`default_nettype wire

bind testbench axi3_reorder_targets axi3_reorder_targets (
    .clock(clock), .reset(reset));
