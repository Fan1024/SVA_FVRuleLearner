// ===========================================================================
// Candidate target assertions for the two-tile OpenPiton coherence subsystem.
//
// Bound into the formal top, so every reference below is a hierarchical name
// from `openpiton_two_tile_coherence_ft`. Nothing here is an assumption.
//
// The oracles are INDEPENDENT of the design's own bookkeeping:
//
//   * a packet framer per observation point (`tt_pkt_framer`), driven only by
//     the MSG_LENGTH field of the header flit that point actually carried, so
//     flit position and packet boundaries are this file's own arithmetic and
//     not any flit-state register in a router, an encoder or a decoder;
//   * FOUR NoC1 shadow queues, one per (source L1.5, destination L2) pair,
//     pushed from what an L1.5 put on the wire and popped from what an L2 took
//     off it -- the two-agent form of `openpiton_pmesh_order`'s four-queue
//     oracle, and the only thing here that can say a request crossed the mesh
//     unchanged and in order;
//   * an outstanding-memory-request set keyed on (requesting L2, MSG_MSHRID),
//     both read off the request packet itself -- the id from flit 0, the
//     requester from flit 2 -- with the issue order and a per-entry age beside
//     it;
//   * a per-tile outstanding-L1.5-request set keyed on the MSG_MSHRID the L1.5
//     itself put on NoC1;
//   * the checker's shadow directory (`u_checker.sh_excl` / `sh_shared`), which
//     is this package's coherence oracle: per line, per tile permission
//     maintained only from observed NoC transactions. The coherence targets
//     below read it; none of them reads `l2_dir`, `rf_l15_mesi` or any other
//     piece of the design's own directory.
//   * saturating wait counters, which is how a fairness / bounded-response /
//     deadlock obligation is written as a safety property.
//
// Field positions from define.tmp.h: MSG_TYPE, MSG_LENGTH, MSG_MSHRID, MSG_MESI
// and the four MSG_DST_* fields live in flit 0; MSG_ADDR_ in flit 1;
// MSG_SRC_CHIPID_ / MSG_SRC_X_ / MSG_SRC_Y_ in flit 2. MSG_LENGTH counts the
// flits AFTER the header flit.
// ===========================================================================

// One packet framer. `idx` is 0 on a header flit and counts body flits after
// it; `hdr` and `a1` mark flit 0 and flit 1 of a packet as they are accepted.
module tt_pkt_framer (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        fire,
    input  wire [63:0] data,
    output wire        hdr,
    output wire        a1,
    output wire        a2,
    output wire [7:0]  idx
);
    reg [7:0] idx_f, len_f;
    assign idx = idx_f;
    assign hdr = fire && (idx_f == 8'd0);
    assign a1  = fire && (idx_f == 8'd1);
    assign a2  = fire && (idx_f == 8'd2);

    always @(posedge clk) begin
        if (!reset_n) begin
            idx_f <= 8'd0;
            len_f <= 8'd0;
        end else if (fire) begin
            if (idx_f == 8'd0) begin
                len_f <= data[`MSG_LENGTH];
                idx_f <= (data[`MSG_LENGTH] == 8'd0) ? 8'd0 : 8'd1;
            end else begin
                idx_f <= (idx_f == len_f) ? 8'd0 : idx_f + 8'd1;
            end
        end
    end
endmodule


module two_tile_targets (input wire clk, input wire reset_n);

    localparam integer QD   = 8;    // NoC1 pair-queue depth
    localparam integer NMEM = 16;   // memory outstanding slots (2 L2s x 8 MSHRs)

    // -------------------------------------------------------------- aliases
    wire t_ready = openpiton_two_tile_coherence_ft.dut_ready;

    // L1.5 pins, per tile
    wire [1:0]   l15_n1_val  = openpiton_two_tile_coherence_ft.l15_n1_val;
    wire [1:0]   l15_n1_rdy  = openpiton_two_tile_coherence_ft.l15_n1_rdy;
    wire [127:0] l15_n1_dat  = openpiton_two_tile_coherence_ft.l15_n1_data;
    wire [1:0]   l15_n2_val  = openpiton_two_tile_coherence_ft.l15_n2_val;
    wire [1:0]   l15_n2_rdy  = openpiton_two_tile_coherence_ft.l15_n2_rdy;
    wire [127:0] l15_n2_dat  = openpiton_two_tile_coherence_ft.l15_n2_data;
    wire [1:0]   l15_n3_val  = openpiton_two_tile_coherence_ft.l15_n3_val;
    wire [1:0]   l15_n3_rdy  = openpiton_two_tile_coherence_ft.l15_n3_rdy;
    wire [127:0] l15_n3_dat  = openpiton_two_tile_coherence_ft.l15_n3_data;

    // L2 pins, per tile
    wire [1:0]   l2_n1_val   = openpiton_two_tile_coherence_ft.l2_n1_val;
    wire [1:0]   l2_n1_rdy   = openpiton_two_tile_coherence_ft.l2_n1_rdy;
    wire [127:0] l2_n1_dat   = openpiton_two_tile_coherence_ft.l2_n1_data;
    wire [1:0]   l2_n2_val   = openpiton_two_tile_coherence_ft.l2_n2_val;
    wire [1:0]   l2_n2_rdy   = openpiton_two_tile_coherence_ft.l2_n2_rdy;
    wire [127:0] l2_n2_dat   = openpiton_two_tile_coherence_ft.l2_n2_data;

    // the off-chip memory link
    wire        mq_val  = openpiton_two_tile_coherence_ft.mem_req_val;
    wire        mq_rdy  = openpiton_two_tile_coherence_ft.mem_req_rdy;
    wire [63:0] mq_dat  = openpiton_two_tile_coherence_ft.mem_req_data;
    wire        ms_val  = openpiton_two_tile_coherence_ft.mem_rsp_val;
    wire        ms_rdy  = openpiton_two_tile_coherence_ft.mem_rsp_rdy;
    wire [63:0] ms_dat  = openpiton_two_tile_coherence_ft.mem_rsp_data;

    // the checker's shadow directory -- this package's coherence oracle
    wire [15:0] sh_excl0   = openpiton_two_tile_coherence_ft.u_checker.sh_excl[0];
    wire [15:0] sh_excl1   = openpiton_two_tile_coherence_ft.u_checker.sh_excl[1];
    wire [15:0] sh_shared0 = openpiton_two_tile_coherence_ft.u_checker.sh_shared[0];
    wire [15:0] sh_shared1 = openpiton_two_tile_coherence_ft.u_checker.sh_shared[1];
    wire [3:0]  rq_cnt0    = openpiton_two_tile_coherence_ft.u_checker.rq_cnt[0];
    wire [3:0]  rq_cnt1    = openpiton_two_tile_coherence_ft.u_checker.rq_cnt[1];

    // L2 MSHR pools, both slices
    wire [15:0] l2_busy  = openpiton_two_tile_coherence_ft.l2_mshr_busy;
    wire [15:0] l2_wait  = openpiton_two_tile_coherence_ft.l2_mshr_wait;
    wire [15:0] l2_pend  = openpiton_two_tile_coherence_ft.l2_mshr_pend;
    wire [7:0]  l2_empty = openpiton_two_tile_coherence_ft.l2_empty_slots;
    wire [11:0] l15_trk  = openpiton_two_tile_coherence_ft.l15_mshr_val;

    wire [1:0]  l2_state_e [0:1][0:7];
    wire [39:0] l2_addr_e  [0:1][0:7];
    wire [2:0]  l2_key_e   [0:1][0:7];
    genvar gt, ge;
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_l2t
            for (ge = 0; ge < 8; ge = ge + 1) begin : g_l2e
                if (gt == 0) begin : g_t0
                    assign l2_state_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[0].u_l2.mshr_wrap.state_mem_f[ge];
                    assign l2_addr_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[0].u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_ADDR];
                    assign l2_key_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[0].u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_CMP_ADDR];
                end else begin : g_t1
                    assign l2_state_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[1].u_l2.mshr_wrap.state_mem_f[ge];
                    assign l2_addr_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[1].u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_ADDR];
                    assign l2_key_e[gt][ge] =
                        openpiton_two_tile_coherence_ft.g_tile[1].u_l2.mshr_wrap.data_mem_f[ge][`L2_MSHR_CMP_ADDR];
                end
            end
        end
    endgenerate

    // L1.5 miss trackers, per tile
    wire [1:0] ld_val   [0:1]; wire [1:0] st_val   [0:1]; wire [1:0] if_val   [0:1];
    wire [1:0] ld_alloc [0:1]; wire [1:0] st_alloc [0:1]; wire [1:0] if_alloc [0:1];
    wire [1:0] ld_free  [0:1]; wire [1:0] st_free  [0:1]; wire [1:0] if_free  [0:1];
    assign ld_val[0]   = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ld_val;
    assign st_val[0]   = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.st_val;
    assign if_val[0]   = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ifill_val;
    assign ld_alloc[0] = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ld_alloc_mask;
    assign st_alloc[0] = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.st_alloc_mask;
    assign if_alloc[0] = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ifill_alloc_mask;
    assign ld_free[0]  = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ld_dealloc_mask;
    assign st_free[0]  = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.st_dealloc_mask;
    assign if_free[0]  = openpiton_two_tile_coherence_ft.g_tile[0].u_l15.mshr.ifill_dealloc_mask;
    assign ld_val[1]   = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ld_val;
    assign st_val[1]   = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.st_val;
    assign if_val[1]   = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ifill_val;
    assign ld_alloc[1] = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ld_alloc_mask;
    assign st_alloc[1] = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.st_alloc_mask;
    assign if_alloc[1] = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ifill_alloc_mask;
    assign ld_free[1]  = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ld_dealloc_mask;
    assign st_free[1]  = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.st_dealloc_mask;
    assign if_free[1]  = openpiton_two_tile_coherence_ft.g_tile[1].u_l15.mshr.ifill_dealloc_mask;

    // ===================================================================
    // ORACLE 1 -- one packet framer per observation point.
    // ===================================================================
    wire        n1o_fire [0:1]; wire n1o_hdr [0:1]; wire n1o_a1 [0:1]; wire n1o_a2 [0:1];
    wire        n2i_fire [0:1]; wire n2i_hdr [0:1]; wire n2i_a1 [0:1]; wire n2i_a2 [0:1];
    wire        n3o_fire [0:1]; wire n3o_hdr [0:1]; wire n3o_a1 [0:1]; wire n3o_a2 [0:1];
    wire        n1i_fire [0:1]; wire n1i_hdr [0:1]; wire n1i_a1 [0:1]; wire n1i_a2 [0:1];
    wire        n2o_fire [0:1]; wire n2o_hdr [0:1]; wire n2o_a1 [0:1]; wire n2o_a2 [0:1];
    wire [7:0]  n1i_idx  [0:1];
    wire [7:0]  n1o_idx  [0:1];
    wire [7:0]  n2i_idx  [0:1];
    wire [7:0]  n3o_idx  [0:1];
    wire [7:0]  n2o_idx  [0:1];

    wire [63:0] n1o_dat [0:1]; wire [63:0] n2i_dat [0:1]; wire [63:0] n3o_dat [0:1];
    wire [63:0] n1i_dat [0:1]; wire [63:0] n2o_dat [0:1];

    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_fr
            assign n1o_dat[gt]  = l15_n1_dat[64*gt +: 64];
            assign n2i_dat[gt]  = l15_n2_dat[64*gt +: 64];
            assign n3o_dat[gt]  = l15_n3_dat[64*gt +: 64];
            assign n1i_dat[gt]  = l2_n1_dat[64*gt +: 64];
            assign n2o_dat[gt]  = l2_n2_dat[64*gt +: 64];
            assign n1o_fire[gt] = l15_n1_val[gt] && l15_n1_rdy[gt];
            assign n2i_fire[gt] = l15_n2_val[gt] && l15_n2_rdy[gt];
            assign n3o_fire[gt] = l15_n3_val[gt] && l15_n3_rdy[gt];
            assign n1i_fire[gt] = l2_n1_val[gt]  && l2_n1_rdy[gt];
            assign n2o_fire[gt] = l2_n2_val[gt]  && l2_n2_rdy[gt];

            tt_pkt_framer f_n1o (.clk(clk), .reset_n(reset_n), .fire(n1o_fire[gt]),
                .data(n1o_dat[gt]), .hdr(n1o_hdr[gt]), .a1(n1o_a1[gt]), .a2(n1o_a2[gt]), .idx(n1o_idx[gt]));
            tt_pkt_framer f_n2i (.clk(clk), .reset_n(reset_n), .fire(n2i_fire[gt]),
                .data(n2i_dat[gt]), .hdr(n2i_hdr[gt]), .a1(n2i_a1[gt]), .a2(n2i_a2[gt]), .idx(n2i_idx[gt]));
            tt_pkt_framer f_n3o (.clk(clk), .reset_n(reset_n), .fire(n3o_fire[gt]),
                .data(n3o_dat[gt]), .hdr(n3o_hdr[gt]), .a1(n3o_a1[gt]), .a2(n3o_a2[gt]), .idx(n3o_idx[gt]));
            tt_pkt_framer f_n1i (.clk(clk), .reset_n(reset_n), .fire(n1i_fire[gt]),
                .data(n1i_dat[gt]), .hdr(n1i_hdr[gt]), .a1(n1i_a1[gt]), .a2(n1i_a2[gt]), .idx(n1i_idx[gt]));
            tt_pkt_framer f_n2o (.clk(clk), .reset_n(reset_n), .fire(n2o_fire[gt]),
                .data(n2o_dat[gt]), .hdr(n2o_hdr[gt]), .a1(n2o_a1[gt]), .a2(n2o_a2[gt]), .idx(n2o_idx[gt]));
        end
    endgenerate

    wire mq_fire = mq_val && mq_rdy;
    wire ms_fire = ms_val && ms_rdy;
    wire mq_hdr, mq_a1, mq_a2; wire [7:0] mq_idx;
    wire ms_hdr, ms_a1, ms_a2; wire [7:0] ms_idx;
    tt_pkt_framer f_mq (.clk(clk), .reset_n(reset_n), .fire(mq_fire), .data(mq_dat),
                        .hdr(mq_hdr), .a1(mq_a1), .a2(mq_a2), .idx(mq_idx));
    tt_pkt_framer f_ms (.clk(clk), .reset_n(reset_n), .fire(ms_fire), .data(ms_dat),
                        .hdr(ms_hdr), .a1(ms_a1), .a2(ms_a2), .idx(ms_idx));

    // ===================================================================
    // ORACLE 2 -- four NoC1 shadow queues, one per (source L1.5, home L2).
    //
    // Pushed from what an L1.5 put on the wire: the id at flit 0, the line at
    // flit 1, the home at flit 0's MSG_DST_X. Popped at the destination L2's
    // flit 2, which is the first flit that names the source. Nothing in the
    // pairing comes from the routers.
    // ===================================================================
    reg [2:0] q_id   [0:1][0:1][0:QD-1];   // [src][dst][slot]
    reg [3:0] q_key  [0:1][0:1][0:QD-1];
    reg       q_st   [0:1][0:1][0:QD-1];
    reg [3:0] q_wr   [0:1][0:1];
    reg [3:0] q_rd   [0:1][0:1];
    wire [3:0] q_cnt [0:1][0:1];

    // the NoC1 packet in flight out of each L1.5
    reg [2:0] o_id  [0:1];
    reg       o_dst [0:1];
    reg       o_st  [0:1];
    reg       o_trk [0:1];      // this packet is a tracked LOAD/STORE request

    // the NoC1 packet in flight into each L2
    reg [2:0] i_id  [0:1];
    reg [3:0] i_key [0:1];
    reg       i_trk [0:1];

    wire [7:0] n1o_type [0:1]; wire [7:0] n1o_mid [0:1]; wire [7:0] n1o_dstx [0:1];
    wire [7:0] n1i_type [0:1]; wire [7:0] n1i_mid [0:1];
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_n1f
            assign n1o_type[gt] = n1o_dat[gt][`MSG_TYPE];
            assign n1o_mid[gt]  = n1o_dat[gt][`MSG_MSHRID];
            assign n1o_dstx[gt] = n1o_dat[gt][`MSG_DST_X];
            assign n1i_type[gt] = n1i_dat[gt][`MSG_TYPE];
            assign n1i_mid[gt]  = n1i_dat[gt][`MSG_MSHRID];
        end
    endgenerate

    wire n1o_is_req [0:1];
    wire n1i_is_req [0:1];
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_n1r
            assign n1o_is_req[gt] = (n1o_type[gt] == `MSG_TYPE_LOAD_REQ) ||
                                    (n1o_type[gt] == `MSG_TYPE_STORE_REQ);
            assign n1i_is_req[gt] = (n1i_type[gt] == `MSG_TYPE_LOAD_REQ) ||
                                    (n1i_type[gt] == `MSG_TYPE_STORE_REQ);
        end
    endgenerate

    assign q_cnt[0][0] = q_wr[0][0] - q_rd[0][0];
    assign q_cnt[0][1] = q_wr[0][1] - q_rd[0][1];
    assign q_cnt[1][0] = q_wr[1][0] - q_rd[1][0];
    assign q_cnt[1][1] = q_wr[1][1] - q_rd[1][1];

    // the pop event at each L2: flit 2 of a tracked NoC1 request names its source
    wire       pop_ev  [0:1];
    wire       pop_src [0:1];
    wire [2:0] pop_hid [0:1];
    wire [3:0] pop_hkey[0:1];
    wire       pop_hst [0:1];
    wire       pop_live[0:1];
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_pop
            assign pop_ev[gt]   = n1i_a2[gt] && i_trk[gt];
            assign pop_src[gt]  = n1i_dat[gt][`MSG_SRC_X_] == 8'd1;
            assign pop_live[gt] = q_cnt[pop_src[gt]][gt] != 4'd0;
            assign pop_hid[gt]  = q_id [pop_src[gt]][gt][q_rd[pop_src[gt]][gt][2:0]];
            assign pop_hkey[gt] = q_key[pop_src[gt]][gt][q_rd[pop_src[gt]][gt][2:0]];
            assign pop_hst[gt]  = q_st [pop_src[gt]][gt][q_rd[pop_src[gt]][gt][2:0]];
        end
    endgenerate

    integer si, di, qi;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (si = 0; si < 2; si = si + 1) begin
                o_id[si] <= 3'd0; o_dst[si] <= 1'b0; o_st[si] <= 1'b0; o_trk[si] <= 1'b0;
                i_id[si] <= 3'd0; i_key[si] <= 4'd0; i_trk[si] <= 1'b0;
                for (di = 0; di < 2; di = di + 1) begin
                    q_wr[si][di] <= 4'd0;
                    q_rd[si][di] <= 4'd0;
                    for (qi = 0; qi < QD; qi = qi + 1) begin
                        q_id[si][di][qi]  <= 3'd0;
                        q_key[si][di][qi] <= 4'd0;
                        q_st[si][di][qi]  <= 1'b0;
                    end
                end
            end
        end else begin
            for (si = 0; si < 2; si = si + 1) begin
                if (n1o_hdr[si]) begin
                    o_id[si]  <= n1o_mid[si][2:0];
                    o_dst[si] <= (n1o_dstx[si] == 8'd1);
                    o_st[si]  <= (n1o_type[si] == `MSG_TYPE_STORE_REQ);
                    o_trk[si] <= n1o_is_req[si];
                end
                if (n1o_a1[si] && o_trk[si]) begin
                    q_id [si][o_dst[si]][q_wr[si][o_dst[si]][2:0]] <= o_id[si];
                    q_key[si][o_dst[si]][q_wr[si][o_dst[si]][2:0]] <= n1o_dat[si][9:6];
                    q_st [si][o_dst[si]][q_wr[si][o_dst[si]][2:0]] <= o_st[si];
                    q_wr [si][o_dst[si]] <= q_wr[si][o_dst[si]] + 4'd1;
                end

                if (n1i_hdr[si]) begin
                    i_id[si]  <= n1i_mid[si][2:0];
                    i_trk[si] <= n1i_is_req[si];
                end
                if (n1i_a1[si]) i_key[si] <= n1i_dat[si][9:6];
                if (pop_ev[si] && pop_live[si])
                    q_rd[pop_src[si]][si] <= q_rd[pop_src[si]][si] + 4'd1;
            end
        end
    end

    // ===================================================================
    // ORACLE 3 -- the outstanding memory-request set, keyed on (L2, mshrid).
    // ===================================================================
    reg [NMEM-1:0] mem_out;
    reg [8:0]      mem_age  [0:NMEM-1];
    reg [7:0]      mem_type [0:NMEM-1];
    reg [3:0]      mem_q    [0:NMEM-1];
    reg [4:0]      mem_q_wr, mem_q_rd;
    reg [7:0]      mem_req_cnt, mem_ack_cnt;

    // the memory request packet in flight
    reg [2:0] mq_id_f;
    reg [7:0] mq_type_f;
    reg       mq_is_mem_f;

    wire [7:0] mq_type = mq_dat[`MSG_TYPE];
    wire [7:0] mq_mid  = mq_dat[`MSG_MSHRID];
    wire [7:0] ms_type = ms_dat[`MSG_TYPE];
    wire mq_is_mem = (mq_type == `MSG_TYPE_LOAD_MEM) || (mq_type == `MSG_TYPE_STORE_MEM);
    wire ms_is_ack = (ms_type == `MSG_TYPE_LOAD_MEM_ACK) || (ms_type == `MSG_TYPE_STORE_MEM_ACK);

    // the requester is named by flit 2 of the request; the ack names its
    // destination in flit 0, and those must be the same L2.
    wire       mq_commit = mq_a2 && mq_is_mem_f;
    wire       mq_src    = (mq_dat[`MSG_SRC_X_] == 8'd1);
    wire [3:0] mq_slot   = {mq_src, mq_id_f};
    wire       ms_ev     = ms_hdr && ms_is_ack;
    wire       ms_dst    = (ms_dat[`MSG_DST_X] == 8'd1);
    wire [7:0] ms_mid    = ms_dat[`MSG_MSHRID];
    wire [3:0] ms_slot   = {ms_dst, ms_mid[2:0]};

    integer mi;
    always @(posedge clk) begin
        if (!reset_n) begin
            mem_out     <= {NMEM{1'b0}};
            mem_q_wr    <= 5'd0;
            mem_q_rd    <= 5'd0;
            mem_req_cnt <= 8'd0;
            mem_ack_cnt <= 8'd0;
            mq_id_f     <= 3'd0;
            mq_type_f   <= 8'd0;
            mq_is_mem_f <= 1'b0;
            for (mi = 0; mi < NMEM; mi = mi + 1) begin
                mem_age[mi]  <= 9'd0;
                mem_type[mi] <= 8'd0;
                mem_q[mi]    <= 4'd0;
            end
        end else begin
            if (mq_hdr) begin
                mq_id_f     <= mq_mid[2:0];
                mq_type_f   <= mq_type;
                mq_is_mem_f <= mq_is_mem;
            end
            for (mi = 0; mi < NMEM; mi = mi + 1) begin
                if (mem_out[mi] && !(ms_ev && (ms_slot == mi[3:0])))
                    mem_age[mi] <= (mem_age[mi] == 9'd511) ? mem_age[mi] : mem_age[mi] + 9'd1;
                else if (!mem_out[mi])
                    mem_age[mi] <= 9'd0;
            end
            if (ms_ev) begin
                mem_out[ms_slot] <= 1'b0;
                mem_age[ms_slot] <= 9'd0;
                mem_q_rd         <= mem_q_rd + 5'd1;
                mem_ack_cnt      <= mem_ack_cnt + 8'd1;
            end
            if (mq_commit) begin
                mem_out[mq_slot]      <= 1'b1;
                mem_age[mq_slot]      <= 9'd0;
                mem_type[mq_slot]     <= mq_type_f;
                mem_q[mem_q_wr[3:0]]  <= mq_slot;
                mem_q_wr              <= mem_q_wr + 5'd1;
                mem_req_cnt           <= mem_req_cnt + 8'd1;
            end
        end
    end

    reg [4:0] mem_out_cnt;
    reg [8:0] mem_age_max;
    integer   ma;
    always @* begin
        mem_out_cnt = 5'd0;
        mem_age_max = 9'd0;
        for (ma = 0; ma < NMEM; ma = ma + 1) begin
            if (mem_out[ma]) begin
                mem_out_cnt = mem_out_cnt + 5'd1;
                if (mem_age[ma] > mem_age_max) mem_age_max = mem_age[ma];
            end
        end
    end

    wire [4:0] mem_q_occ  = mem_q_wr - mem_q_rd;
    wire [3:0] mem_q_head = mem_q[mem_q_rd[3:0]];

    // ===================================================================
    // ORACLE 4 -- the outstanding-L1.5-request set, per tile, keyed on the
    // MSG_MSHRID the L1.5 itself put on NoC1.
    // ===================================================================
    reg [7:0] l15_out  [0:1];
    reg [9:0] l15_age  [0:1][0:7];
    reg [2:0] l15_open [0:1];
    reg       l15_open_v [0:1];

    wire [7:0] n2i_type [0:1]; wire [7:0] n2i_mid [0:1]; wire [1:0] n2i_mesi [0:1];
    wire [7:0] n3o_type [0:1]; wire n3o_last [0:1];
    wire n2i_is_ack [0:1]; wire n2i_is_fwd [0:1]; wire n3o_is_fwdack [0:1];
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_n23
            assign n2i_type[gt] = n2i_dat[gt][`MSG_TYPE];
            assign n2i_mid[gt]  = n2i_dat[gt][`MSG_MSHRID];
            assign n2i_mesi[gt] = n2i_dat[gt][`MSG_MESI];
            assign n3o_type[gt] = n3o_dat[gt][`MSG_TYPE];
            assign n3o_last[gt] = n3o_dat[gt][`MSG_LAST_SUBLINE];
            assign n2i_is_ack[gt] = (n2i_type[gt] == `MSG_TYPE_DATA_ACK) ||
                                    (n2i_type[gt] == `MSG_TYPE_NODATA_ACK);
            assign n2i_is_fwd[gt] = (n2i_type[gt] == `MSG_TYPE_INV_FWD) ||
                                    (n2i_type[gt] == `MSG_TYPE_STORE_FWD) ||
                                    (n2i_type[gt] == `MSG_TYPE_LOAD_FWD);
            assign n3o_is_fwdack[gt] = (n3o_type[gt] == `MSG_TYPE_INV_FWDACK) ||
                                       (n3o_type[gt] == `MSG_TYPE_STORE_FWDACK) ||
                                       (n3o_type[gt] == `MSG_TYPE_LOAD_FWDACK);
        end
    endgenerate

    wire l15_ack_ev [0:1];
    wire [2:0] l15_ack_id [0:1];
    generate
        for (gt = 0; gt < 2; gt = gt + 1) begin : g_ackev
            assign l15_ack_ev[gt] = n2i_hdr[gt] && n2i_is_ack[gt];
            assign l15_ack_id[gt] = n2i_mid[gt][2:0];
        end
    endgenerate

    integer li, lj;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (li = 0; li < 2; li = li + 1) begin
                l15_out[li]    <= 8'd0;
                l15_open[li]   <= 3'd0;
                l15_open_v[li] <= 1'b0;
                for (lj = 0; lj < 8; lj = lj + 1) l15_age[li][lj] <= 10'd0;
            end
        end else begin
            for (li = 0; li < 2; li = li + 1) begin
                for (lj = 0; lj < 8; lj = lj + 1) begin
                    if (l15_out[li][lj] && !(l15_ack_ev[li] && (l15_ack_id[li] == lj[2:0])))
                        l15_age[li][lj] <= (l15_age[li][lj] == 10'd1023) ? l15_age[li][lj]
                                                                        : l15_age[li][lj] + 10'd1;
                    else if (!l15_out[li][lj])
                        l15_age[li][lj] <= 10'd0;
                end
                if (n1o_hdr[li]) begin
                    l15_open[li]   <= n1o_mid[li][2:0];
                    l15_open_v[li] <= n1o_is_req[li];
                end
                if (n1o_a1[li] && l15_open_v[li]) begin
                    l15_out[li][l15_open[li]] <= 1'b1;
                    l15_age[li][l15_open[li]] <= 10'd0;
                end
                if (l15_ack_ev[li]) begin
                    l15_out[li][l15_ack_id[li]] <= 1'b0;
                    l15_age[li][l15_ack_id[li]] <= 10'd0;
                end
            end
        end
    end

    reg [3:0] l15_out_cnt [0:1];
    reg [9:0] l15_age_max [0:1];
    integer   la, lb;
    always @* begin
        for (la = 0; la < 2; la = la + 1) begin
            l15_out_cnt[la] = 4'd0;
            l15_age_max[la] = 10'd0;
            for (lb = 0; lb < 8; lb = lb + 1) begin
                if (l15_out[la][lb]) begin
                    l15_out_cnt[la] = l15_out_cnt[la] + 4'd1;
                    if (l15_age[la][lb] > l15_age_max[la]) l15_age_max[la] = l15_age[la][lb];
                end
            end
        end
    end

    // ===================================================================
    // ORACLE 5 -- forward / forward-ack conservation and age, per tile.
    // ===================================================================
    reg [7:0] fwd_cnt    [0:1];
    reg [7:0] fwdack_cnt [0:1];
    reg [9:0] fwd_age    [0:1];

    integer fj;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (fj = 0; fj < 2; fj = fj + 1) begin
                fwd_cnt[fj] <= 8'd0; fwdack_cnt[fj] <= 8'd0; fwd_age[fj] <= 10'd0;
            end
        end else begin
            for (fj = 0; fj < 2; fj = fj + 1) begin
                if (n2i_hdr[fj] && n2i_is_fwd[fj]) fwd_cnt[fj] <= fwd_cnt[fj] + 8'd1;
                if (n3o_hdr[fj] && n3o_is_fwdack[fj] && n3o_last[fj])
                    fwdack_cnt[fj] <= fwdack_cnt[fj] + 8'd1;
                if (fwd_cnt[fj] == fwdack_cnt[fj])
                    fwd_age[fj] <= 10'd0;
                else
                    fwd_age[fj] <= (fwd_age[fj] == 10'd1023) ? fwd_age[fj] : fwd_age[fj] + 10'd1;
            end
        end
    end

    // ===================================================================
    // ORACLE 6 -- saturating wait counters for the four channels and the
    // off-chip link, plus a global no-progress counter.
    // ===================================================================
    reg [9:0] w_n1 [0:1];
    reg [9:0] w_n2 [0:1];
    reg [9:0] w_n3 [0:1];
    reg [9:0] w_mq, w_ms;
    reg [9:0] w_global;

    wire any_fire = n1o_fire[0] || n1o_fire[1] || n2i_fire[0] || n2i_fire[1]
                 || n3o_fire[0] || n3o_fire[1] || n1i_fire[0] || n1i_fire[1]
                 || n2o_fire[0] || n2o_fire[1] || mq_fire || ms_fire;
    wire any_work = (|l2_busy) || (|l15_trk) || (|mem_out)
                 || (l15_out[0] != 8'd0) || (l15_out[1] != 8'd0);

    integer wi;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (wi = 0; wi < 2; wi = wi + 1) begin
                w_n1[wi] <= 10'd0; w_n2[wi] <= 10'd0; w_n3[wi] <= 10'd0;
            end
            w_mq <= 10'd0; w_ms <= 10'd0; w_global <= 10'd0;
        end else begin
            for (wi = 0; wi < 2; wi = wi + 1) begin
                w_n1[wi] <= (l15_n1_val[wi] && !l15_n1_rdy[wi])
                            ? ((w_n1[wi] == 10'd1023) ? w_n1[wi] : w_n1[wi] + 10'd1) : 10'd0;
                w_n2[wi] <= (l2_n2_val[wi] && !l2_n2_rdy[wi])
                            ? ((w_n2[wi] == 10'd1023) ? w_n2[wi] : w_n2[wi] + 10'd1) : 10'd0;
                w_n3[wi] <= (l15_n3_val[wi] && !l15_n3_rdy[wi])
                            ? ((w_n3[wi] == 10'd1023) ? w_n3[wi] : w_n3[wi] + 10'd1) : 10'd0;
            end
            w_mq <= (mq_val && !mq_rdy) ? ((w_mq == 10'd1023) ? w_mq : w_mq + 10'd1) : 10'd0;
            w_ms <= (ms_val && !ms_rdy) ? ((w_ms == 10'd1023) ? w_ms : w_ms + 10'd1) : 10'd0;
            w_global <= (any_work && !any_fire)
                        ? ((w_global == 10'd1023) ? w_global : w_global + 10'd1) : 10'd0;
        end
    end

    // ===================================================================
    // ORACLE 7 -- per-line write epoch. `ep_owner_v[k]` says some tile is the
    // recorded exclusive owner of key k and `ep_owner[k]` says which;
    // `ep_revoked[k]` says the recorded owner has since acknowledged giving it
    // up. Set only from the ack and fwdack events above.
    // ===================================================================
    reg [15:0] ep_owner_v;
    reg [15:0] ep_owner;
    reg [15:0] ep_revoked;

    // an exclusive grant on this tile, with the line it applies to
    wire       g_ev  [0:1];
    wire [3:0] g_key [0:1];
    wire       ck_hit [0:1];
    assign ck_hit[0] = openpiton_two_tile_coherence_ft.u_checker.ack_hit[0];
    assign ck_hit[1] = openpiton_two_tile_coherence_ft.u_checker.ack_hit[1];
    assign g_key[0]  = openpiton_two_tile_coherence_ft.u_checker.ack_key[0];
    assign g_key[1]  = openpiton_two_tile_coherence_ft.u_checker.ack_key[1];
    assign g_ev[0]   = ck_hit[0] && openpiton_two_tile_coherence_ft.u_checker.ack_write[0];
    assign g_ev[1]   = ck_hit[1] && openpiton_two_tile_coherence_ft.u_checker.ack_write[1];

    wire       r_ev  [0:1];
    wire [3:0] r_key [0:1];
    assign r_ev[0]  = openpiton_two_tile_coherence_ft.u_checker.pop_ev[0];
    assign r_ev[1]  = openpiton_two_tile_coherence_ft.u_checker.pop_ev[1];
    assign r_key[0] = openpiton_two_tile_coherence_ft.u_checker.pop_key[0];
    assign r_key[1] = openpiton_two_tile_coherence_ft.u_checker.pop_key[1];

    always @(posedge clk) begin
        if (!reset_n) begin
            ep_owner_v <= 16'd0;
            ep_owner   <= 16'd0;
            ep_revoked <= 16'd0;
        end else begin
            if (g_ev[0]) begin
                ep_owner_v[g_key[0]] <= 1'b1;
                ep_owner[g_key[0]]   <= 1'b0;
                ep_revoked[g_key[0]] <= 1'b0;
            end
            if (g_ev[1]) begin
                ep_owner_v[g_key[1]] <= 1'b1;
                ep_owner[g_key[1]]   <= 1'b1;
                ep_revoked[g_key[1]] <= 1'b0;
            end
            if (r_ev[0] && ep_owner_v[r_key[0]] && !ep_owner[r_key[0]])
                ep_revoked[r_key[0]] <= 1'b1;
            if (r_ev[1] && ep_owner_v[r_key[1]] &&  ep_owner[r_key[1]])
                ep_revoked[r_key[1]] <= 1'b1;
        end
    end

    // ===================================================================
    // Combinational reductions used by several targets.
    // ===================================================================
    reg       l2_set_dup [0:1];
    reg       l2_line_dup [0:1];
    reg [3:0] l2_busy_cnt [0:1];
    reg       l2_state_illegal;
    integer   ca, cb, cc;
    always @* begin
        l2_state_illegal = 1'b0;
        for (ca = 0; ca < 2; ca = ca + 1) begin
            l2_set_dup[ca]  = 1'b0;
            l2_line_dup[ca] = 1'b0;
            l2_busy_cnt[ca] = 4'd0;
            for (cb = 0; cb < 8; cb = cb + 1) begin
                if (l2_state_e[ca][cb] != `L2_MSHR_STATE_INVAL)
                    l2_busy_cnt[ca] = l2_busy_cnt[ca] + 4'd1;
                if (l2_state_e[ca][cb] == 2'd3) l2_state_illegal = 1'b1;
                for (cc = 0; cc < 8; cc = cc + 1) begin
                    if ((cb != cc)
                        && (l2_state_e[ca][cb] != `L2_MSHR_STATE_INVAL)
                        && (l2_state_e[ca][cc] != `L2_MSHR_STATE_INVAL)) begin
                        if (l2_key_e[ca][cb] == l2_key_e[ca][cc]) l2_set_dup[ca] = 1'b1;
                        if (l2_addr_e[ca][cb][39:6] == l2_addr_e[ca][cc][39:6])
                            l2_line_dup[ca] = 1'b1;
                    end
                end
            end
        end
    end

    // ===================================================================
    // 1. END-TO-END ORDERING
    // ===================================================================
    T_ORDER_NOC1_ID_ARRIVES_IN_SEND_ORDER_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (pop_ev[0] && pop_live[0]) |-> (i_id[0] == pop_hid[0]));
    T_ORDER_MEM_ACK_IN_REQUEST_ORDER: assert property (@(posedge clk) disable iff (!reset_n)
        (ms_ev && (mem_q_occ != 5'd0)) |-> (ms_slot == mem_q_head));
    T_ORDER_L15_REQUEST_TYPE_PRESERVED_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (pop_ev[0] && pop_live[0]) |->
            ((n1i_type[0] == `MSG_TYPE_STORE_REQ) == pop_hst[0]));

    // ===================================================================
    // 2. DATA INTEGRITY
    // ===================================================================
    T_DATA_NOC1_LINE_PRESERVED_ACROSS_MESH_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (pop_ev[0] && pop_live[0]) |-> (i_key[0] == pop_hkey[0]));
    T_DATA_MEM_ACK_TYPE_MATCHES_REQUEST: assert property (@(posedge clk) disable iff (!reset_n)
        (ms_ev && mem_out[ms_slot]) |->
            ((ms_type == `MSG_TYPE_LOAD_MEM_ACK) ==
             (mem_type[ms_slot] == `MSG_TYPE_LOAD_MEM)));
    T_DATA_MEM_ACK_RETURNS_TO_REQUESTER: assert property (@(posedge clk) disable iff (!reset_n)
        ms_ev |-> mem_out[ms_slot]);
    T_DATA_NOC1_HOME_IS_ADDRESS_BIT_6: assert property (@(posedge clk) disable iff (!reset_n)
        (n1o_a1[0] && o_trk[0]) |-> (o_dst[0] == n1o_dat[0][6]));

    // ===================================================================
    // 3. UNIQUENESS / NO DUPLICATION
    // ===================================================================
    T_UNIQ_L15_MSHRID_NOT_REUSED_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (n1o_a1[0] && l15_open_v[0]) |-> !l15_out[0][l15_open[0]]);
    T_UNIQ_MEM_REQ_ID_NOT_REUSED: assert property (@(posedge clk) disable iff (!reset_n)
        mq_commit |-> !mem_out[mq_slot]);
    T_UNIQ_L2_MSHR_SET_ONEHOT_T0: assert property (@(posedge clk) disable iff (!reset_n)
        !l2_set_dup[0]);

    // ===================================================================
    // 4. NO LOSS / CONSERVATION
    // ===================================================================
    T_CONSERV_MEM_REQ_EQ_ACK_PLUS_OUT: assert property (@(posedge clk) disable iff (!reset_n)
        (mem_req_cnt - mem_ack_cnt) == {3'd0, mem_out_cnt});
    T_CONSERV_FWDACK_NEVER_EXCEEDS_FWD_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (fwd_cnt[0] - fwdack_cnt[0]) <= 8'd8);

    // ===================================================================
    // 5. MUTUAL EXCLUSION / ONE-HOT
    // ===================================================================
    T_MUTEX_L2_MSHR_LINE_ONEHOT_T0: assert property (@(posedge clk) disable iff (!reset_n)
        !l2_line_dup[0]);
    T_MUTEX_ONE_EXCLUSIVE_OWNER_PER_LINE: assert property (@(posedge clk) disable iff (!reset_n)
        (sh_excl0 & sh_excl1) == 16'd0);

    // ===================================================================
    // 6. OCCUPANCY AND BOUNDS
    // ===================================================================
    T_BOUND_NOC1_PAIR_QUEUE_LE_DEPTH: assert property (@(posedge clk) disable iff (!reset_n)
        (q_cnt[0][0] <= QD[3:0]) && (q_cnt[0][1] <= QD[3:0]) &&
        (q_cnt[1][0] <= QD[3:0]) && (q_cnt[1][1] <= QD[3:0]));
    T_BOUND_L15_OUTSTANDING_LE_TRACKERS_T0: assert property (@(posedge clk) disable iff (!reset_n)
        l15_out_cnt[0] <= 4'd6);
    T_BOUND_REVOKE_QUEUE_LE_DEPTH: assert property (@(posedge clk) disable iff (!reset_n)
        (rq_cnt0 <= 4'd8) && (rq_cnt1 <= 4'd8));

    // ===================================================================
    // 7. ALLOCATOR DISCIPLINE
    // ===================================================================
    T_ALLOC_L15_TRACKER_NO_REALLOC_LIVE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        ((ld_alloc[0] & ld_val[0] & ~ld_free[0]) == 2'd0) &&
        ((st_alloc[0] & st_val[0] & ~st_free[0]) == 2'd0) &&
        ((if_alloc[0] & if_val[0] & ~if_free[0]) == 2'd0));
    T_ALLOC_L15_TRACKER_NO_FREE_IDLE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        ((ld_free[0] & ~ld_val[0]) == 2'd0) &&
        ((st_free[0] & ~st_val[0]) == 2'd0) &&
        ((if_free[0] & ~if_val[0]) == 2'd0));

    // ===================================================================
    // 8. REQUEST-RESPONSE CORRESPONDENCE
    // ===================================================================
    T_REQRSP_ACK_HAS_OUTSTANDING_REQUEST_T0: assert property (@(posedge clk) disable iff (!reset_n)
        l15_ack_ev[0] |-> l15_out[0][l15_ack_id[0]]);
    T_REQRSP_FWDACK_HAS_PENDING_FWD_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (n3o_hdr[0] && n3o_is_fwdack[0] && n3o_last[0]) |-> (fwd_cnt[0] != fwdack_cnt[0]));
    T_REQRSP_MEM_REQ_NAMES_A_BUSY_ENTRY: assert property (@(posedge clk) disable iff (!reset_n)
        mq_commit |-> (l2_state_e[mq_src][mq_id_f] != `L2_MSHR_STATE_INVAL));

    // ===================================================================
    // 9. PROTOCOL CONFORMANCE
    // ===================================================================
    T_PROTO_NOC1_VAL_STABLE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (l15_n1_val[0] && !l15_n1_rdy[0]) |=> l15_n1_val[0]);
    T_PROTO_NOC1_DATA_STABLE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (l15_n1_val[0] && !l15_n1_rdy[0]) |=> $stable(l15_n1_dat[63:0]));
    T_PROTO_NOC2_VAL_STABLE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (l2_n2_val[0] && !l2_n2_rdy[0]) |=> l2_n2_val[0]);
    T_PROTO_NOC3_VAL_STABLE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (l15_n3_val[0] && !l15_n3_rdy[0]) |=> l15_n3_val[0]);

    // ===================================================================
    // 10. ARBITRATION FAIRNESS (saturating counters, safety encoding)
    // ===================================================================
    T_FAIR_NOC1_ADMITTED_WITHIN_N_T0: assert property (@(posedge clk) disable iff (!reset_n)
        w_n1[0] < 10'd192);
    T_FAIR_MEM_LINK_ADMITTED_WITHIN_N: assert property (@(posedge clk) disable iff (!reset_n)
        w_mq < 10'd192);

    // ===================================================================
    // 11. BOUNDED RESPONSE
    // ===================================================================
    T_BOUNDRSP_MEM_ROUND_TRIP_WITHIN_N: assert property (@(posedge clk) disable iff (!reset_n)
        mem_age_max < 9'd320);
    T_BOUNDRSP_L15_REQUEST_ANSWERED_WITHIN_N_T0: assert property (@(posedge clk) disable iff (!reset_n)
        l15_age_max[0] < 10'd640);
    T_BOUNDRSP_FWD_ACKED_WITHIN_N_T0: assert property (@(posedge clk) disable iff (!reset_n)
        fwd_age[0] < 10'd320);

    // ===================================================================
    // 12. DEADLOCK FREEDOM
    // ===================================================================
    T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk) disable iff (!reset_n)
        w_global < 10'd256);
    T_DEADLOCK_L2_POOL_DRAINS_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (l2_empty[3:0] == 4'd0) |-> (w_global < 10'd128));

    // ===================================================================
    // 13. RESET / INITIALISATION
    // ===================================================================
    T_RESET_L2_MSHR_ALL_INVAL: assert property (@(posedge clk) disable iff (!reset_n)
        !t_ready |-> (l2_busy == 16'd0));
    T_RESET_L15_TRACKERS_IDLE: assert property (@(posedge clk) disable iff (!reset_n)
        !t_ready |-> (l15_trk == 12'd0));
    T_RESET_NO_PERMISSION_HELD: assert property (@(posedge clk) disable iff (!reset_n)
        !t_ready |-> ((sh_excl0 | sh_excl1 | sh_shared0 | sh_shared1) == 16'd0));

    // ===================================================================
    // 14. LIFECYCLE / ACCESS CONTROL
    // ===================================================================
    T_LIFECYCLE_L2_MSHR_STATE_LEGAL: assert property (@(posedge clk) disable iff (!reset_n)
        !l2_state_illegal);
    T_LIFECYCLE_PERMISSION_RISES_ONLY_AT_AN_ACK_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (((sh_excl0 | sh_shared0) & ~$past(sh_excl0 | sh_shared0)) != 16'd0) |->
            $past(ck_hit[0]));
    T_LIFECYCLE_FWD_ONLY_TO_A_HOLDER_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (n2i_a1[0] && openpiton_two_tile_coherence_ft.u_checker.rq_open_v[0]) |->
            (sh_excl0[n2i_dat[0][9:6]] || sh_shared0[n2i_dat[0][9:6]]));

    // ===================================================================
    // 15. COHERENCE
    // ===================================================================
    T_COHERENCE_NO_STALE_SHARER_UNDER_A_WRITER: assert property (@(posedge clk) disable iff (!reset_n)
        ((sh_excl0 & sh_shared1) == 16'd0) && ((sh_excl1 & sh_shared0) == 16'd0));
    T_COHERENCE_WRITE_GRANT_SERIALISED_T0: assert property (@(posedge clk) disable iff (!reset_n)
        g_ev[0] |-> (!sh_excl1[g_key[0]] && !sh_shared1[g_key[0]]));
    T_COHERENCE_OWNERSHIP_MIGRATES_ONLY_AFTER_REVOKE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (g_ev[0] && ep_owner_v[g_key[0]] && ep_owner[g_key[0]]) |-> ep_revoked[g_key[0]]);
    T_COHERENCE_NO_PERMISSION_AFTER_ACKED_INVALIDATE_T0: assert property (@(posedge clk) disable iff (!reset_n)
        (r_ev[0] && openpiton_two_tile_coherence_ft.u_checker.pop_inv[0]) |=>
            (!sh_excl0[$past(r_key[0])] && !sh_shared0[$past(r_key[0])]));
    T_COHERENCE_HOME_SLICE_OWNS_ITS_LINES: assert property (@(posedge clk) disable iff (!reset_n)
        (n1i_a1[0] && i_trk[0]) |-> (n1i_dat[0][6] == 1'b0));

    // ===================================================================
    // COVERS -- one per category, showing the constrained scenario is real.
    // ===================================================================
    C_ORDER_TWO_SOURCES_QUEUED_AT_ONE_HOME: cover property (@(posedge clk) disable iff (!reset_n)
        (q_cnt[0][0] != 4'd0) && (q_cnt[1][0] != 4'd0));
    C_ORDER_PAIR_QUEUE_DEEP: cover property (@(posedge clk) disable iff (!reset_n)
        q_cnt[0][1] >= 4'd2);
    C_DATA_REMOTE_HOME_REQUEST: cover property (@(posedge clk) disable iff (!reset_n)
        n1o_hdr[0] && n1o_is_req[0] && (n1o_dstx[0] == 8'd1));
    C_DATA_LOCAL_HOME_REQUEST: cover property (@(posedge clk) disable iff (!reset_n)
        n1o_hdr[0] && n1o_is_req[0] && (n1o_dstx[0] == 8'd0));
    C_UNIQ_L2_MSHR_TWO_BUSY: cover property (@(posedge clk) disable iff (!reset_n)
        l2_busy_cnt[0] >= 4'd2);
    C_CONSERV_MEM_TWO_OUTSTANDING: cover property (@(posedge clk) disable iff (!reset_n)
        mem_out_cnt >= 5'd2);
    C_CONSERV_MEM_FROM_BOTH_L2S: cover property (@(posedge clk) disable iff (!reset_n)
        (|mem_out[7:0]) && (|mem_out[15:8]));
    C_MUTEX_BOTH_L2_SLICES_BUSY: cover property (@(posedge clk) disable iff (!reset_n)
        (|l2_busy[7:0]) && (|l2_busy[15:8]));
    C_BOUND_L15_THREE_OUTSTANDING: cover property (@(posedge clk) disable iff (!reset_n)
        l15_out_cnt[0] >= 4'd3);
    C_BOUND_BOTH_L15_OUTSTANDING: cover property (@(posedge clk) disable iff (!reset_n)
        (l15_out_cnt[0] != 4'd0) && (l15_out_cnt[1] != 4'd0));
    C_ALLOC_L15_ALLOC_AND_FREE_SAME_CYCLE: cover property (@(posedge clk) disable iff (!reset_n)
        (|ld_alloc[0]) && (|ld_free[0]));
    C_REQRSP_ACK_WHILE_OTHER_OUTSTANDING: cover property (@(posedge clk) disable iff (!reset_n)
        l15_ack_ev[0] && (l15_out_cnt[0] >= 4'd2));
    C_PROTO_NOC1_BACKPRESSURED: cover property (@(posedge clk) disable iff (!reset_n)
        l15_n1_val[0] && !l15_n1_rdy[0]);
    C_PROTO_NOC2_BACKPRESSURED: cover property (@(posedge clk) disable iff (!reset_n)
        l2_n2_val[0] && !l2_n2_rdy[0]);
    C_FAIR_NOC1_WAIT_16: cover property (@(posedge clk) disable iff (!reset_n)
        w_n1[0] >= 10'd16);
    C_FAIR_BOTH_TILES_WAITING: cover property (@(posedge clk) disable iff (!reset_n)
        (w_n1[0] != 10'd0) && (w_n1[1] != 10'd0));
    C_BOUNDRSP_MEM_AGE_32: cover property (@(posedge clk) disable iff (!reset_n)
        mem_age_max >= 9'd32);
    C_BOUNDRSP_L15_AGE_64: cover property (@(posedge clk) disable iff (!reset_n)
        l15_age_max[0] >= 10'd64);
    C_DEADLOCK_NO_PROGRESS_8: cover property (@(posedge clk) disable iff (!reset_n)
        w_global >= 10'd8);
    C_DEADLOCK_BOTH_POOLS_NEARLY_FULL: cover property (@(posedge clk) disable iff (!reset_n)
        (l2_empty[3:0] <= 4'd1) && (l2_empty[7:4] <= 4'd1));
    C_RESET_FIRST_CYCLE: cover property (@(posedge clk) disable iff (!reset_n)
        !t_ready);
    C_LIFECYCLE_FWD_TO_HOLDER: cover property (@(posedge clk) disable iff (!reset_n)
        n2i_hdr[0] && n2i_is_fwd[0]);
    C_LIFECYCLE_FWD_BOTH_TILES: cover property (@(posedge clk) disable iff (!reset_n)
        (fwd_cnt[0] != 8'd0) && (fwd_cnt[1] != 8'd0));
    C_COHERENCE_TILE0_WRITES: cover property (@(posedge clk) disable iff (!reset_n)
        |sh_excl0);
    C_COHERENCE_TILE1_WRITES: cover property (@(posedge clk) disable iff (!reset_n)
        |sh_excl1);
    C_COHERENCE_BOTH_HOLD_DIFFERENT_LINES: cover property (@(posedge clk) disable iff (!reset_n)
        (|sh_excl0) && (|sh_excl1));
    C_COHERENCE_SHARED_BY_BOTH: cover property (@(posedge clk) disable iff (!reset_n)
        |(sh_shared0 & sh_shared1));
    C_COHERENCE_WRITE_MIGRATION: cover property (@(posedge clk) disable iff (!reset_n)
        g_ev[0] && ep_owner_v[g_key[0]] && ep_owner[g_key[0]]);
    C_COHERENCE_REVOKE_THEN_REGRANT: cover property (@(posedge clk) disable iff (!reset_n)
        (r_ev[0]) ##[1:64] (g_ev[1]));
    C_COHERENCE_WRITER_AND_REMOTE_READER: cover property (@(posedge clk) disable iff (!reset_n)
        (|sh_excl0) && (|sh_shared1));
endmodule

// ---------------------------------------------------------------------------
// BIND. Added 2026-08-19: without it `two_tile_targets` is declared and never
// instantiated, so it compiles perfectly and elaborates to NOTHING -- Jasper
// sees no instance and none of the assertions above become properties. The
// first 8 h screen against this package reported `METRIC assertions 4`, the
// checker's four, with 44 stranded.
//
// `checker_reset_n` rather than the raw `reset_n`, matching how the FT wires
// its own checker: the oracle must be released from reset on the same edge the
// checker is, or its shadow state is a cycle out of step with what it shadows.
bind openpiton_two_tile_coherence_ft two_tile_targets
     u_targets_openpiton_two_tile_coherence (.clk(clk), .reset_n(checker_reset_n));
