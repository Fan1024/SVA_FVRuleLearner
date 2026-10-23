// ===========================================================================
// Candidate target assertions for verilog_axis_width_roundtrip.
//
// Bound into `testbench`, so every reference below is a hierarchical name from
// the formal top.  Nothing here is an assumption.
//
// The oracle is INDEPENDENT of `ft/tb.sv`'s single end-to-end byte ring.  It
// cuts the 8 -> 32 -> pipeline -> 8 path at its THREE internal boundaries and
// keeps a queue across each hop, so each stage is judged on its own:
//
//   * QA -- a 64-entry byte queue, pushed at the source port
//     (`s_valid && s_ready`, carrying that byte's `tlast`) and popped at the
//     PACKED boundary, one pop per set `tkeep` lane of the accepted word.
//     This is what the 8->32 upsizer has to agree with.
//   * QW -- a 64-entry WIDE-WORD queue of {data, keep, last}, pushed at the
//     packed boundary and popped at the BUFFERED boundary.  This is what the
//     four-stage pipeline FIFO has to agree with.
//   * QB -- a 64-entry byte queue, pushed at the buffered boundary by
//     expanding the accepted word's set lanes, and popped at the egress.
//     This is what the 32->8 downsizer has to agree with.
//
//   * saturating wait counters, which is how a bounded-response / deadlock
//     obligation is written as a safety property under FRA.
//
// Lane order and `tkeep` shape are this file's own arithmetic: a byte at lane
// i of a packed word is the i-th byte of that word, and a word carries n bytes
// where n is the population count of its `tkeep`.
// ===========================================================================

`default_nettype none

module axis_width_targets (input wire clock, input wire reset);

    localparam integer DEPTH = 64;

    localparam [7:0] N_OUT_STALL   = 8'd8;
    localparam [7:0] N_BUF_STALL   = 8'd16;
    localparam [7:0] N_NO_MOVE     = 8'd24;
    localparam [7:0] N_INPUT_BLOCK = 8'd128;
    localparam [7:0] CTR_MAX       = 8'd255;

    // ------------------------------------------------------------- aliases
    wire [7:0]  s_dat = testbench.s_data;
    wire        s_val = testbench.s_valid;
    wire        s_rdy = testbench.s_ready;
    wire        s_lst = testbench.s_last;
    wire        s_fire = s_val && s_rdy;

    wire [31:0] pk_dat = testbench.packed_data;
    wire [3:0]  pk_kep = testbench.packed_keep;
    wire        pk_val = testbench.packed_valid;
    wire        pk_rdy = testbench.packed_ready;
    wire        pk_lst = testbench.packed_last;
    wire        pk_fire = pk_val && pk_rdy;

    wire [31:0] bf_dat = testbench.buffered_data;
    wire [3:0]  bf_kep = testbench.buffered_keep;
    wire        bf_val = testbench.buffered_valid;
    wire        bf_rdy = testbench.buffered_ready;
    wire        bf_lst = testbench.buffered_last;
    wire        bf_fire = bf_val && bf_rdy;

    wire [7:0]  o_dat = testbench.out_data;
    wire        o_kep = testbench.out_keep;
    wire        o_val = testbench.out_valid;
    wire        o_rdy = testbench.m_ready;
    wire        o_lst = testbench.out_last;
    wire        o_fire = o_val && o_rdy;

    // upsizer state
    wire [1:0]  up_seg   = testbench.upsize.upsize.seg_reg;
    wire        up_skid  = testbench.upsize.upsize.s_axis_tvalid_reg;
    wire        up_oval  = testbench.upsize.upsize.m_axis_tvalid_reg;
    wire [3:0]  up_okeep = testbench.upsize.upsize.m_axis_tkeep_reg;

    // pipeline FIFO state
    wire        pp_v0 = testbench.wide_pipeline.stage[0].axis_tvalid_reg;
    wire        pp_v1 = testbench.wide_pipeline.stage[1].axis_tvalid_reg;
    wire        pp_v2 = testbench.wide_pipeline.stage[2].axis_tvalid_reg;
    wire        pp_v3 = testbench.wide_pipeline.stage[3].axis_tvalid_reg;
    wire [5:0]  pp_ofw = testbench.wide_pipeline.fifo.out_fifo_wr_ptr_reg;
    wire [5:0]  pp_ofr = testbench.wide_pipeline.fifo.out_fifo_rd_ptr_reg;
    wire        pp_oval = testbench.wide_pipeline.fifo.m_axis_tvalid_reg;

    // downsizer state
    wire        dn_skid  = testbench.downsize.downsize.s_axis_tvalid_reg;
    wire [3:0]  dn_skeep = testbench.downsize.downsize.s_axis_tkeep_reg;
    wire        dn_oval  = testbench.downsize.downsize.m_axis_tvalid_reg;

    // byte counts carried by a wide word
    wire [2:0] pk_n = {2'd0, pk_kep[0]} + {2'd0, pk_kep[1]}
                    + {2'd0, pk_kep[2]} + {2'd0, pk_kep[3]};
    wire [2:0] bf_n = {2'd0, bf_kep[0]} + {2'd0, bf_kep[1]}
                    + {2'd0, bf_kep[2]} + {2'd0, bf_kep[3]};
    wire [2:0] up_n = {2'd0, up_okeep[0]} + {2'd0, up_okeep[1]}
                    + {2'd0, up_okeep[2]} + {2'd0, up_okeep[3]};
    wire [2:0] dn_n = {2'd0, dn_skeep[0]} + {2'd0, dn_skeep[1]}
                    + {2'd0, dn_skeep[2]} + {2'd0, dn_skeep[3]};
    wire [2:0] pp_nv = {2'd0, pp_v0} + {2'd0, pp_v1}
                     + {2'd0, pp_v2} + {2'd0, pp_v3};

    // =====================================================================
    // ORACLE -- three shadow queues, one per hop
    // =====================================================================
    reg [7:0]  qa_dat [0:DEPTH-1];
    reg        qa_lst [0:DEPTH-1];
    reg [5:0]  qa_wr, qa_rd;
    reg [6:0]  qa_occ;

    reg [31:0] qw_dat [0:DEPTH-1];
    reg [3:0]  qw_kep [0:DEPTH-1];
    reg        qw_lst [0:DEPTH-1];
    reg [5:0]  qw_wr, qw_rd;
    reg [6:0]  qw_occ;
    reg [9:0]  qw_bytes;

    reg [7:0]  qb_dat [0:DEPTH-1];
    reg        qb_lst [0:DEPTH-1];
    reg [5:0]  qb_wr, qb_rd;
    reg [6:0]  qb_occ;

    reg [15:0] in_bytes, out_bytes;

    reg [7:0]  out_stall_ctr;
    reg [7:0]  buf_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  in_block_ctr;
    reg        after_reset;
    reg        seen_partial;
    reg        seen_full_word;

    // ---------------------------------------------------- packed-hop check
    reg        pk_data_bad;
    reg        pk_last_bad;
    reg        pk_short;
    reg [5:0]  ai;
    integer    i;
    always @* begin
        pk_data_bad = 1'b0;
        pk_last_bad = 1'b0;
        pk_short    = 1'b0;
        if (pk_fire) begin
            if (qa_occ < {4'd0, pk_n})
                pk_short = 1'b1;
            else
                for (i = 0; i < 4; i = i + 1)
                    if (i < pk_n) begin
                        ai = qa_rd + i[5:0];
                        if (pk_dat[8*i +: 8] != qa_dat[ai])
                            pk_data_bad = 1'b1;
                        if (qa_lst[ai] !=
                                ((i == (pk_n - 3'd1)) ? pk_lst : 1'b0))
                            pk_last_bad = 1'b1;
                    end
        end
    end

    // bytes the upsizer is holding: a completed word, or the segments merged
    // so far, plus its one-beat skid
    wire [3:0] up_hold = (up_oval ? {1'b0, up_n} : {2'd0, up_seg})
                       + {3'd0, up_skid};
    // bytes the downsizer is holding: what is left in its shift buffer plus
    // its output register
    wire [3:0] dn_hold = (dn_skid ? {1'b0, dn_n} : 4'd0) + {3'd0, dn_oval};

    // ------------------------------------------------------- oracle update
    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            qa_wr <= 6'd0; qa_rd <= 6'd0; qa_occ <= 7'd0;
            qw_wr <= 6'd0; qw_rd <= 6'd0; qw_occ <= 7'd0; qw_bytes <= 10'd0;
            qb_wr <= 6'd0; qb_rd <= 6'd0; qb_occ <= 7'd0;
            in_bytes <= 16'd0; out_bytes <= 16'd0;
            out_stall_ctr <= 8'd0;
            buf_stall_ctr <= 8'd0;
            no_move_ctr   <= 8'd0;
            in_block_ctr  <= 8'd0;
            seen_partial  <= 1'b0;
            seen_full_word<= 1'b0;
        end else begin
            // QA: one byte in at the source port, pk_n bytes out at the
            // packed boundary
            if (s_fire) begin
                qa_dat[qa_wr] <= s_dat;
                qa_lst[qa_wr] <= s_lst;
                qa_wr <= qa_wr + 6'd1;
                if (in_bytes != 16'hffff)
                    in_bytes <= in_bytes + 16'd1;
            end
            if (pk_fire)
                qa_rd <= qa_rd + {3'd0, pk_n};
            qa_occ <= qa_occ + {6'd0, s_fire} - (pk_fire ? {4'd0, pk_n} : 7'd0);

            // QW: one wide word per hop across the pipeline FIFO
            if (pk_fire) begin
                qw_dat[qw_wr] <= pk_dat;
                qw_kep[qw_wr] <= pk_kep;
                qw_lst[qw_wr] <= pk_lst;
                qw_wr <= qw_wr + 6'd1;
                if (pk_kep != 4'hf)
                    seen_partial <= 1'b1;
                else
                    seen_full_word <= 1'b1;
            end
            if (bf_fire)
                qw_rd <= qw_rd + 6'd1;
            qw_occ <= qw_occ + {6'd0, pk_fire} - {6'd0, bf_fire};
            qw_bytes <= qw_bytes + (pk_fire ? {7'd0, pk_n} : 10'd0)
                                 - (bf_fire ? {7'd0, bf_n} : 10'd0);

            // QB: bf_n bytes in at the buffered boundary, one byte out
            if (bf_fire) begin
                if (bf_n > 3'd0) begin
                    qb_dat[qb_wr] <= bf_dat[7:0];
                    qb_lst[qb_wr] <= (bf_n == 3'd1) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd1) begin
                    qb_dat[qb_wr + 6'd1] <= bf_dat[15:8];
                    qb_lst[qb_wr + 6'd1] <= (bf_n == 3'd2) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd2) begin
                    qb_dat[qb_wr + 6'd2] <= bf_dat[23:16];
                    qb_lst[qb_wr + 6'd2] <= (bf_n == 3'd3) ? bf_lst : 1'b0;
                end
                if (bf_n > 3'd3) begin
                    qb_dat[qb_wr + 6'd3] <= bf_dat[31:24];
                    qb_lst[qb_wr + 6'd3] <= bf_lst;
                end
                qb_wr <= qb_wr + {3'd0, bf_n};
            end
            if (o_fire) begin
                qb_rd <= qb_rd + 6'd1;
                if (out_bytes != 16'hffff)
                    out_bytes <= out_bytes + 16'd1;
            end
            qb_occ <= qb_occ + (bf_fire ? {4'd0, bf_n} : 7'd0) - {6'd0, o_fire};

            // bounded response: bytes are past the downsizer's input and the
            // consumer is ready, but nothing leaves
            if ((qb_occ == 7'd0) || !o_rdy || o_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            // bounded response: words are inside the pipeline FIFO and the
            // downsizer can take one, but none crosses
            if ((qw_occ == 7'd0) || !bf_rdy || bf_fire)
                buf_stall_ctr <= 8'd0;
            else if (buf_stall_ctr != CTR_MAX)
                buf_stall_ctr <= buf_stall_ctr + 8'd1;

            // deadlock: work past the packing point, a ready consumer, and no
            // beat at either downstream boundary
            if (((qw_occ == 7'd0) && (qb_occ == 7'd0)) || !o_rdy
                    || bf_fire || o_fire)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            // deadlock: the source is blocked while the consumer is ready
            if (!s_val || s_rdy || !o_rdy)
                in_block_ctr <= 8'd0;
            else if (in_block_ctr != CTR_MAX)
                in_block_ctr <= in_block_ctr + 8'd1;
        end
    end

    // =====================================================================
    // 1 -- END-TO-END ORDERING
    // =====================================================================
    T_ORDER_PACKED_WORD_IS_INPUT_HEAD: assert property (@(posedge clock) disable iff (reset) !pk_data_bad);

    T_ORDER_PACKED_LAST_MARKS_FRAME_END: assert property (@(posedge clock) disable iff (reset) !pk_last_bad);

    T_ORDER_BUFFERED_WORD_IS_PACKED_HEAD: assert property (@(posedge clock) disable iff (reset) (bf_fire && (qw_occ != 7'd0)) |-> ((bf_dat == qw_dat[qw_rd]) && (bf_kep == qw_kep[qw_rd])));

    T_ORDER_OUT_BYTE_IS_BUFFERED_HEAD: assert property (@(posedge clock) disable iff (reset) (o_fire && (qb_occ != 7'd0)) |-> (o_dat == qb_dat[qb_rd]));

    // =====================================================================
    // 2 -- DATA INTEGRITY
    // =====================================================================
    T_DATA_BUFFERED_LAST_IS_PACKED_HEAD_LAST: assert property (@(posedge clock) disable iff (reset) (bf_fire && (qw_occ != 7'd0)) |-> (bf_lst == qw_lst[qw_rd]));

    T_DATA_OUT_LAST_IS_BUFFERED_HEAD_LAST: assert property (@(posedge clock) disable iff (reset) (o_fire && (qb_occ != 7'd0)) |-> (o_lst == qb_lst[qb_rd]));

    T_DATA_OUT_KEEP_ALWAYS_ONE: assert property (@(posedge clock) disable iff (reset) o_val |-> (o_kep == 1'b1));

    T_DATA_PACKED_FULL_WORD_UNLESS_LAST: assert property (@(posedge clock) disable iff (reset) (pk_fire && !pk_lst) |-> (pk_kep == 4'hf));

    // =====================================================================
    // 3 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_PACKED_WORD_WAS_PUSHED: assert property (@(posedge clock) disable iff (reset) !pk_short);

    T_UNIQ_BUFFERED_WORD_WAS_PACKED: assert property (@(posedge clock) disable iff (reset) bf_fire |-> (qw_occ != 7'd0));

    T_UNIQ_OUT_BYTE_WAS_BUFFERED: assert property (@(posedge clock) disable iff (reset) o_fire |-> (qb_occ != 7'd0));

    // =====================================================================
    // 4 -- NO LOSS / CONSERVATION
    // =====================================================================
    T_CONSERV_QA_OCC_MATCHES_UPSIZE_STATE: assert property (@(posedge clock) disable iff (reset) (qa_occ == {3'd0, up_hold}));

    T_CONSERV_QW_OCC_MATCHES_PIPELINE_STATE: assert property (@(posedge clock) disable iff (reset) (qw_occ == ({4'd0, pp_nv} + {1'd0, pp_ofw - pp_ofr} + {6'd0, pp_oval})));

    T_CONSERV_QB_OCC_MATCHES_DOWNSIZE_STATE: assert property (@(posedge clock) disable iff (reset) (qb_occ == {3'd0, dn_hold}));

    T_CONSERV_BYTES_IN_EQ_OUT_PLUS_INFLIGHT: assert property (@(posedge clock) disable iff (reset) ((in_bytes - out_bytes) == ({9'd0, qa_occ} + {6'd0, qw_bytes} + {9'd0, qb_occ})));

    // =====================================================================
    // 6 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    T_BOUND_QA_OCC_LE_FIVE: assert property (@(posedge clock) disable iff (reset) (qa_occ <= 7'd5));

    T_BOUND_QW_OCC_LE_FORTY: assert property (@(posedge clock) disable iff (reset) (qw_occ <= 7'd40));

    T_BOUND_QB_OCC_LE_FIVE: assert property (@(posedge clock) disable iff (reset) (qb_occ <= 7'd5));

    T_BOUND_PIPELINE_SKID_FILL_LE_TWENTYFOUR: assert property (@(posedge clock) disable iff (reset) ((pp_ofw - pp_ofr) <= 6'd24));

    T_BOUND_UPSIZE_NO_SEGMENT_WHILE_WORD_HELD: assert property (@(posedge clock) disable iff (reset) up_oval |-> (up_seg == 2'd0));

    // =====================================================================
    // 9 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_PACKED_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (pk_val && !pk_rdy) |=> pk_val);

    T_PROTO_PACKED_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (pk_val && !pk_rdy) |=> ($stable(pk_dat) && $stable(pk_kep) && $stable(pk_lst)));

    T_PROTO_BUFFERED_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (bf_val && !bf_rdy) |=> bf_val);

    T_PROTO_BUFFERED_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (bf_val && !bf_rdy) |=> ($stable(bf_dat) && $stable(bf_kep) && $stable(bf_lst)));

    T_PROTO_OUT_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (o_val && !o_rdy) |=> o_val);

    T_PROTO_OUT_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (o_val && !o_rdy) |=> ($stable(o_dat) && $stable(o_lst)));

    T_PROTO_PACKED_KEEP_CONTIGUOUS: assert property (@(posedge clock) disable iff (reset) pk_val |-> ((pk_kep == 4'h1) || (pk_kep == 4'h3) || (pk_kep == 4'h7) || (pk_kep == 4'hf)));

    // =====================================================================
    // 11 -- BOUNDED RESPONSE (bounded-safety form)
    // =====================================================================
    T_BOUNDRSP_BUFFERED_BYTE_DELIVERED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (out_stall_ctr <= N_OUT_STALL));

    T_BOUNDRSP_PACKED_WORD_CROSSES_PIPELINE_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (buf_stall_ctr <= N_BUF_STALL));

    // =====================================================================
    // 12 -- DEADLOCK FREEDOM (bounded-safety form)
    // =====================================================================
    T_DEADLOCK_STREAM_MOVES_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (no_move_ctr <= N_NO_MOVE));

    T_DEADLOCK_SOURCE_UNBLOCKED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (in_block_ctr <= N_INPUT_BLOCK));

    // =====================================================================
    // 13 -- RESET / INITIALISATION
    // =====================================================================
    T_RESET_UPSIZE_IDLE: assert property (@(posedge clock) disable iff (reset) after_reset |-> (!pk_val && !up_skid && (up_seg == 2'd0)));

    T_RESET_PIPELINE_EMPTY: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((pp_nv == 3'd0) && (pp_ofw == pp_ofr) && !pp_oval));

    T_RESET_DOWNSIZE_IDLE: assert property (@(posedge clock) disable iff (reset) after_reset |-> (!o_val && !dn_skid));

    T_RESET_INPUT_PORT_READY: assert property (@(posedge clock) disable iff (reset) after_reset |-> s_rdy);

    // =====================================================================
    // COVERS -- one or more per category used above
    // =====================================================================
    C_ORDER_PACKED_WORD_ACCEPTED: cover property (@(posedge clock) disable iff (reset) pk_fire);
    C_ORDER_OUT_BYTE_AFTER_WRAP: cover property (@(posedge clock) disable iff (reset) (o_fire && (qb_rd == 6'd3)));

    C_DATA_PARTIAL_WORD: cover property (@(posedge clock) disable iff (reset) (pk_fire && (pk_kep != 4'hf)));
    C_DATA_FULL_WORD: cover property (@(posedge clock) disable iff (reset) (pk_fire && (pk_kep == 4'hf)));
    C_DATA_FRAME_END_AT_EGRESS: cover property (@(posedge clock) disable iff (reset) (o_fire && o_lst));

    C_UNIQ_TWO_FRAMES_SEEN: cover property (@(posedge clock) disable iff (reset) (seen_partial && seen_full_word && o_fire));

    C_CONSERV_UPSIZE_HOLDS_THREE: cover property (@(posedge clock) disable iff (reset) (qa_occ >= 7'd3));
    C_CONSERV_DOWNSIZE_HOLDS_THREE: cover property (@(posedge clock) disable iff (reset) (qb_occ >= 7'd3));

    C_OCC_PIPELINE_DEEP: cover property (@(posedge clock) disable iff (reset) (qw_occ >= 7'd8));
    C_OCC_PIPELINE_SKID_DEEP: cover property (@(posedge clock) disable iff (reset) ((pp_ofw - pp_ofr) >= 6'd8));

    C_PROTO_PACKED_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (pk_val && !pk_rdy));
    C_PROTO_BUFFERED_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (bf_val && !bf_rdy));
    C_PROTO_OUT_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (o_val && !o_rdy));
    C_PROTO_SOURCE_BLOCKED: cover property (@(posedge clock) disable iff (reset) (s_val && !s_rdy));

    C_BOUNDRSP_OUT_STALLED_TWO: cover property (@(posedge clock) disable iff (reset) (out_stall_ctr >= 8'd2));
    C_BOUNDRSP_BUF_STALLED_FOUR: cover property (@(posedge clock) disable iff (reset) (buf_stall_ctr >= 8'd4));

    C_DEADLOCK_NOTHING_MOVED_TWO: cover property (@(posedge clock) disable iff (reset) (no_move_ctr >= 8'd2));
    C_DEADLOCK_SOURCE_BLOCKED_EIGHT: cover property (@(posedge clock) disable iff (reset) (in_block_ctr >= 8'd8));

    C_RESET_FIRST_CYCLE_AFTER_RESET: cover property (@(posedge clock) disable iff (reset) after_reset);

endmodule

`default_nettype wire

bind testbench axis_width_targets axis_width_targets (
    .clock(clock), .reset(reset));
