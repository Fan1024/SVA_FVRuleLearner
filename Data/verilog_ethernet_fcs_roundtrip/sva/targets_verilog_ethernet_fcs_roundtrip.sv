// ===========================================================================
// Candidate target assertions for verilog_ethernet_fcs_roundtrip.
//
// Bound into `testbench`, so every reference below is a hierarchical name from
// the formal top.  Nothing here is an assumption.
//
// The oracle is INDEPENDENT of `ft/tb.sv`'s single end-to-end byte ring.  It
// cuts the insert/check pair at the FRAMED MIDDLE and keeps its own model of
// each hop:
//
//   * QA -- a 64-entry payload-byte queue, pushed at the source port and
//     popped at the middle boundary while this file's own framer says the
//     middle byte is a payload byte.  This is what the FCS inserter's
//     pass-through has to agree with.
//   * a REFERENCE CRC-32 -- `crc32_next` below is a byte-serial reflected
//     CRC-32 (poly 0xEDB88320, seeded all-ones) computed from the payload
//     bytes THIS FILE saw at the source port.  It shares nothing with the
//     design's `lfsr` instance.  The four bytes the inserter appends must be
//     the ones's complement of that state, low byte first, which is what the
//     Ethernet FCS is.
//   * FR -- an 8-entry queue of completed frames' reference CRCs, so the FCS
//     window at the middle is checked against the frame it belongs to even
//     when the next frame has already started at the source port.
//   * QB -- a 64-entry payload-byte queue, pushed at the middle boundary from
//     what the middle ACTUALLY carried and popped at the egress.  This is what
//     the FCS checker's strip-and-forward has to agree with.
//   * a four-deep history of middle bytes, against which the checker's own
//     delay line is compared.
//   * saturating wait counters, which is how a bounded-response / deadlock
//     obligation is written as a safety property under FRA.
//
// The package's environment (`ft/tb.sv`) already assumes the source never
// marks a frame bad and never runs a frame past sixteen bytes; nothing here
// adds to it.
// ===========================================================================

`default_nettype none

module eth_fcs_targets (input wire clock, input wire reset);

    localparam integer DEPTH  = 64;
    localparam integer FRAMES = 8;

    localparam [1:0] INS_IDLE    = 2'd0;
    localparam [1:0] INS_PAYLOAD = 2'd1;
    localparam [1:0] INS_PAD     = 2'd2;
    localparam [1:0] INS_FCS     = 2'd3;

    localparam [7:0] N_MID_STALL   = 8'd8;
    localparam [7:0] N_OUT_STALL   = 8'd12;
    localparam [7:0] N_NO_MOVE     = 8'd16;
    localparam [7:0] N_INPUT_BLOCK = 8'd24;
    localparam [7:0] CTR_MAX       = 8'd255;

    // ------------------------------------------------------------ oracle CRC
    // Byte-serial reflected CRC-32.  This is the Ethernet FCS generator, and
    // it is written here rather than read out of the design's `lfsr`.
    function automatic [31:0] crc32_next(input [31:0] c, input [7:0] d);
        reg [31:0] x;
        integer    b;
        begin
            x = c ^ {24'd0, d};
            for (b = 0; b < 8; b = b + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_next = x;
        end
    endfunction

    // ------------------------------------------------------------- aliases
    wire [7:0] s_dat = testbench.s_data;
    wire       s_val = testbench.s_valid;
    wire       s_rdy = testbench.s_ready;
    wire       s_lst = testbench.s_last;
    wire       s_usr = testbench.s_user;
    wire       s_fire = s_val && s_rdy;

    wire [7:0] mid_dat = testbench.fcs_data;
    wire       mid_val = testbench.fcs_valid;
    wire       mid_rdy = testbench.fcs_ready;
    wire       mid_lst = testbench.fcs_last;
    wire       mid_usr = testbench.fcs_user;
    wire       mid_fire = mid_val && mid_rdy;

    wire [7:0] o_dat = testbench.m_data;
    wire       o_val = testbench.m_valid;
    wire       o_rdy = testbench.m_ready;
    wire       o_lst = testbench.m_last;
    wire       o_usr = testbench.m_user;
    wire       o_fire = o_val && o_rdy;

    wire       bad_fcs = testbench.error_bad_fcs;

    // inserter state
    wire [1:0]  ins_state = testbench.insert_dut.state_reg;
    wire [15:0] ins_fptr  = testbench.insert_dut.frame_ptr_reg;
    wire [31:0] ins_crc   = testbench.insert_dut.crc_state;
    wire        ins_oval  = testbench.insert_dut.m_axis_tvalid_reg;
    wire        ins_tval  = testbench.insert_dut.temp_m_axis_tvalid_reg;
    wire        ins_busy  = testbench.insert_busy;

    // checker state
    wire [1:0]  chk_state = testbench.check_dut.state_reg;
    wire [31:0] chk_crc   = testbench.check_dut.crc_state;
    wire [7:0]  chk_d0    = testbench.check_dut.s_axis_tdata_d0;
    wire [7:0]  chk_d1    = testbench.check_dut.s_axis_tdata_d1;
    wire [7:0]  chk_d2    = testbench.check_dut.s_axis_tdata_d2;
    wire [7:0]  chk_d3    = testbench.check_dut.s_axis_tdata_d3;
    wire        chk_v0    = testbench.check_dut.s_axis_tvalid_d0;
    wire        chk_v1    = testbench.check_dut.s_axis_tvalid_d1;
    wire        chk_v2    = testbench.check_dut.s_axis_tvalid_d2;
    wire        chk_v3    = testbench.check_dut.s_axis_tvalid_d3;
    wire        chk_oval  = testbench.check_dut.m_axis_tvalid_reg;
    wire        chk_tval  = testbench.check_dut.temp_m_axis_tvalid_reg;

    // =====================================================================
    // ORACLE state
    // =====================================================================
    reg [7:0]  qa_dat [0:DEPTH-1];
    reg        qa_lst [0:DEPTH-1];
    reg [5:0]  qa_wr, qa_rd;
    reg [6:0]  qa_occ;

    reg [7:0]  qb_dat [0:DEPTH-1];
    reg        qb_lst [0:DEPTH-1];
    reg [5:0]  qb_wr, qb_rd;
    reg [6:0]  qb_occ;

    reg [31:0] fr_crc [0:FRAMES-1];
    reg [2:0]  fr_wr, fr_rd;
    reg [3:0]  fr_occ;

    reg [31:0] in_crc;
    reg [4:0]  in_len;

    reg        mid_fcs;          // the middle framer is inside the FCS window
    reg [1:0]  mid_idx;          // which of the four FCS bytes is next
    reg [7:0]  mid_h0, mid_h1, mid_h2, mid_h3;
    reg [2:0]  mid_hist;         // how many middle bytes have been seen, to 4

    reg [15:0] in_bytes, out_bytes, mid_bytes, rel_bytes;
    reg [7:0]  mid_frames, out_frames;

    reg [7:0]  mid_stall_ctr;
    reg [7:0]  out_stall_ctr;
    reg [7:0]  no_move_ctr;
    reg [7:0]  in_block_ctr;
    reg        after_reset;
    reg        seen_two_frames;

    wire       mid_payload = mid_fire && !mid_fcs;
    wire       mid_fcs_beat = mid_fire && mid_fcs;
    wire [4:0] fcs_shift = {mid_idx, 3'd0};
    wire [7:0] fcs_expect = ~fr_crc[fr_rd][fcs_shift +: 8];

    // ------------------------------------------------------- oracle update
    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            qa_wr <= 6'd0; qa_rd <= 6'd0; qa_occ <= 7'd0;
            qb_wr <= 6'd0; qb_rd <= 6'd0; qb_occ <= 7'd0;
            fr_wr <= 3'd0; fr_rd <= 3'd0; fr_occ <= 4'd0;
            in_crc <= 32'hFFFFFFFF;
            in_len <= 5'd0;
            mid_fcs <= 1'b0;
            mid_idx <= 2'd0;
            mid_hist <= 3'd0;
            mid_h0 <= 8'd0; mid_h1 <= 8'd0; mid_h2 <= 8'd0; mid_h3 <= 8'd0;
            in_bytes <= 16'd0; out_bytes <= 16'd0;
            mid_bytes <= 16'd0; rel_bytes <= 16'd0;
            mid_frames <= 8'd0; out_frames <= 8'd0;
            mid_stall_ctr <= 8'd0;
            out_stall_ctr <= 8'd0;
            no_move_ctr   <= 8'd0;
            in_block_ctr  <= 8'd0;
            seen_two_frames <= 1'b0;
        end else begin
            // source port: one payload byte, and the reference CRC over it
            if (s_fire) begin
                qa_dat[qa_wr] <= s_dat;
                qa_lst[qa_wr] <= s_lst;
                qa_wr <= qa_wr + 6'd1;
                if (in_bytes != 16'hffff)
                    in_bytes <= in_bytes + 16'd1;
                if (s_lst) begin
                    fr_crc[fr_wr] <= crc32_next(in_crc, s_dat);
                    fr_wr  <= fr_wr + 3'd1;
                    in_crc <= 32'hFFFFFFFF;
                    in_len <= 5'd0;
                end else begin
                    in_crc <= crc32_next(in_crc, s_dat);
                    in_len <= in_len + 5'd1;
                end
            end
            fr_occ <= fr_occ + {3'd0, (s_fire && s_lst)}
                             - {3'd0, (mid_fcs_beat && (mid_idx == 2'd3))};

            // middle boundary: this file's framer decides payload vs FCS
            if (mid_fire) begin
                mid_h0 <= mid_dat;
                mid_h1 <= mid_h0;
                mid_h2 <= mid_h1;
                mid_h3 <= mid_h2;
                if (mid_hist != 3'd4)
                    mid_hist <= mid_hist + 3'd1;
                if (mid_bytes != 16'hffff)
                    mid_bytes <= mid_bytes + 16'd1;
                if (!mid_fcs) begin
                    qa_rd <= qa_rd + 6'd1;
                    qb_dat[qb_wr] <= mid_dat;
                    qb_lst[qb_wr] <= qa_lst[qa_rd];
                    qb_wr <= qb_wr + 6'd1;
                    if (rel_bytes != 16'hffff)
                        rel_bytes <= rel_bytes + 16'd1;
                    if (qa_lst[qa_rd]) begin
                        mid_fcs <= 1'b1;
                        mid_idx <= 2'd0;
                    end
                end else if (mid_idx == 2'd3) begin
                    mid_fcs <= 1'b0;
                    mid_idx <= 2'd0;
                    fr_rd   <= fr_rd + 3'd1;
                    mid_frames <= mid_frames + 8'd1;
                    if (mid_frames != 8'd0)
                        seen_two_frames <= 1'b1;
                end else begin
                    mid_idx <= mid_idx + 2'd1;
                end
            end
            qa_occ <= qa_occ + {6'd0, s_fire} - {6'd0, mid_payload};
            qb_occ <= qb_occ + {6'd0, mid_payload} - {6'd0, o_fire};

            // egress
            if (o_fire) begin
                qb_rd <= qb_rd + 6'd1;
                if (out_bytes != 16'hffff)
                    out_bytes <= out_bytes + 16'd1;
                if (o_lst)
                    out_frames <= out_frames + 8'd1;
            end

            // bounded response: a payload byte is inside the inserter and the
            // checker can take one, but nothing crosses the middle
            if ((qa_occ == 7'd0) || !mid_rdy || mid_fire)
                mid_stall_ctr <= 8'd0;
            else if (mid_stall_ctr != CTR_MAX)
                mid_stall_ctr <= mid_stall_ctr + 8'd1;

            // bounded response: a frame is complete at the middle, so the
            // checker's delay line has been flushed, and the consumer is
            // ready, but nothing leaves
            if ((mid_frames == out_frames) || !o_rdy || o_fire)
                out_stall_ctr <= 8'd0;
            else if (out_stall_ctr != CTR_MAX)
                out_stall_ctr <= out_stall_ctr + 8'd1;

            // deadlock: work the design can act on, both sinks ready, and no
            // beat at any of the three boundaries
            if (!((qa_occ != 7'd0) || (mid_frames != out_frames))
                    || !o_rdy || !mid_rdy || mid_fire || o_fire || s_fire)
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
    T_ORDER_MID_PAYLOAD_BYTE_IS_INPUT_HEAD: assert property (@(posedge clock) disable iff (reset) (mid_payload && (qa_occ != 7'd0)) |-> (mid_dat == qa_dat[qa_rd]));

    T_ORDER_OUT_BYTE_IS_MID_PAYLOAD_HEAD: assert property (@(posedge clock) disable iff (reset) (o_fire && (qb_occ != 7'd0)) |-> (o_dat == qb_dat[qb_rd]));

    T_ORDER_MID_LAST_ONLY_ON_FOURTH_FCS_BYTE: assert property (@(posedge clock) disable iff (reset) mid_fire |-> (mid_lst == (mid_fcs && (mid_idx == 2'd3))));

    T_ORDER_OUT_LAST_IS_MID_PAYLOAD_HEAD_LAST: assert property (@(posedge clock) disable iff (reset) (o_fire && (qb_occ != 7'd0)) |-> (o_lst == qb_lst[qb_rd]));

    // =====================================================================
    // 2 -- DATA INTEGRITY
    // =====================================================================
    T_DATA_MID_FCS_BYTE_IS_REFERENCE_CRC: assert property (@(posedge clock) disable iff (reset) (mid_fcs_beat && (fr_occ != 4'd0)) |-> (mid_dat == fcs_expect));

    T_DATA_CHECK_DELAY_LINE_HOLDS_LAST_FOUR_BYTES: assert property (@(posedge clock) disable iff (reset) (mid_hist == 3'd4) |-> ((chk_d0 == mid_h0) && (chk_d1 == mid_h1) && (chk_d2 == mid_h2) && (chk_d3 == mid_h3)));

    T_DATA_NO_BAD_FCS_REPORTED: assert property (@(posedge clock) disable iff (reset) !bad_fcs);

    T_DATA_OUT_NEVER_MARKED_BAD: assert property (@(posedge clock) disable iff (reset) o_val |-> !o_usr);

    T_DATA_MID_NEVER_MARKED_BAD: assert property (@(posedge clock) disable iff (reset) mid_val |-> !mid_usr);

    // =====================================================================
    // 3 -- UNIQUENESS / NO DUPLICATION
    // =====================================================================
    T_UNIQ_MID_PAYLOAD_WAS_PUSHED: assert property (@(posedge clock) disable iff (reset) mid_payload |-> (qa_occ != 7'd0));

    T_UNIQ_OUT_BYTE_WAS_RELEASED: assert property (@(posedge clock) disable iff (reset) o_fire |-> (qb_occ != 7'd0));

    T_UNIQ_MID_FCS_BELONGS_TO_A_FRAME: assert property (@(posedge clock) disable iff (reset) mid_fcs_beat |-> (fr_occ != 4'd0));

    // =====================================================================
    // 4 -- NO LOSS / CONSERVATION
    // =====================================================================
    T_CONSERV_INSERT_FRAME_PTR_TRACKS_PAYLOAD_COUNT: assert property (@(posedge clock) disable iff (reset) (ins_state == INS_PAYLOAD) |-> (ins_fptr == {11'd0, in_len}));

    T_CONSERV_BYTES_IN_EQ_OUT_PLUS_INFLIGHT: assert property (@(posedge clock) disable iff (reset) ((in_bytes - out_bytes) == ({9'd0, qa_occ} + {9'd0, qb_occ})));

    T_CONSERV_MID_BYTES_EQ_PAYLOAD_PLUS_FOUR_PER_FRAME: assert property (@(posedge clock) disable iff (reset) (mid_bytes == (rel_bytes + {6'd0, mid_frames, 2'd0} + {14'd0, (mid_fcs ? mid_idx : 2'd0)})));

    T_CONSERV_OUT_NEVER_MORE_THAN_IN: assert property (@(posedge clock) disable iff (reset) (out_bytes <= in_bytes));

    // =====================================================================
    // 6 -- OCCUPANCY AND BOUNDS
    // =====================================================================
    T_BOUND_QA_OCC_LE_THREE: assert property (@(posedge clock) disable iff (reset) (qa_occ <= 7'd3));

    T_BOUND_QB_OCC_LE_EIGHT: assert property (@(posedge clock) disable iff (reset) (qb_occ <= 7'd8));

    T_BOUND_FRAME_QUEUE_OCC_LE_FOUR: assert property (@(posedge clock) disable iff (reset) (fr_occ <= 4'd4));

    T_BOUND_INSERT_FRAME_PTR_LE_SIXTEEN: assert property (@(posedge clock) disable iff (reset) (ins_fptr <= 16'd16));

    // =====================================================================
    // 9 -- PROTOCOL CONFORMANCE
    // =====================================================================
    T_PROTO_MID_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (mid_val && !mid_rdy) |=> mid_val);

    T_PROTO_MID_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (mid_val && !mid_rdy) |=> ($stable(mid_dat) && $stable(mid_lst) && $stable(mid_usr)));

    T_PROTO_OUT_VALID_NOT_WITHDRAWN: assert property (@(posedge clock) disable iff (reset) (o_val && !o_rdy) |=> o_val);

    T_PROTO_OUT_PAYLOAD_STABLE: assert property (@(posedge clock) disable iff (reset) (o_val && !o_rdy) |=> ($stable(o_dat) && $stable(o_lst) && $stable(o_usr)));

    // =====================================================================
    // 11 -- BOUNDED RESPONSE (bounded-safety form)
    // =====================================================================
    T_BOUNDRSP_PAYLOAD_CROSSES_MIDDLE_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (mid_stall_ctr <= N_MID_STALL));

    T_BOUNDRSP_COMPLETED_FRAME_DRAINS_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (out_stall_ctr <= N_OUT_STALL));

    // =====================================================================
    // 12 -- DEADLOCK FREEDOM (bounded-safety form)
    // =====================================================================
    T_DEADLOCK_SOME_BOUNDARY_MOVES_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (no_move_ctr <= N_NO_MOVE));

    T_DEADLOCK_SOURCE_UNBLOCKED_WITHIN_N: assert property (@(posedge clock) disable iff (reset) (in_block_ctr <= N_INPUT_BLOCK));

    // =====================================================================
    // 13 -- RESET / INITIALISATION
    // =====================================================================
    T_RESET_INSERT_IDLE: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((ins_state == INS_IDLE) && (ins_crc == 32'hFFFFFFFF) && !mid_val && !ins_tval && !ins_busy));

    T_RESET_CHECK_IDLE: assert property (@(posedge clock) disable iff (reset) after_reset |-> ((chk_state == INS_IDLE) && (chk_crc == 32'hFFFFFFFF) && !o_val && !chk_tval && !bad_fcs));

    T_RESET_CHECK_DELAY_LINE_INVALID: assert property (@(posedge clock) disable iff (reset) after_reset |-> (!chk_v0 && !chk_v1 && !chk_v2 && !chk_v3));

    T_RESET_SOURCE_PORT_NOT_READY: assert property (@(posedge clock) disable iff (reset) after_reset |-> !s_rdy);

    // =====================================================================
    // 14 -- LIFECYCLE / ACCESS CONTROL
    // =====================================================================
    T_LIFECYCLE_INSERT_NEVER_PADS: assert property (@(posedge clock) disable iff (reset) (ins_state != INS_PAD));

    T_LIFECYCLE_NO_INPUT_ACCEPTED_DURING_FCS: assert property (@(posedge clock) disable iff (reset) s_fire |-> (ins_state != INS_FCS));

    // =====================================================================
    // COVERS -- one or more per category used above
    // =====================================================================
    C_ORDER_MID_PAYLOAD_BYTE: cover property (@(posedge clock) disable iff (reset) mid_payload);
    C_ORDER_FRAME_ENDS_AT_MIDDLE: cover property (@(posedge clock) disable iff (reset) (mid_fcs_beat && (mid_idx == 2'd3)));
    C_ORDER_FRAME_ENDS_AT_EGRESS: cover property (@(posedge clock) disable iff (reset) (o_fire && o_lst));

    C_DATA_FCS_BYTE_CHECKED: cover property (@(posedge clock) disable iff (reset) (mid_fcs_beat && (fr_occ != 4'd0)));
    C_DATA_DELAY_LINE_PRIMED: cover property (@(posedge clock) disable iff (reset) (mid_hist == 3'd4));

    C_UNIQ_TWO_FRAMES_AT_MIDDLE: cover property (@(posedge clock) disable iff (reset) seen_two_frames);
    C_UNIQ_TWO_FRAMES_IN_FLIGHT: cover property (@(posedge clock) disable iff (reset) (fr_occ >= 4'd2));

    C_CONSERV_LONG_FRAME: cover property (@(posedge clock) disable iff (reset) (in_len >= 5'd8));
    C_CONSERV_MAX_FRAME: cover property (@(posedge clock) disable iff (reset) (in_len == 5'd15));

    C_OCC_QA_BACKLOG: cover property (@(posedge clock) disable iff (reset) (qa_occ >= 7'd2));
    C_OCC_QB_BACKLOG: cover property (@(posedge clock) disable iff (reset) (qb_occ >= 7'd4));

    C_PROTO_MID_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (mid_val && !mid_rdy));
    C_PROTO_OUT_BACKPRESSURED: cover property (@(posedge clock) disable iff (reset) (o_val && !o_rdy));

    C_BOUNDRSP_MID_STALLED_TWO: cover property (@(posedge clock) disable iff (reset) (mid_stall_ctr >= 8'd2));
    C_BOUNDRSP_OUT_STALLED_TWO: cover property (@(posedge clock) disable iff (reset) (out_stall_ctr >= 8'd2));

    C_DEADLOCK_NOTHING_MOVED_TWO: cover property (@(posedge clock) disable iff (reset) (no_move_ctr >= 8'd2));
    C_DEADLOCK_SOURCE_BLOCKED_FOUR: cover property (@(posedge clock) disable iff (reset) (in_block_ctr >= 8'd4));

    C_RESET_FIRST_CYCLE_AFTER_RESET: cover property (@(posedge clock) disable iff (reset) after_reset);

    C_LIFECYCLE_INSERT_IN_FCS: cover property (@(posedge clock) disable iff (reset) (ins_state == INS_FCS));
    C_LIFECYCLE_INSERT_IN_PAYLOAD: cover property (@(posedge clock) disable iff (reset) (ins_state == INS_PAYLOAD));

endmodule

`default_nettype wire

bind testbench eth_fcs_targets eth_fcs_targets (
    .clock(clock), .reset(reset));
