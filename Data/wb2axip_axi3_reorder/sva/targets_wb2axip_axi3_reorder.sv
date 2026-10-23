// ===========================================================================
// Candidate target assertions for wb2axip_axi3_reorder.
//
// Bound into `testbench`, so every reference below is a hierarchical name from
// the formal top.  Nothing here is an assumption.
//
// The oracle is INDEPENDENT of `ft/tb.sv`'s four per-ID reference rings, and
// is deliberately a DIFFERENT SHAPE: one 32-entry ARRIVAL ring shared by every
// ID, in the order the W beats were accepted, each entry carrying its ID, its
// payload, its beat position inside its packet and a live bit.  The beat the
// reorderer presents for an ID must be the OLDEST LIVE ENTRY OF THAT ID, found
// by walking the ring from its oldest slot -- which is per-ID FIFO order
// stated without a per-ID pointer.
//
// Alongside it:
//
//   * a 16-entry AW ID queue, pushed when an AW address is accepted and popped
//     when a packet's last beat is accepted at the master port.  Packet order
//     is this queue, not the design's `current_id`.
//   * per-ID live counts and a packet framer at the master port, both this
//     file's own arithmetic.
//   * saturating wait counters, which is how a bounded-response / deadlock
//     obligation is written as a safety property under FRA.
//
// Configuration, from `ft/tb.sv`: OPT_METHOD=1 (the 16-station shift
// register), 2-bit IDs, 8-bit data, an 8-deep AW FIFO, and an environment that
// makes every packet exactly four beats per ID.
// ===========================================================================

`default_nettype none

module axi3_reorder_targets (input wire clock, input wire reset);

    localparam integer AR    = 32;   // arrival ring entries
    localparam integer AWQ   = 16;   // AW id queue entries
    localparam integer NSREG = 16;   // shift register stations

    localparam [7:0] N_HEAD_STALL = 8'd8;
    localparam [7:0] N_AW_LOAD    = 8'd8;
    localparam [7:0] N_NO_MOVE    = 8'd16;
    localparam [7:0] N_AW_BLOCK   = 8'd24;
    localparam [7:0] CTR_MAX      = 8'd255;

    // ------------------------------------------------------------- aliases
    wire       aw_val = testbench.s_awvalid;
    wire       aw_rdy = testbench.s_awready;
    wire [1:0] aw_id  = testbench.s_awid;
    wire       push_aw = aw_val && aw_rdy;

    wire       w_val  = testbench.s_wvalid;
    wire       w_rdy  = testbench.s_wready;
    wire [1:0] w_id   = testbench.s_wid;
    wire [7:0] w_dat  = testbench.s_wdata;
    wire       w_stb  = testbench.s_wstrb;
    wire       w_lst  = testbench.s_wlast;
    wire       push_w = w_val && w_rdy;

    wire       m_val  = testbench.m_wvalid;
    wire       m_rdy  = testbench.m_wready;
    wire [1:0] m_id   = testbench.m_wid;
    wire [7:0] m_dat  = testbench.m_wdata;
    wire       m_stb  = testbench.m_wstrb;
    wire       m_lst  = testbench.m_wlast;
    wire       pop_w  = m_val && m_rdy;
    wire       pop_aw = pop_w && m_lst;

    // design state
    wire [NSREG-1:0] sr_valid  = testbench.dut.SHIFT_REGISTER.sr_valid;
    wire             cid_valid = testbench.dut.cid_valid;
    wire [1:0]       current_id = testbench.dut.current_id;
    wire [3:0]       awf_fill  = testbench.dut.AWFIFO.awidfifo.o_fill;
    wire [3:0]       awf_wr    = testbench.dut.AWFIFO.awidfifo.wr_addr;
    wire [3:0]       awf_rd    = testbench.dut.AWFIFO.awidfifo.rd_addr;

    // =====================================================================
    // ORACLE -- one arrival ring for every ID, plus an AW id queue
    // =====================================================================
    reg [1:0] ar_id  [0:AR-1];
    reg [7:0] ar_dat [0:AR-1];
    reg       ar_stb [0:AR-1];
    reg       ar_lst [0:AR-1];
    reg [1:0] ar_pos [0:AR-1];
    reg       ar_liv [0:AR-1];
    reg [4:0] ar_wr;
    reg [5:0] ar_occ;

    reg [1:0] awq_id [0:AWQ-1];
    reg [3:0] awq_wr, awq_rd;
    reg [4:0] awq_occ;

    reg [5:0] id_live [0:3];
    reg [1:0] in_beat [0:3];

    reg [1:0] out_beat;
    reg       out_pkt_active;
    reg [1:0] out_pkt_id;

    reg [15:0] w_in_cnt, w_out_cnt, aw_in_cnt, aw_out_cnt;

    reg [7:0] head_stall_ctr;
    reg [7:0] aw_load_ctr;
    reg [7:0] no_move_ctr;
    reg [7:0] aw_block_ctr;
    reg       after_reset;
    reg       seen_two_ids_live;

    // ------------------------- the oldest live arrival entry of the ID the
    // ------------------------- master port is presenting
    reg       first_found;
    reg [4:0] first_idx;
    reg [4:0] scan_ix;
    integer   j;
    always @* begin
        first_found = 1'b0;
        first_idx   = 5'd0;
        for (j = 0; j < AR; j = j + 1) begin
            scan_ix = ar_wr + j[4:0];
            if (!first_found && ar_liv[scan_ix] && (ar_id[scan_ix] == m_id))
                begin
                    first_found = 1'b1;
                    first_idx   = scan_ix;
                end
        end
    end

    // shift-register population, and the sum of the per-ID live counts
    reg [5:0] sr_fill;
    reg [7:0] live_sum;
    integer   k;
    always @* begin
        sr_fill = 6'd0;
        for (k = 0; k < NSREG; k = k + 1)
            if (sr_valid[k])
                sr_fill = sr_fill + 6'd1;
        live_sum = 8'd0;
        for (k = 0; k < 4; k = k + 1)
            live_sum = live_sum + {2'd0, id_live[k]};
    end

    wire [1:0] head_id      = awq_id[awq_rd];
    wire       head_has_beat = (awq_occ != 5'd0) && (id_live[head_id] != 6'd0);
    wire [3:0] awq_rd_next  = awq_rd + 4'd1;
    wire [1:0] expect_cid   = (m_val && m_lst) ? awq_id[awq_rd_next]
                                               : awq_id[awq_rd];

    // ------------------------------------------------------- oracle update
    integer u;
    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            ar_wr <= 5'd0;
            ar_occ <= 6'd0;
            awq_wr <= 4'd0; awq_rd <= 4'd0; awq_occ <= 5'd0;
            out_beat <= 2'd0;
            out_pkt_active <= 1'b0;
            out_pkt_id <= 2'd0;
            w_in_cnt <= 16'd0; w_out_cnt <= 16'd0;
            aw_in_cnt <= 16'd0; aw_out_cnt <= 16'd0;
            head_stall_ctr <= 8'd0;
            aw_load_ctr <= 8'd0;
            no_move_ctr <= 8'd0;
            aw_block_ctr <= 8'd0;
            seen_two_ids_live <= 1'b0;
            for (u = 0; u < 4; u = u + 1) begin
                id_live[u] <= 6'd0;
                in_beat[u] <= 2'd0;
            end
            for (u = 0; u < AR; u = u + 1)
                ar_liv[u] <= 1'b0;
        end else begin
            // W beats, in arrival order
            if (push_w) begin
                ar_id[ar_wr]  <= w_id;
                ar_dat[ar_wr] <= w_dat;
                ar_stb[ar_wr] <= w_stb;
                ar_lst[ar_wr] <= w_lst;
                ar_pos[ar_wr] <= in_beat[w_id];
                ar_liv[ar_wr] <= 1'b1;
                ar_wr <= ar_wr + 5'd1;
                in_beat[w_id] <= w_lst ? 2'd0 : (in_beat[w_id] + 2'd1);
                if (w_in_cnt != 16'hffff)
                    w_in_cnt <= w_in_cnt + 16'd1;
            end
            if (pop_w && first_found)
                ar_liv[first_idx] <= 1'b0;
            ar_occ <= ar_occ + {5'd0, push_w} - {5'd0, pop_w};

            for (u = 0; u < 4; u = u + 1)
                id_live[u] <= id_live[u]
                    + {5'd0, (push_w && (w_id == u[1:0]))}
                    - {5'd0, (pop_w  && (m_id == u[1:0]))};
            if ((id_live[0] != 6'd0) && (id_live[1] != 6'd0))
                seen_two_ids_live <= 1'b1;

            // AW ids, in acceptance order
            if (push_aw) begin
                awq_id[awq_wr] <= aw_id;
                awq_wr <= awq_wr + 4'd1;
                if (aw_in_cnt != 16'hffff)
                    aw_in_cnt <= aw_in_cnt + 16'd1;
            end
            if (pop_aw) begin
                awq_rd <= awq_rd + 4'd1;
                if (aw_out_cnt != 16'hffff)
                    aw_out_cnt <= aw_out_cnt + 16'd1;
            end
            awq_occ <= awq_occ + {4'd0, push_aw} - {4'd0, pop_aw};

            // the packet framer at the master port
            if (pop_w) begin
                if (w_out_cnt != 16'hffff)
                    w_out_cnt <= w_out_cnt + 16'd1;
                if (!out_pkt_active) begin
                    out_pkt_id     <= m_id;
                    out_pkt_active <= !m_lst;
                    out_beat       <= m_lst ? 2'd0 : 2'd1;
                end else if (m_lst) begin
                    out_pkt_active <= 1'b0;
                    out_beat       <= 2'd0;
                end else begin
                    out_beat       <= out_beat + 2'd1;
                end
            end

            // bounded response: the head packet's ID has a beat inside the
            // design and the master port is ready, but nothing is delivered
            if (!head_has_beat || !m_rdy || pop_w)
                head_stall_ctr <= 8'd0;
            else if (head_stall_ctr != CTR_MAX)
                head_stall_ctr <= head_stall_ctr + 8'd1;

            // bounded response: an accepted AW is not yet the design's
            // current packet
            if ((awq_occ == 5'd0) || cid_valid || !m_rdy || pop_aw)
                aw_load_ctr <= 8'd0;
            else if (aw_load_ctr != CTR_MAX)
                aw_load_ctr <= aw_load_ctr + 8'd1;

            // deadlock: the head packet can be served, the master port is
            // ready, and nothing moves at any boundary
            if (!head_has_beat || !m_rdy || pop_w || push_w || push_aw)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            // deadlock: the AW port is blocked while the head packet can be
            // drained
            if (!aw_val || aw_rdy || !m_rdy || !head_has_beat)
                aw_block_ctr <= 8'd0;
            else if (aw_block_ctr != CTR_MAX)
                aw_block_ctr <= aw_block_ctr + 8'd1;
        end
    end

    // =====================================================================
    // 1 -- END-TO-END ORDERING
    // =====================================================================
    T_ORDER_OUT_BEAT_IS_OLDEST_LIVE_OF_ID: assert property (@(posedge clock) disable iff (reset) (pop_w && first_found) |-> (m_dat == ar_dat[first_idx]));

    T_ORDER_OUT_ID_IS_AW_QUEUE_HEAD: assert property (@(posedge clock) disable iff (reset) (m_val && (awq_occ != 5'd0)) |-> (m_id == awq_id[awq_rd]));

    T_ORDER_OUT_LAST_ON_FOURTH_BEAT: assert property (@(posedge clock) disable iff (reset) (pop_w && m_lst) |-> (out_beat == 2'd3));

    T_ORDER_OUT_BEAT_POSITION_MATCHES_ARRIVAL: assert property (@(posedge clock) disable iff (reset) (pop_w && first_found) |-> (out_beat == ar_pos[first_idx]));

    // =====================================================================
    // 2 -- DATA INTEGRITY
    // =====================================================================
    T_DATA_OUT_STRB_MATCHES_ARRIVAL: assert property (@(posedge clock) disable iff (reset) (pop_w && first_found) |-> (m_stb == ar_stb[first_idx]));

    T_DATA_OUT_LAST_MATCHES_ARRIVAL: assert property (@(posedge clock) disable iff (reset) (pop_w && first_found) |-> (m_lst == ar_lst[first_idx]));

    // =====================================================================
    // 3 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_OUT_BEAT_WAS_ACCEPTED: assert property (@(posedge clock) disable iff (reset) pop_w |-> first_found);

    T_UNIQ_ARRIVAL_SLOT_NOT_LIVE_ON_PUSH: assert property (@(posedge clock) disable iff (reset) push_w |-> !ar_liv[ar_wr]);

    T_UNIQ_OUT_COUNT_LE_IN_COUNT: assert property (@(posedge clock) disable iff (reset) (w_out_cnt <= w_in_cnt));

    // =====================================================================
    // 4 -- NO LOSS / CONSERVATION
    // =====================================================================
    T_CONSERV_INFLIGHT_EQ_SR_FILL_PLUS_OUTREG: assert property (@(posedge clock) disable iff (reset) (ar_occ == (sr_fill + {5'd0, m_val})));

    T_CONSERV_AW_OUTSTANDING_EQ_FIFO_PLUS_CURRENT: assert property (@(posedge clock) disable iff (reset) (awq_occ == ({1'd0, awf_fill} + {4'd0, cid_valid} + {4'd0, (m_val && m_lst)})));

    T_CONSERV_AWFIFO_FILL_TRACKS_PTRS: assert property (@(posedge clock) disable iff (reset) (awf_fill == (awf_wr - awf_rd)));

    T_CONSERV_PER_ID_LIVE_SUMS_TO_INFLIGHT: assert property (@(posedge clock) disable iff (reset) (live_sum == {2'd0, ar_occ}));

    // =====================================================================
    // 5 -- MUTUAL EXCLUSION / ONE-HOT
    // =====================================================================
    T_MUTEX_SR_VALID_IS_CONTIGUOUS: assert property (@(posedge clock) disable iff (reset) ((sr_valid & (sr_valid + 16'd1)) == 16'd0));

    T_MUTEX_OUT_PACKET_NOT_INTERLEAVED: assert property (@(posedge clock) disable iff (reset) (pop_w && out_pkt_active) |-> (m_id == out_pkt_id));

    // =====================================================================
    // 6 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    T_BOUND_INFLIGHT_LE_SEVENTEEN: assert property (@(posedge clock) disable iff (reset) (ar_occ <= 6'd17));

    T_BOUND_AW_OUTSTANDING_LE_NINE: assert property (@(posedge clock) disable iff (reset) (awq_occ <= 5'd9));

    T_BOUND_AWFIFO_FILL_LE_EIGHT: assert property (@(posedge clock) disable iff (reset) (awf_fill <= 4'd8));

    T_BOUND_PER_ID_LIVE_LE_SEVENTEEN: assert property (@(posedge clock) disable iff (reset) ((id_live[0] <= 6'd17) && (id_live[1] <= 6'd17) && (id_live[2] <= 6'd17) && (id_live[3] <= 6'd17)));

    // =====================================================================
    // 7 -- ALLOCATOR DISCIPLINE
    // =====================================================================
    T_ALLOC_NO_W_ACCEPT_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) (ar_occ >= 6'd17) |-> !push_w);

    T_ALLOC_NO_AW_ACCEPT_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) (awq_occ >= 5'd9) |-> !push_aw);

    // =====================================================================
    // 8 -- REQUEST / RESPONSE CORRESPONDENCE
    // =====================================================================
    T_REQRSP_OUT_BEAT_HAS_AN_AW: assert property (@(posedge clock) disable iff (reset) m_val |-> (awq_occ != 5'd0));

    T_REQRSP_CURRENT_ID_IS_AW_QUEUE_ENTRY: assert property (@(posedge clock) disable iff (reset) (cid_valid && (awq_occ >= (m_val && m_lst ? 5'd2 : 5'd1))) |-> (current_id == expect_cid));

    T_REQRSP_PACKETS_COMPLETED_LE_AW_ACCEPTED: assert property (@(posedge clock) disable iff (reset) (aw_out_cnt <= aw_in_cnt));

    // =====================================================================
    // 9 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_OUT_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (m_val && !m_rdy) |=> m_val);

    T_PROTO_OUT_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (m_val && !m_rdy) |=> ($stable(m_dat) && $stable(m_stb) && $stable(m_lst) && $stable(m_id)));

    T_PROTO_W_PORT_REFUSES_ONLY_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) !w_rdy |-> (ar_occ >= 6'd16));

    T_PROTO_AW_PORT_REFUSES_ONLY_WHEN_FULL: assert property (@(posedge clock) disable iff (reset) !aw_rdy |-> (awf_fill == 4'd8));

    // =====================================================================
    // 11 -- BOUNDED RESPONSE (bounded-safety form)
    // =====================================================================
    T_BOUNDRSP_HEAD_PACKET_BEAT_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (head_stall_ctr <= N_HEAD_STALL));

    T_BOUNDRSP_AW_BECOMES_CURRENT_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (aw_load_ctr <= N_AW_LOAD));

    // =====================================================================
    // 12 -- DEADLOCK FREEDOM (bounded-safety form)
    // =====================================================================
    T_DEADLOCK_SOME_BOUNDARY_MOVES_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (no_move_ctr <= N_NO_MOVE));

    T_DEADLOCK_AW_PORT_UNBLOCKED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (aw_block_ctr <= N_AW_BLOCK));

    // =====================================================================
    // 13 -- RESET / INITIALISATION
    // =====================================================================
    T_RESET_SHIFT_REGISTER_EMPTY: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((sr_valid == 16'd0) && !m_val));

    T_RESET_AW_TRACKING_EMPTY: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((awf_fill == 4'd0) && (awf_wr == awf_rd) && !cid_valid));

    T_RESET_BOTH_SLAVE_PORTS_READY: assert property (@(posedge clock) disable iff (reset) after_reset |-> (aw_rdy && w_rdy));

    // =====================================================================
    // COVERS -- one or more per category used above
    // =====================================================================
    C_ORDER_PACKET_COMPLETES: cover property (@(posedge clock) disable iff (reset) (pop_w && m_lst && (out_beat == 2'd3)));
    C_ORDER_INTERLEAVED_ARRIVAL: cover property (@(posedge clock) disable iff (reset) (push_w && (w_id != head_id) && (awq_occ != 5'd0)));

    C_DATA_BEAT_DELIVERED: cover property (@(posedge clock) disable iff (reset) (pop_w && first_found));

    C_UNIQ_TWO_IDS_LIVE: cover property (@(posedge clock) disable iff (reset) seen_two_ids_live);
    C_UNIQ_RING_WRAPS: cover property (@(posedge clock) disable iff (reset) (push_w && (ar_wr == 5'd31)));

    C_CONSERV_SR_HOLDS_FOUR: cover property (@(posedge clock) disable iff (reset) (sr_fill >= 6'd4));
    C_CONSERV_AW_BACKLOG: cover property (@(posedge clock) disable iff (reset) (awq_occ >= 5'd4));

    C_MUTEX_SR_HOLDS_EIGHT: cover property (@(posedge clock) disable iff (reset) (sr_fill >= 6'd8));
    C_MUTEX_PACKET_IN_PROGRESS: cover property (@(posedge clock) disable iff (reset) (pop_w && out_pkt_active));

    C_OCC_SR_FULL: cover property (@(posedge clock) disable iff (reset) (sr_valid == 16'hffff));
    C_OCC_AWFIFO_FULL: cover property (@(posedge clock) disable iff (reset) (awf_fill == 4'd8));

    C_ALLOC_W_PORT_BLOCKED: cover property (@(posedge clock) disable iff (reset) (w_val && !w_rdy));
    C_ALLOC_AW_PORT_BLOCKED: cover property (@(posedge clock) disable iff (reset) (aw_val && !aw_rdy));

    C_REQRSP_CURRENT_ID_LOADED: cover property (@(posedge clock) disable iff (reset) (cid_valid && (awq_occ != 5'd0)));
    C_REQRSP_TWO_PACKETS_DONE: cover property (@(posedge clock) disable iff (reset) (aw_out_cnt >= 16'd2));

    C_PROTO_OUT_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (m_val && !m_rdy));

    C_BOUNDRSP_HEAD_STALLED_TWO: cover property (@(posedge clock) disable iff (reset) (head_stall_ctr >= 8'd2));
    C_BOUNDRSP_AW_LOAD_STALLED_TWO: cover property (@(posedge clock) disable iff (reset) (aw_load_ctr >= 8'd2));

    C_DEADLOCK_NOTHING_MOVED_TWO: cover property (@(posedge clock) disable iff (reset) (no_move_ctr >= 8'd2));
    C_DEADLOCK_AW_BLOCKED_FOUR: cover property (@(posedge clock) disable iff (reset) (aw_block_ctr >= 8'd4));

    C_RESET_FIRST_CYCLE_AFTER_RESET: cover property (@(posedge clock) disable iff (reset) after_reset);

endmodule

`default_nettype wire

bind testbench axi3_reorder_targets axi3_reorder_targets (
    .clock(clock), .reset(reset));
