// ===========================================================================
// Checker for the two-tile OpenPiton coherence task.
//
// It holds the package's INDEPENDENT ORACLE: a shadow directory of per-line,
// per-tile permission maintained ONLY from packets observed on the two L1.5s'
// NoC pins. It never reads `l2_dir`, `rf_l15_mesi`, an MSHR, or any other piece
// of the design's own bookkeeping -- the design's directory is exactly the thing
// a coherence target is supposed to be checking, and an assertion that restated
// it would prove nothing.
//
// What the oracle is built out of, in order:
//
//   1. A packet framer per tile per channel. Position inside a packet is this
//      file's own count of accepted flits against the header's own MSG_LENGTH,
//      so flit 0 (type / mshrid / mesi) and flit 1 (address) are identified by
//      arithmetic done here, not by any flit-state register in the design.
//
//   2. A per-tile outstanding-request table, keyed on the MSG_MSHRID the L1.5
//      itself put on NoC1, carrying the line key read out of that request's own
//      address flit. This is what lets a one-flit DATA_ACK -- which carries a
//      mshrid and no address -- be attributed to a line.
//
//   3. A per-tile revoke queue: an entry is pushed when a LOAD_FWD / STORE_FWD /
//      INV_FWD header plus its address flit are seen arriving at that L1.5, and
//      popped when that L1.5 emits a last-subline *_FWDACK on NoC3. OpenPiton's
//      NoC2 is point-to-point in order and the L1.5 answers forwards in the
//      order it takes them, so head-of-queue is the pairing.
//
//   4. The shadow directory itself: sh_excl[tile] and sh_shared[tile], one bit
//      per line key. A DATA_ACK / NODATA_ACK carrying `MSG_MESI` of E or M gives
//      the requesting tile write permission; MESI of S gives read permission; a
//      popped INV/STORE FWDACK takes all permission away; a popped LOAD_FWDACK
//      downgrades write permission to read; a writeback or a writeback guard
//      the tile issued itself takes it away.
//
// The line key is address bits [9:6], which is the whole address space the
// bounded core sources in the formal top ever ask for. Bit 6 of that key is also
// the home-tile selector, so eight of the sixteen keys live in tile 0's L2 slice
// and eight in tile 1's -- both L1.5s reach both slices.
//
// The environment fairness assumptions are here too. Both constrain FREE INPUTS
// of the formal top directly, never a derived state predicate, so consistency is
// immediate: holding cpx_ack = 2'b11 and mem_send = 1 for all time satisfies all
// three.
// ===========================================================================

module openpiton_two_tile_coherence_checker (
    input wire        clk,
    input wire        reset_n,

    // the two L1.5s' NoC pins, {tile1, tile0}
    input wire [1:0]   l15_n1_val,
    input wire [1:0]   l15_n1_rdy,
    input wire [127:0] l15_n1_data,
    input wire [1:0]   l15_n2_val,
    input wire [1:0]   l15_n2_rdy,
    input wire [127:0] l15_n2_data,
    input wire [1:0]   l15_n3_val,
    input wire [1:0]   l15_n3_rdy,
    input wire [127:0] l15_n3_data,

    // reachability taps only -- no target reads these
    input wire [15:0] l2_mshr_busy,
    input wire [15:0] l2_mshr_wait,
    input wire [15:0] l2_mshr_pend,
    input wire [7:0]  l2_empty_slots,
    input wire [11:0] l15_mshr_val,

    input wire [1:0]  noc1_blocked,
    input wire [1:0]  noc2_blocked,
    input wire [1:0]  noc3_blocked,
    input wire        mem_req_blocked,
    input wire        mem_rsp_blocked,

    input wire        mem_holding,
    input wire [4:0]  mem_occupancy,
    input wire [3:0]  core_active,
    input wire [1:0]  cpx_ack,
    input wire        mem_send
);
    localparam integer NTILE = 2;
    localparam integer NKEY  = 16;
    localparam integer QD    = 8;     // revoke queue depth per tile

    // -----------------------------------------------------------------------
    // Environment fairness. Without these the system is trivially and
    // uninterestingly stalled: a core that never drains CPX, or a memory that
    // never answers, is not a coherence failure. Both are LEGALITY contracts.
    // -----------------------------------------------------------------------
    A_FAIR_CPX0: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] cpx_ack[0]);
    A_FAIR_CPX1: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] cpx_ack[1]);
    A_FAIR_MEM: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] mem_send);

    // =======================================================================
    // ORACLE 1 -- packet framers, six of them.
    // =======================================================================
    wire [63:0] n1_dat [0:1];
    wire [63:0] n2_dat [0:1];
    wire [63:0] n3_dat [0:1];
    wire        n1_fire [0:1];
    wire        n2_fire [0:1];
    wire        n3_fire [0:1];

    genvar gi;
    generate
        for (gi = 0; gi < NTILE; gi = gi + 1) begin : g_wire
            assign n1_dat[gi]  = l15_n1_data[64*gi +: 64];
            assign n2_dat[gi]  = l15_n2_data[64*gi +: 64];
            assign n3_dat[gi]  = l15_n3_data[64*gi +: 64];
            assign n1_fire[gi] = l15_n1_val[gi] && l15_n1_rdy[gi];
            assign n2_fire[gi] = l15_n2_val[gi] && l15_n2_rdy[gi];
            assign n3_fire[gi] = l15_n3_val[gi] && l15_n3_rdy[gi];
        end
    endgenerate

    reg [7:0] f1_idx [0:1]; reg [7:0] f1_len [0:1];
    reg [7:0] f2_idx [0:1]; reg [7:0] f2_len [0:1];
    reg [7:0] f3_idx [0:1]; reg [7:0] f3_len [0:1];

    wire n1_hdr [0:1];
    wire n2_hdr [0:1];
    wire n3_hdr [0:1];
    wire n1_a1  [0:1];      // this fire is flit 1 of a NoC1 packet
    wire n2_a1  [0:1];
    wire n3_a1  [0:1];

    generate
        for (gi = 0; gi < NTILE; gi = gi + 1) begin : g_hdr
            assign n1_hdr[gi] = n1_fire[gi] && (f1_idx[gi] == 8'd0);
            assign n2_hdr[gi] = n2_fire[gi] && (f2_idx[gi] == 8'd0);
            assign n3_hdr[gi] = n3_fire[gi] && (f3_idx[gi] == 8'd0);
            assign n1_a1[gi]  = n1_fire[gi] && (f1_idx[gi] == 8'd1);
            assign n2_a1[gi]  = n2_fire[gi] && (f2_idx[gi] == 8'd1);
            assign n3_a1[gi]  = n3_fire[gi] && (f3_idx[gi] == 8'd1);
        end
    endgenerate

    integer fi;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (fi = 0; fi < NTILE; fi = fi + 1) begin
                f1_idx[fi] <= 8'd0; f1_len[fi] <= 8'd0;
                f2_idx[fi] <= 8'd0; f2_len[fi] <= 8'd0;
                f3_idx[fi] <= 8'd0; f3_len[fi] <= 8'd0;
            end
        end else begin
            for (fi = 0; fi < NTILE; fi = fi + 1) begin
                if (n1_fire[fi]) begin
                    if (f1_idx[fi] == 8'd0) begin
                        f1_len[fi] <= n1_dat[fi][`MSG_LENGTH];
                        f1_idx[fi] <= (n1_dat[fi][`MSG_LENGTH] == 8'd0) ? 8'd0 : 8'd1;
                    end else begin
                        f1_idx[fi] <= (f1_idx[fi] == f1_len[fi]) ? 8'd0 : f1_idx[fi] + 8'd1;
                    end
                end
                if (n2_fire[fi]) begin
                    if (f2_idx[fi] == 8'd0) begin
                        f2_len[fi] <= n2_dat[fi][`MSG_LENGTH];
                        f2_idx[fi] <= (n2_dat[fi][`MSG_LENGTH] == 8'd0) ? 8'd0 : 8'd1;
                    end else begin
                        f2_idx[fi] <= (f2_idx[fi] == f2_len[fi]) ? 8'd0 : f2_idx[fi] + 8'd1;
                    end
                end
                if (n3_fire[fi]) begin
                    if (f3_idx[fi] == 8'd0) begin
                        f3_len[fi] <= n3_dat[fi][`MSG_LENGTH];
                        f3_idx[fi] <= (n3_dat[fi][`MSG_LENGTH] == 8'd0) ? 8'd0 : 8'd1;
                    end else begin
                        f3_idx[fi] <= (f3_idx[fi] == f3_len[fi]) ? 8'd0 : f3_idx[fi] + 8'd1;
                    end
                end
            end
        end
    end

    // ---- decoded header fields ---------------------------------------------
    wire [7:0] n1_type [0:1]; wire [7:0] n1_mid [0:1];
    wire [7:0] n2_type [0:1]; wire [7:0] n2_mid [0:1]; wire [1:0] n2_mesi [0:1];
    wire [7:0] n3_type [0:1]; wire [7:0] n3_mid [0:1]; wire n3_last [0:1];
    wire [3:0] n1_key  [0:1];    // from flit 1 of a NoC1 packet
    wire [3:0] n2_key  [0:1];
    wire [3:0] n3_key  [0:1];

    generate
        for (gi = 0; gi < NTILE; gi = gi + 1) begin : g_dec
            assign n1_type[gi] = n1_dat[gi][`MSG_TYPE];
            assign n1_mid[gi]  = n1_dat[gi][`MSG_MSHRID];
            assign n2_type[gi] = n2_dat[gi][`MSG_TYPE];
            assign n2_mid[gi]  = n2_dat[gi][`MSG_MSHRID];
            assign n2_mesi[gi] = n2_dat[gi][`MSG_MESI];
            assign n3_type[gi] = n3_dat[gi][`MSG_TYPE];
            assign n3_mid[gi]  = n3_dat[gi][`MSG_MSHRID];
            assign n3_last[gi] = n3_dat[gi][`MSG_LAST_SUBLINE];
            assign n1_key[gi]  = n1_dat[gi][9:6];
            assign n2_key[gi]  = n2_dat[gi][9:6];
            assign n3_key[gi]  = n3_dat[gi][9:6];
        end
    endgenerate

    // Message classes this oracle reacts to.
    wire n1_is_req [0:1];      // a request that will be answered by an ack
    wire n1_is_wbg [0:1];      // writeback guard: the L1.5 is dropping the line
    wire n2_is_ack [0:1];
    wire n2_is_inv [0:1];      // INV_FWD / STORE_FWD -- take the line away
    wire n2_is_dng [0:1];      // LOAD_FWD -- downgrade to shared
    wire n3_is_iack[0:1];      // INV_FWDACK / STORE_FWDACK
    wire n3_is_dack[0:1];      // LOAD_FWDACK
    wire n3_is_wb  [0:1];      // WB_REQ

    generate
        for (gi = 0; gi < NTILE; gi = gi + 1) begin : g_cls
            assign n1_is_req[gi]  = (n1_type[gi] == `MSG_TYPE_LOAD_REQ) ||
                                    (n1_type[gi] == `MSG_TYPE_STORE_REQ);
            assign n1_is_wbg[gi]  = (n1_type[gi] == `MSG_TYPE_WBGUARD_REQ);
            assign n2_is_ack[gi]  = (n2_type[gi] == `MSG_TYPE_DATA_ACK) ||
                                    (n2_type[gi] == `MSG_TYPE_NODATA_ACK);
            assign n2_is_inv[gi]  = (n2_type[gi] == `MSG_TYPE_INV_FWD) ||
                                    (n2_type[gi] == `MSG_TYPE_STORE_FWD);
            assign n2_is_dng[gi]  = (n2_type[gi] == `MSG_TYPE_LOAD_FWD);
            assign n3_is_iack[gi] = (n3_type[gi] == `MSG_TYPE_INV_FWDACK) ||
                                    (n3_type[gi] == `MSG_TYPE_STORE_FWDACK);
            assign n3_is_dack[gi] = (n3_type[gi] == `MSG_TYPE_LOAD_FWDACK);
            assign n3_is_wb[gi]   = (n3_type[gi] == `MSG_TYPE_WB_REQ);
        end
    endgenerate

    // =======================================================================
    // ORACLE 2 -- per-tile outstanding-request table, keyed on MSG_MSHRID.
    // =======================================================================
    reg [7:0] req_live  [0:1];              // one bit per mshrid[2:0]
    reg [3:0] req_key   [0:1][0:7];
    reg       req_store [0:1][0:7];
    reg [2:0] req_open  [0:1];              // id of the NoC1 packet in flight
    reg       req_open_v[0:1];
    reg       req_open_wbg [0:1];

    // =======================================================================
    // ORACLE 3 -- per-tile revoke queue.
    // =======================================================================
    reg [3:0] rq_key  [0:1][0:QD-1];
    reg       rq_inv  [0:1][0:QD-1];        // 1 = invalidate, 0 = downgrade
    reg [3:0] rq_wr   [0:1];
    reg [3:0] rq_rd   [0:1];
    reg [3:0] rq_open [0:1];                // key of the FWD packet in flight
    reg       rq_open_v [0:1];
    reg       rq_open_inv [0:1];

    wire [3:0] rq_cnt [0:1];
    assign rq_cnt[0] = rq_wr[0] - rq_rd[0];
    assign rq_cnt[1] = rq_wr[1] - rq_rd[1];

    // =======================================================================
    // ORACLE 4 -- the shadow directory.
    // =======================================================================
    reg [NKEY-1:0] sh_excl   [0:1];
    reg [NKEY-1:0] sh_shared [0:1];

    // event decode, all of it this file's own arithmetic over the wire
    wire        ack_ev   [0:1];
    wire [2:0]  ack_id   [0:1];
    wire        ack_hit  [0:1];
    wire [3:0]  ack_key  [0:1];
    wire        ack_write[0:1];
    wire        ack_read [0:1];
    wire        pop_ev   [0:1];
    wire [3:0]  pop_key  [0:1];
    wire        pop_inv  [0:1];

    generate
        for (gi = 0; gi < NTILE; gi = gi + 1) begin : g_ev
            assign ack_ev[gi]    = n2_hdr[gi] && n2_is_ack[gi];
            assign ack_id[gi]    = n2_mid[gi][2:0];
            assign ack_hit[gi]   = ack_ev[gi] && req_live[gi][n2_mid[gi][2:0]];
            assign ack_key[gi]   = req_key[gi][n2_mid[gi][2:0]];
            assign ack_write[gi] = (n2_mesi[gi] == `MSG_MESI_E) ||
                                   (n2_mesi[gi] == `MSG_MESI_M);
            assign ack_read[gi]  = (n2_mesi[gi] == `MSG_MESI_S);
            assign pop_ev[gi]    = n3_hdr[gi] && n3_last[gi] &&
                                   (n3_is_iack[gi] || n3_is_dack[gi]) &&
                                   (rq_cnt[gi] != 4'd0);
            assign pop_key[gi]   = rq_key[gi][rq_rd[gi][2:0]];
            assign pop_inv[gi]   = rq_inv[gi][rq_rd[gi][2:0]];
        end
    endgenerate

    // the WB_REQ packet in flight on this tile's NoC3 (its address is flit 1)
    reg n3_is_wb_open [0:1];
    always @(posedge clk) begin
        if (!reset_n) begin
            n3_is_wb_open[0] <= 1'b0;
            n3_is_wb_open[1] <= 1'b0;
        end else begin
            if (n3_hdr[0]) n3_is_wb_open[0] <= n3_is_wb[0];
            if (n3_hdr[1]) n3_is_wb_open[1] <= n3_is_wb[1];
        end
    end

    integer ti, ei, qi;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (ti = 0; ti < NTILE; ti = ti + 1) begin
                req_live[ti]   <= 8'd0;
                req_open[ti]   <= 3'd0;
                req_open_v[ti] <= 1'b0;
                req_open_wbg[ti] <= 1'b0;
                rq_wr[ti]      <= 4'd0;
                rq_rd[ti]      <= 4'd0;
                rq_open[ti]    <= 4'd0;
                rq_open_v[ti]  <= 1'b0;
                rq_open_inv[ti]<= 1'b0;
                sh_excl[ti]    <= {NKEY{1'b0}};
                sh_shared[ti]  <= {NKEY{1'b0}};
                for (ei = 0; ei < 8; ei = ei + 1) begin
                    req_key[ti][ei]   <= 4'd0;
                    req_store[ti][ei] <= 1'b0;
                end
                for (qi = 0; qi < QD; qi = qi + 1) begin
                    rq_key[ti][qi] <= 4'd0;
                    rq_inv[ti][qi] <= 1'b0;
                end
            end
        end else begin
            for (ti = 0; ti < NTILE; ti = ti + 1) begin
                // ---- NoC1 out: open a request, then take its address flit ----
                if (n1_hdr[ti]) begin
                    req_open[ti]     <= n1_mid[ti][2:0];
                    req_open_v[ti]   <= n1_is_req[ti];
                    req_open_wbg[ti] <= n1_is_wbg[ti];
                    if (n1_is_req[ti]) req_store[ti][n1_mid[ti][2:0]] <=
                                           (n1_type[ti] == `MSG_TYPE_STORE_REQ);
                end
                if (n1_a1[ti]) begin
                    if (req_open_v[ti]) begin
                        req_key[ti][req_open[ti]] <= n1_key[ti];
                        req_live[ti][req_open[ti]] <= 1'b1;
                    end
                    // A writeback guard says this L1.5 is giving the line up.
                    if (req_open_wbg[ti]) begin
                        sh_excl[ti][n1_key[ti]]   <= 1'b0;
                        sh_shared[ti][n1_key[ti]] <= 1'b0;
                    end
                end

                // ---- NoC2 in: an ack grants, a forward opens a revoke -------
                if (ack_ev[ti]) begin
                    req_live[ti][ack_id[ti]] <= 1'b0;
                    if (req_live[ti][ack_id[ti]]) begin
                        if (ack_write[ti]) begin
                            sh_excl[ti][ack_key[ti]]   <= 1'b1;
                            sh_shared[ti][ack_key[ti]] <= 1'b0;
                        end else if (ack_read[ti]) begin
                            sh_excl[ti][ack_key[ti]]   <= 1'b0;
                            sh_shared[ti][ack_key[ti]] <= 1'b1;
                        end
                    end
                end
                if (n2_hdr[ti]) begin
                    rq_open_v[ti]   <= n2_is_inv[ti] || n2_is_dng[ti];
                    rq_open_inv[ti] <= n2_is_inv[ti];
                end
                if (n2_a1[ti] && rq_open_v[ti]) begin
                    rq_key[ti][rq_wr[ti][2:0]] <= n2_key[ti];
                    rq_inv[ti][rq_wr[ti][2:0]] <= rq_open_inv[ti];
                    rq_wr[ti]                  <= rq_wr[ti] + 4'd1;
                end

                // ---- NoC3 out: a last-subline fwdack retires the head -------
                if (pop_ev[ti]) begin
                    rq_rd[ti] <= rq_rd[ti] + 4'd1;
                    if (pop_inv[ti]) begin
                        sh_excl[ti][pop_key[ti]]   <= 1'b0;
                        sh_shared[ti][pop_key[ti]] <= 1'b0;
                    end else begin
                        sh_excl[ti][pop_key[ti]]   <= 1'b0;
                        sh_shared[ti][pop_key[ti]] <= 1'b1;
                    end
                end
                // ---- NoC3 out: a writeback gives the line up ----------------
                if (n3_a1[ti] && n3_is_wb_open[ti]) begin
                    sh_excl[ti][n3_key[ti]]   <= 1'b0;
                    sh_shared[ti][n3_key[ti]] <= 1'b0;
                end
            end
        end
    end

    // =======================================================================
    // THE PROTECTED TARGETS -- coherence, category 15.
    // =======================================================================

    // No two caches with write permission on one line.
    T_COHERENCE_NO_TWO_WRITERS: assert property (@(posedge clk) disable iff (!reset_n)
        (sh_excl[0] & sh_excl[1]) == {NKEY{1'b0}});

    // A writer excludes a reader on the other tile: no stale shared copy
    // survives while the other tile holds the line for writing.
    T_COHERENCE_EXCL_EXCLUDES_SHARER: assert property (@(posedge clk) disable iff (!reset_n)
        ((sh_excl[0] & sh_shared[1]) == {NKEY{1'b0}}) &&
        ((sh_excl[1] & sh_shared[0]) == {NKEY{1'b0}}));

    // Write serialisation per line: the moment a tile is granted write
    // permission, the other tile holds nothing on that line.
    T_COHERENCE_WRITE_SERIALISED: assert property (@(posedge clk) disable iff (!reset_n)
        (ack_hit[0] && ack_write[0]) |->
            (!sh_excl[1][ack_key[0]] && !sh_shared[1][ack_key[0]]));
    T_COHERENCE_WRITE_SERIALISED_T1: assert property (@(posedge clk) disable iff (!reset_n)
        (ack_hit[1] && ack_write[1]) |->
            (!sh_excl[0][ack_key[1]] && !sh_shared[0][ack_key[1]]));

    // =======================================================================
    // COVERS -- vacuity guards. These say the two-agent states the targets
    // constrain are reachable at all; a target whose covers are unreachable is
    // a statement about a design that never does anything.
    // =======================================================================
    wire both_share_some = |(sh_shared[0] & sh_shared[1]);
    wire [4:0] sh_pop0 = sh_excl[0][0]+sh_excl[0][1]+sh_excl[0][2]+sh_excl[0][3]
                       + sh_excl[0][4]+sh_excl[0][5]+sh_excl[0][6]+sh_excl[0][7]
                       + sh_excl[0][8]+sh_excl[0][9]+sh_excl[0][10]+sh_excl[0][11]
                       + sh_excl[0][12]+sh_excl[0][13]+sh_excl[0][14]+sh_excl[0][15];

    C_TILE0_WRITER: cover property (@(posedge clk) disable iff (!reset_n)
        |sh_excl[0]);
    C_TILE1_WRITER: cover property (@(posedge clk) disable iff (!reset_n)
        |sh_excl[1]);
    C_BOTH_TILES_HOLD_SOMETHING: cover property (@(posedge clk) disable iff (!reset_n)
        (|(sh_excl[0] | sh_shared[0])) && (|(sh_excl[1] | sh_shared[1])));
    C_BOTH_TILES_SHARE_ONE_LINE: cover property (@(posedge clk) disable iff (!reset_n)
        both_share_some);
    C_WRITER_AND_REMOTE_SHARER_DIFFERENT_LINES: cover property (@(posedge clk) disable iff (!reset_n)
        (|sh_excl[0]) && (|sh_shared[1]));
    C_OWNERSHIP_MIGRATES: cover property (@(posedge clk) disable iff (!reset_n)
        (|sh_excl[0]) ##[1:64] (|sh_excl[1]));
    C_TILE0_TWO_WRITE_LINES: cover property (@(posedge clk) disable iff (!reset_n)
        sh_pop0 >= 5'd2);

    C_INV_IN_FLIGHT_T0: cover property (@(posedge clk) disable iff (!reset_n)
        rq_cnt[0] != 4'd0);
    C_INV_IN_FLIGHT_T1: cover property (@(posedge clk) disable iff (!reset_n)
        rq_cnt[1] != 4'd0);
    C_INV_IN_FLIGHT_BOTH: cover property (@(posedge clk) disable iff (!reset_n)
        (rq_cnt[0] != 4'd0) && (rq_cnt[1] != 4'd0));
    C_INV_QUEUE_DEEP: cover property (@(posedge clk) disable iff (!reset_n)
        rq_cnt[0] >= 4'd2);

    C_INV_FWD_SEEN: cover property (@(posedge clk) disable iff (!reset_n)
        n2_hdr[0] && n2_is_inv[0]);
    C_DOWNGRADE_FWD_SEEN: cover property (@(posedge clk) disable iff (!reset_n)
        n2_hdr[0] && n2_is_dng[0]);
    C_FWDACK_SEEN: cover property (@(posedge clk) disable iff (!reset_n)
        n3_hdr[0] && (n3_is_iack[0] || n3_is_dack[0]));
    C_WRITEBACK_SEEN: cover property (@(posedge clk) disable iff (!reset_n)
        n3_hdr[0] && n3_is_wb[0]);
    C_WBGUARD_SEEN: cover property (@(posedge clk) disable iff (!reset_n)
        n1_hdr[0] && n1_is_wbg[0]);
    C_REMOTE_HOME_REQUEST: cover property (@(posedge clk) disable iff (!reset_n)
        n1_hdr[0] && n1_is_req[0] && (n1_dat[0][`MSG_DST_X] == 8'd1));

    C_BOTH_L2_POOLS_LOADED: cover property (@(posedge clk) disable iff (!reset_n)
        (l2_empty_slots[3:0] <= 4'd2) && (l2_empty_slots[7:4] <= 4'd2));
    C_L2_MSHR_FULL_T0: cover property (@(posedge clk) disable iff (!reset_n)
        l2_empty_slots[3:0] == 4'd0);
    C_ALL_TRACKERS_LOADED: cover property (@(posedge clk) disable iff (!reset_n)
        (|l2_mshr_pend) && (|l2_mshr_wait) && (l15_mshr_val != 12'd0));
    C_ALL_FOUR_CORES_ACTIVE: cover property (@(posedge clk) disable iff (!reset_n)
        &core_active);
    C_MEM_ROUND_TRIP: cover property (@(posedge clk) disable iff (!reset_n)
        mem_holding && (|l2_mshr_wait));
    C_MEM_QUEUE_DEEP: cover property (@(posedge clk) disable iff (!reset_n)
        mem_occupancy >= 5'd4);
    C_ALL_CHANNELS_BUSY: cover property (@(posedge clk) disable iff (!reset_n)
        (|noc1_blocked) && (|noc2_blocked) && (|noc3_blocked));
    C_MEM_LINK_BACKPRESSURED: cover property (@(posedge clk) disable iff (!reset_n)
        mem_req_blocked || mem_rsp_blocked);
endmodule
