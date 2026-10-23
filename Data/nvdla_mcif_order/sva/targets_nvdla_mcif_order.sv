// ===========================================================================
// Candidate target assertions for the NVDLA MCIF read subsystem.
//
// Bound into the formal top, so every reference below is a hierarchical name
// from `nvdla_mcif_order_ft`.  NOTHING HERE IS AN ASSUMPTION -- the twelve the
// task already carries live in sva/nvdla_mcif_order_checker.sv and this file
// adds none.
//
// What the design does under the frozen configuration (NCLIENT=4, 256-byte
// aligned eight-atom commands, reg2dp_rd_os_cnt=15, unit weights on clients
// 0..3 and zero weight on the six tied-off ones):
//
//   one 256-byte client command
//     -> BPT: one single-transaction bpt2arb request (size 7, ftran & ltran)
//     -> the weighted round-robin arbiter (unit weights == plain round robin)
//     -> SPT: four consecutive beats at 256-byte offsets 0,2,4,6, and the SPT
//        holds the arbiter off until the fourth, so the AXI stream is runs of
//        four with one ID
//     -> CVT: four AXI reads, arlen=0, addresses A, A+64, A+128, A+192
//     -> four AXI read-data beats
//     -> EG: shared input pipe -> per-client latency FIFO -> round robin ->
//        the two 256-bit reorder FIFOs -> the per-client output pipe
//     -> four 64-byte client responses, mask 2'b11, data unswizzled.
//
// The ORACLES are this file's own and independent of the design's bookkeeping:
//
//   * a per-client shadow command queue holding only the address bits the
//     client itself drove, plus this file's own 0..3 expansion index, so the
//     expected AXI address is arithmetic done here and nowhere in the design;
//   * per-client difference counters -- atoms owed, beats owed, response atoms
//     owed, public outstanding, egress input pipe -- driven only by the four
//     public handshakes;
//   * per-client 512-bit XOR accumulators on the two sides of the egress,
//     which catch a dropped, duplicated or corrupted beat by content and do
//     not repeat the package checker's positional data FIFO;
//   * saturating counters, which is how a fairness, bounded-response or
//     deadlock obligation is written as a safety property.  There is no
//     s_eventually and no unbounded liveness anywhere in this file.
//
// TWO THINGS A READER OF A RESULT FROM THIS FILE NEEDS.
//
// 1. RESET.  The oracles are reset-initialised and every claim is stated for a
//    run that starts in the design's reset state.  If one of these is promoted
//    to a target, its oracle registers have to join the task's `design_keep`
//    pattern exactly as `u_checker.*` already does -- otherwise the reset cut
//    starts them arbitrary and the claim is falsified at cycle 0 for a reason
//    that is not the design's.
//
// 2. THE REORDER FIFO'S OUTPUT REGISTERS.  `ro_rd_count_p` is the reorder
//    FIFO's RAM occupancy only; that FIFO also carries two output-side holding
//    registers this file does not read.  Every claim that adds egress
//    occupancy up is therefore written as an INEQUALITY (`>=`), never as an
//    equality, so an unread stage can never manufacture a failure.
// ===========================================================================

module nvdla_mcif_targets (input wire clk, input wire reset_n);

   localparam integer NC = 4;    // active clients: 0 bdma, 1 sdp, 2 pdp, 3 cdp
   localparam integer QD = 8;    // shadow command-queue depth per client

   // the bounds asserted below, gathered so the numbers are readable
   localparam [9:0] N_OS_WINDOW   = 10'd16;   // reg2dp_rd_os_cnt + 1
   localparam [9:0] N_CLIENT_HOLD = 10'd20;   // 2 pipe + 4 lat + 6 ro + 2 pipe
   localparam [5:0] N_ARB_BYPASS  = 6'd12;    // ten sources, one grant apiece
   localparam [9:0] N_DRAIN       = 10'd128;
   localparam [9:0] N_ISSUE       = 10'd128;
   localparam [9:0] N_STALL       = 10'd256;

   // ------------------------------------------------------------- boundary
   wire [3:0]    req_valid = nvdla_mcif_order_ft.req_valid;
   wire [3:0]    req_ready = nvdla_mcif_order_ft.req_ready;
   wire [315:0]  req_pd    = nvdla_mcif_order_ft.req_pd_flat;
   wire [3:0]    rsp_valid = nvdla_mcif_order_ft.rsp_valid;
   wire [3:0]    rsp_ready = nvdla_mcif_order_ft.rsp_ready;
   wire [2055:0] rsp_pd    = nvdla_mcif_order_ft.rsp_pd_flat;

   wire          ar_valid  = nvdla_mcif_order_ft.mcif2noc_axi_ar_arvalid;
   wire          ar_ready  = nvdla_mcif_order_ft.mcif2noc_axi_ar_arready;
   wire [7:0]    ar_id     = nvdla_mcif_order_ft.mcif2noc_axi_ar_arid;
   wire [3:0]    ar_len    = nvdla_mcif_order_ft.mcif2noc_axi_ar_arlen;
   wire [63:0]   ar_addr   = nvdla_mcif_order_ft.mcif2noc_axi_ar_araddr;

   wire          r_valid   = nvdla_mcif_order_ft.noc2mcif_axi_r_rvalid;
   wire          r_ready   = nvdla_mcif_order_ft.noc2mcif_axi_r_rready;
   wire [7:0]    r_id      = nvdla_mcif_order_ft.noc2mcif_axi_r_rid;
   wire [511:0]  r_data    = nvdla_mcif_order_ft.noc2mcif_axi_r_rdata;

   wire       ar_fire   = ar_valid && ar_ready;
   wire       r_fire    = r_valid  && r_ready;
   wire [3:0] req_fire  = req_valid & req_ready;
   wire [3:0] rsp_fire  = rsp_valid & rsp_ready;

   wire       ar_active = (ar_id[7:2] == 6'd0);
   wire       r_active  = (r_id[7:2]  == 6'd0);
   wire [1:0] ar_c      = ar_id[1:0];
   wire [1:0] r_c       = r_id[1:0];

   wire [3:0] ar_fire_c = { (ar_fire && ar_active && (ar_c == 2'd3)),
                            (ar_fire && ar_active && (ar_c == 2'd2)),
                            (ar_fire && ar_active && (ar_c == 2'd1)),
                            (ar_fire && ar_active && (ar_c == 2'd0)) };
   wire [3:0] r_fire_c  = { (r_fire && r_active && (r_c == 2'd3)),
                            (r_fire && r_active && (r_c == 2'd2)),
                            (r_fire && r_active && (r_c == 2'd1)),
                            (r_fire && r_active && (r_c == 2'd0)) };

   // the six tied-off clients, whose response channels must stay silent
   wire [5:0] dead_rsp_valid = {
        nvdla_mcif_order_ft.mcif2cdma_wt_rd_rsp_valid,
        nvdla_mcif_order_ft.mcif2cdma_dat_rd_rsp_valid,
        nvdla_mcif_order_ft.mcif2sdp_e_rd_rsp_valid,
        nvdla_mcif_order_ft.mcif2sdp_n_rd_rsp_valid,
        nvdla_mcif_order_ft.mcif2sdp_b_rd_rsp_valid,
        nvdla_mcif_order_ft.mcif2rbk_rd_rsp_valid };

   // ------------------------------------------------------- design windows
   wire [8:0] os_cnt   = nvdla_mcif_order_ft.dut.u_ig.u_cvt.os_cnt;
   wire       os_sub_d = nvdla_mcif_order_ft.dut.u_ig.u_cvt.eg2ig_axi_vld_d;

   wire [9:0] ig_gnt = nvdla_mcif_order_ft.dut.u_ig.u_arb.arb_gnt;
   wire [9:0] ig_req = {
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src9_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src8_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src7_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src6_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src5_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src4_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src3_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src2_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src1_req,
        nvdla_mcif_order_ft.dut.u_ig.u_arb.src0_req };
   wire ig_arb_ready = nvdla_mcif_order_ft.dut.u_ig.u_arb.arb2spt_req_ready;

   wire [9:0] eg_gnt = {
        nvdla_mcif_order_ft.dut.u_eg.src9_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src8_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src7_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src6_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src5_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src4_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src3_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src2_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src1_gnt,
        nvdla_mcif_order_ft.dut.u_eg.src0_gnt };
   wire [9:0] eg_req = {
        nvdla_mcif_order_ft.dut.u_eg.src9_req,
        nvdla_mcif_order_ft.dut.u_eg.src8_req,
        nvdla_mcif_order_ft.dut.u_eg.src7_req,
        nvdla_mcif_order_ft.dut.u_eg.src6_req,
        nvdla_mcif_order_ft.dut.u_eg.src5_req,
        nvdla_mcif_order_ft.dut.u_eg.src4_req,
        nvdla_mcif_order_ft.dut.u_eg.src3_req,
        nvdla_mcif_order_ft.dut.u_eg.src2_req,
        nvdla_mcif_order_ft.dut.u_eg.src1_req,
        nvdla_mcif_order_ft.dut.u_eg.src0_req };

   // the latency-FIFO write demultiplexer, one bit per public AXI ID
   wire [9:0] lat_wr_pvld = {
        nvdla_mcif_order_ft.dut.u_eg.rq9_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq8_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq7_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq6_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq5_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq4_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq3_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq2_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq1_wr_pvld,
        nvdla_mcif_order_ft.dut.u_eg.rq0_wr_pvld };

   // the shared context queue: a 255-entry free-list allocator
   wire [254:0] cq_free     = nvdla_mcif_order_ft.dut.u_cq.free_adr_mask;
   wire [255:0] cq_free_ext = {1'b0, cq_free};   // bit 255 reads "not free"
   wire [8:0]   cq_count    = nvdla_mcif_order_ft.dut.u_cq.cq_wr_count;
   wire         cq_busy     = nvdla_mcif_order_ft.dut.u_cq.cq_wr_busy_int;
   wire         cq_push     = nvdla_mcif_order_ft.dut.u_cq.wr_pushing;
   wire [7:0]   cq_push_adr = nvdla_mcif_order_ft.dut.u_cq.free_adr_index;
   wire         cq_pop      = nvdla_mcif_order_ft.dut.u_cq.rd_popping;
   wire [7:0]   cq_pop_adr  = nvdla_mcif_order_ft.dut.u_cq.rd_popping_adr;
   wire         cq_wr_pvld  = nvdla_mcif_order_ft.dut.u_cq.cq_wr_pvld;
   wire [3:0]   cq_wr_tid   = nvdla_mcif_order_ft.dut.u_cq.cq_wr_thread_id;

   // the egress input pipe, shared by all ten clients
   wire       p1_pv  = nvdla_mcif_order_ft.dut.u_eg.pipe_p1.p1_pipe_valid;
   wire       p1_sv  = nvdla_mcif_order_ft.dut.u_eg.pipe_p1.p1_skid_valid;
   wire [3:0] p1_pid = nvdla_mcif_order_ft.dut.u_eg.pipe_p1.p1_pipe_data[515:512];
   wire [3:0] p1_sid = nvdla_mcif_order_ft.dut.u_eg.pipe_p1.p1_skid_data[515:512];
   wire       eg2ig  = nvdla_mcif_order_ft.dut.u_eg.eg2ig_axi_vld;

   // per-client egress occupancy (ro counts are RAM occupancy only)
   wire [2:0] lat_cnt [0:3];
   wire [2:0] ro0_cnt [0:3];
   wire [2:0] ro1_cnt [0:3];
   wire       out_pv  [0:3];
   wire       out_sv  [0:3];

   assign lat_cnt[0] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo0.rq_rd_count;
   assign lat_cnt[1] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo1.rq_rd_count;
   assign lat_cnt[2] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo2.rq_rd_count;
   assign lat_cnt[3] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo3.rq_rd_count;
   assign ro0_cnt[0] = nvdla_mcif_order_ft.dut.u_eg.ro0_fifo0.ro_rd_count_p;
   assign ro0_cnt[1] = nvdla_mcif_order_ft.dut.u_eg.ro1_fifo0.ro_rd_count_p;
   assign ro0_cnt[2] = nvdla_mcif_order_ft.dut.u_eg.ro2_fifo0.ro_rd_count_p;
   assign ro0_cnt[3] = nvdla_mcif_order_ft.dut.u_eg.ro3_fifo0.ro_rd_count_p;
   assign ro1_cnt[0] = nvdla_mcif_order_ft.dut.u_eg.ro0_fifo1.ro_rd_count_p;
   assign ro1_cnt[1] = nvdla_mcif_order_ft.dut.u_eg.ro1_fifo1.ro_rd_count_p;
   assign ro1_cnt[2] = nvdla_mcif_order_ft.dut.u_eg.ro2_fifo1.ro_rd_count_p;
   assign ro1_cnt[3] = nvdla_mcif_order_ft.dut.u_eg.ro3_fifo1.ro_rd_count_p;
   assign out_pv[0]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p2.p2_pipe_valid;
   assign out_pv[1]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p3.p3_pipe_valid;
   assign out_pv[2]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p4.p4_pipe_valid;
   assign out_pv[3]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p5.p5_pipe_valid;
   assign out_sv[0]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p2.p2_skid_valid;
   assign out_sv[1]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p3.p3_skid_valid;
   assign out_sv[2]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p4.p4_skid_valid;
   assign out_sv[3]  = nvdla_mcif_order_ft.dut.u_eg.pipe_p5.p5_skid_valid;

   // the six tied-off clients' latency FIFOs, which must never take a beat
   wire [2:0] dead_lat_cnt [0:5];
   assign dead_lat_cnt[0] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo4.rq_rd_count;
   assign dead_lat_cnt[1] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo5.rq_rd_count;
   assign dead_lat_cnt[2] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo6.rq_rd_count;
   assign dead_lat_cnt[3] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo7.rq_rd_count;
   assign dead_lat_cnt[4] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo8.rq_rd_count;
   assign dead_lat_cnt[5] = nvdla_mcif_order_ft.dut.u_eg.lat_fifo9.rq_rd_count;

   // per-client BPT latency-FIFO credit counters and transaction counters
   wire [7:0]  bpt_lat [0:3];
   wire [12:0] bpt_cnt_req [0:3];
   assign bpt_lat[0] = nvdla_mcif_order_ft.dut.u_ig.u_bpt0.lat_count_cnt;
   assign bpt_lat[1] = nvdla_mcif_order_ft.dut.u_ig.u_bpt1.lat_count_cnt;
   assign bpt_lat[2] = nvdla_mcif_order_ft.dut.u_ig.u_bpt2.lat_count_cnt;
   assign bpt_lat[3] = nvdla_mcif_order_ft.dut.u_ig.u_bpt3.lat_count_cnt;
   assign bpt_cnt_req[0] = nvdla_mcif_order_ft.dut.u_ig.u_bpt0.count_req;
   assign bpt_cnt_req[1] = nvdla_mcif_order_ft.dut.u_ig.u_bpt1.count_req;
   assign bpt_cnt_req[2] = nvdla_mcif_order_ft.dut.u_ig.u_bpt2.count_req;
   assign bpt_cnt_req[3] = nvdla_mcif_order_ft.dut.u_ig.u_bpt3.count_req;

   wire [1:0] spt_beat = nvdla_mcif_order_ft.dut.u_ig.u_spt.beat_count;

   wire [1:0] eg_cq_lens    = nvdla_mcif_order_ft.dut.u_eg.arb_cq_lens;
   wire       eg_cq_swizzle = nvdla_mcif_order_ft.dut.u_eg.arb_cq_swizzle;
   wire       eg_cq_odd     = nvdla_mcif_order_ft.dut.u_eg.arb_cq_odd;
   wire [1:0] eg_wen        = nvdla_mcif_order_ft.dut.u_eg.arb_wen;

   wire [9:0] ig_wrr = nvdla_mcif_order_ft.dut.u_ig.u_arb.u_read_ig_arb.wrr_gnt;
   wire [9:0] eg_wrr = nvdla_mcif_order_ft.dut.u_eg.u_read_eg_arb.wrr_gnt;

   // =====================================================================
   // ORACLE 1 -- a per-client shadow command queue.  It stores only the top
   // 56 address bits the client itself drove, plus this file's own 0..3
   // expansion index, so the expected AXI address is
   //     { queued A[63:8], own index, 6'b0 }
   // which is arithmetic done here and nowhere in the design.  `q_ovf` latches
   // if the queue would ever wrap and every claim that reads the queue is
   // gated on it, so an overflow can never manufacture a failure.
   // =====================================================================
   reg [55:0] q_addr [0:(4*QD)-1];
   reg [2:0]  q_wr [0:3];
   reg [2:0]  q_rd [0:3];
   reg [3:0]  q_occ [0:3];
   reg        q_ovf [0:3];
   reg [1:0]  sub [0:3];

   wire [3:0] cmd_pop = { (ar_fire_c[3] && (sub[3] == 2'd3)),
                          (ar_fire_c[2] && (sub[2] == 2'd3)),
                          (ar_fire_c[1] && (sub[1] == 2'd3)),
                          (ar_fire_c[0] && (sub[0] == 2'd3)) };

   // =====================================================================
   // ORACLE 2 -- difference counters driven only by the public handshakes.
   // =====================================================================
   reg [9:0] atoms_owed [0:3];      // 4 per accepted command, -1 per AXI read
   reg [9:0] beats_owed [0:3];      // AXI beats returned, not yet delivered
   reg [9:0] rsp_atoms  [0:3];      // 4 per accepted command, -1 per response
   reg [9:0] pub_out;               // AXI reads issued, not yet returned
   reg [2:0] eg_in_pipe;            // beats accepted, not yet in a lat FIFO

   // =====================================================================
   // ORACLE 3 -- per-client 512-bit XOR accumulators on the two sides of the
   // egress.  Catches a dropped, duplicated or corrupted beat by content.
   // =====================================================================
   reg [511:0] r_xor   [0:3];
   reg [511:0] rsp_xor [0:3];

   // ORACLE 4 -- the global AXI issue-run oracle.
   reg [1:0] g_sub;
   reg [3:0] g_id;

   // ORACLE 5 -- saturating counters.  Every fairness, bounded-response and
   // deadlock claim below is the safety statement that one never passes its
   // bound.  None of them is a liveness property.
   reg [5:0] ctr_ig_bypass [0:3];
   reg [5:0] ctr_eg_bypass [0:3];
   reg [9:0] ctr_drain;
   reg [9:0] ctr_issue;
   reg [9:0] ctr_stall;

   reg [3:0] rsp_stall_q;
   reg       post_reset;

   wire all_rsp_ready = &rsp_ready;
   wire any_rsp_fire  = |rsp_fire;
   wire any_beat_owed = (beats_owed[0] != 0) || (beats_owed[1] != 0)
                     || (beats_owed[2] != 0) || (beats_owed[3] != 0);
   wire any_atom_owed = (atoms_owed[0] != 0) || (atoms_owed[1] != 0)
                     || (atoms_owed[2] != 0) || (atoms_owed[3] != 0);
   // below this the outstanding window cannot be the reason nothing moves
   wire window_open   = (pub_out < 10'd8);
   wire ig_evt        = |ig_gnt;
   wire eg_evt        = |eg_gnt;

   integer i;
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         for (i = 0; i < NC; i = i + 1) begin
            q_wr[i]       <= 3'd0;
            q_rd[i]       <= 3'd0;
            q_occ[i]      <= 4'd0;
            q_ovf[i]      <= 1'b0;
            sub[i]        <= 2'd0;
            atoms_owed[i] <= 10'd0;
            beats_owed[i] <= 10'd0;
            rsp_atoms[i]  <= 10'd0;
            r_xor[i]      <= 512'd0;
            rsp_xor[i]    <= 512'd0;
            ctr_ig_bypass[i] <= 6'd0;
            ctr_eg_bypass[i] <= 6'd0;
         end
         pub_out     <= 10'd0;
         eg_in_pipe  <= 3'd0;
         g_sub       <= 2'd0;
         g_id        <= 4'd0;
         ctr_drain   <= 10'd0;
         ctr_issue   <= 10'd0;
         ctr_stall   <= 10'd0;
         rsp_stall_q <= 4'd0;
         post_reset  <= 1'b0;
      end else begin
         post_reset  <= 1'b1;
         rsp_stall_q <= rsp_valid & ~rsp_ready;

         pub_out    <= pub_out    + (ar_fire ? 10'd1 : 10'd0)
                                  - (r_fire  ? 10'd1 : 10'd0);
         eg_in_pipe <= eg_in_pipe + (r_fire ? 3'd1 : 3'd0)
                                  - (eg2ig  ? 3'd1 : 3'd0);

         if (ar_fire) begin
            if (g_sub == 2'd0) g_id <= ar_id[3:0];
            g_sub <= g_sub + 2'd1;
         end

         for (i = 0; i < NC; i = i + 1) begin
            if (req_fire[i]) begin
               q_addr[(i*QD) + q_wr[i]] <= req_pd[(i*79) + 8 +: 56];
               q_wr[i] <= q_wr[i] + 3'd1;
               if (q_occ[i] == QD) q_ovf[i] <= 1'b1;
            end
            if (cmd_pop[i]) q_rd[i] <= q_rd[i] + 3'd1;

            case ({req_fire[i], cmd_pop[i]})
               2'b10:   q_occ[i] <= q_occ[i] + 4'd1;
               2'b01:   q_occ[i] <= q_occ[i] - 4'd1;
               default: begin end
            endcase

            if (ar_fire_c[i]) sub[i] <= sub[i] + 2'd1;

            atoms_owed[i] <= atoms_owed[i] + (req_fire[i]  ? 10'd4 : 10'd0)
                                           - (ar_fire_c[i] ? 10'd1 : 10'd0);
            beats_owed[i] <= beats_owed[i] + (r_fire_c[i]  ? 10'd1 : 10'd0)
                                           - (rsp_fire[i]  ? 10'd1 : 10'd0);
            rsp_atoms[i]  <= rsp_atoms[i]  + (req_fire[i]  ? 10'd4 : 10'd0)
                                           - (rsp_fire[i]  ? 10'd1 : 10'd0);

            if (r_fire_c[i]) r_xor[i]   <= r_xor[i]   ^ r_data;
            if (rsp_fire[i]) rsp_xor[i] <= rsp_xor[i] ^ rsp_pd[(i*514) +: 512];

            if (!ig_evt)
               ctr_ig_bypass[i] <= ctr_ig_bypass[i];
            else if (ig_req[i] && !ig_gnt[i])
               ctr_ig_bypass[i] <= (ctr_ig_bypass[i] == 6'd63)
                                    ? ctr_ig_bypass[i] : ctr_ig_bypass[i] + 6'd1;
            else
               ctr_ig_bypass[i] <= 6'd0;

            if (!eg_evt)
               ctr_eg_bypass[i] <= ctr_eg_bypass[i];
            else if (eg_req[i] && !eg_gnt[i])
               ctr_eg_bypass[i] <= (ctr_eg_bypass[i] == 6'd63)
                                    ? ctr_eg_bypass[i] : ctr_eg_bypass[i] + 6'd1;
            else
               ctr_eg_bypass[i] <= 6'd0;
         end

         ctr_drain <= !(all_rsp_ready && any_beat_owed && !any_rsp_fire) ? 10'd0
                    : (ctr_drain == 10'd1023) ? ctr_drain : ctr_drain + 10'd1;

         ctr_issue <= !(ar_ready && any_atom_owed && !ar_fire && window_open)
                        ? 10'd0
                    : (ctr_issue == 10'd1023) ? ctr_issue : ctr_issue + 10'd1;

         ctr_stall <= !(ar_ready && all_rsp_ready && window_open
                        && (any_atom_owed || any_beat_owed)
                        && !(ar_fire || r_fire || any_rsp_fire)) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   // ------------------------------------------------- derived oracle views
   // Distinct places a returned beat for one client can sit.  The reorder
   // FIFO's two output-side registers are deliberately NOT here, which is
   // why every claim built on `held` is an inequality.
   wire [9:0] held [0:3];
   assign held[0] = {9'd0, (p1_pv && (p1_pid == 4'd0))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd0))}
                  + {7'd0, lat_cnt[0]} + {7'd0, ro0_cnt[0]}
                  + {9'd0, out_pv[0]} + {9'd0, out_sv[0]};
   assign held[1] = {9'd0, (p1_pv && (p1_pid == 4'd1))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd1))}
                  + {7'd0, lat_cnt[1]} + {7'd0, ro0_cnt[1]}
                  + {9'd0, out_pv[1]} + {9'd0, out_sv[1]};
   assign held[2] = {9'd0, (p1_pv && (p1_pid == 4'd2))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd2))}
                  + {7'd0, lat_cnt[2]} + {7'd0, ro0_cnt[2]}
                  + {9'd0, out_pv[2]} + {9'd0, out_sv[2]};
   assign held[3] = {9'd0, (p1_pv && (p1_pid == 4'd3))}
                  + {9'd0, (p1_sv && (p1_sid == 4'd3))}
                  + {7'd0, lat_cnt[3]} + {7'd0, ro0_cnt[3]}
                  + {9'd0, out_pv[3]} + {9'd0, out_sv[3]};

   wire [63:0] expect_ar_addr [0:3];
   assign expect_ar_addr[0] = {q_addr[(0*QD) + q_rd[0]], sub[0], 6'd0};
   assign expect_ar_addr[1] = {q_addr[(1*QD) + q_rd[1]], sub[1], 6'd0};
   assign expect_ar_addr[2] = {q_addr[(2*QD) + q_rd[2]], sub[2], 6'd0};
   assign expect_ar_addr[3] = {q_addr[(3*QD) + q_rd[3]], sub[3], 6'd0};

   // an AXI read whose originating client command this file actually watched
   wire ar_checkable = ar_fire && ar_active
                    && !q_ovf[ar_c] && (q_occ[ar_c] != 4'd0);
   wire [63:0] ar_expect = expect_ar_addr[ar_c];

   wire clients_drained = (beats_owed[0] == 0) && (beats_owed[1] == 0)
                       && (beats_owed[2] == 0) && (beats_owed[3] == 0);
   wire xor_matches = (r_xor[0] == rsp_xor[0]) && (r_xor[1] == rsp_xor[1])
                   && (r_xor[2] == rsp_xor[2]) && (r_xor[3] == rsp_xor[3]);

   // popcount of the context queue's free list
   reg [8:0] cq_free_pop;
   integer f;
   always @* begin
      cq_free_pop = 9'd0;
      for (f = 0; f < 255; f = f + 1)
         if (cq_free[f]) cq_free_pop = cq_free_pop + 9'd1;
   end

   // =====================================================================
   // 1 -- END-TO-END ORDERING
   // =====================================================================
   T_ORDER_AR_SUBBEAT_ASCENDS: assert property (@(posedge clk)
      disable iff (!reset_n)
      ar_checkable |-> (ar_addr[7:6] == sub[ar_c]));

   T_ORDER_AR_RUN_CARRIES_ONE_ID: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ar_fire && (g_sub != 2'd0)) |-> (ar_id[3:0] == g_id));

   T_ORDER_AR_PER_CLIENT_INDEX_IS_GLOBAL: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ar_fire && ar_active) |-> (sub[ar_c] == g_sub));

   // =====================================================================
   // 2 -- DATA INTEGRITY
   // =====================================================================
   T_DATA_AR_ADDR_IS_HEAD_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      ar_checkable |-> (ar_addr[63:8] == ar_expect[63:8]));

   T_DATA_XOR_CONSERVED_WHEN_DRAINED: assert property (@(posedge clk)
      disable iff (!reset_n)
      clients_drained |-> xor_matches);

   T_DATA_EG_CONTEXT_IS_SINGLE_FULL_BEAT: assert property (@(posedge clk)
      disable iff (!reset_n)
      eg_evt |-> ((eg_cq_lens == 2'd0) && !eg_cq_swizzle && !eg_cq_odd));

   T_DATA_EG_WRITE_ENABLE_IS_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      eg_evt |-> (eg_wen == 2'b11));

   // =====================================================================
   // 3 -- UNIQUENESS / NO DUPLICATION
   // =====================================================================
   T_UNIQ_AR_NEVER_INVENTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (((ar_fire_c[0] && (atoms_owed[0] == 0)) ||
        (ar_fire_c[1] && (atoms_owed[1] == 0)) ||
        (ar_fire_c[2] && (atoms_owed[2] == 0)) ||
        (ar_fire_c[3] && (atoms_owed[3] == 0))) == 1'b0));

   T_UNIQ_RESPONSE_NEVER_INVENTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (((rsp_fire[0] && (rsp_atoms[0] == 0)) ||
        (rsp_fire[1] && (rsp_atoms[1] == 0)) ||
        (rsp_fire[2] && (rsp_atoms[2] == 0)) ||
        (rsp_fire[3] && (rsp_atoms[3] == 0))) == 1'b0));

   T_UNIQ_CQ_ENTRY_NOT_DOUBLE_ALLOCATED: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_push |-> cq_free_ext[cq_push_adr]);

   T_UNIQ_CQ_ENTRY_NOT_DOUBLE_FREED: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_pop |-> !cq_free_ext[cq_pop_adr]);

   // =====================================================================
   // 4 -- NO LOSS / CONSERVATION
   // =====================================================================
   T_CONSERV_EGRESS_HOLDINGS_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((beats_owed[0] >= held[0]) && (beats_owed[1] >= held[1]) &&
       (beats_owed[2] >= held[2]) && (beats_owed[3] >= held[3])));

   T_CONSERV_EG_INPUT_PIPE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (eg_in_pipe == ({2'd0, p1_pv} + {2'd0, p1_sv})));

   T_CONSERV_CQ_FREE_PLUS_ALLOCATED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((cq_free_pop + cq_count) == 9'd255));

   T_CONSERV_RO_FIFO_HALVES_TRACK: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((ro0_cnt[0] == ro1_cnt[0]) && (ro0_cnt[1] == ro1_cnt[1]) &&
       (ro0_cnt[2] == ro1_cnt[2]) && (ro0_cnt[3] == ro1_cnt[3])));

   // =====================================================================
   // 5 -- MUTUAL EXCLUSION / ONE-HOT
   // =====================================================================
   T_MUTEX_IG_ARB_GRANT_ONEHOT: assert property (@(posedge clk)
      disable iff (!reset_n)
      $onehot0(ig_gnt));

   T_MUTEX_EG_ARB_GRANT_ONEHOT: assert property (@(posedge clk)
      disable iff (!reset_n)
      $onehot0(eg_gnt));

   T_MUTEX_LATFIFO_WRITE_ONEHOT: assert property (@(posedge clk)
      disable iff (!reset_n)
      $onehot0(lat_wr_pvld));

   // =====================================================================
   // 6 -- OCCUPANCY AND BOUNDS
   // =====================================================================
   T_BOUND_OS_CNT_LE_WINDOW: assert property (@(posedge clk)
      disable iff (!reset_n)
      ({1'b0, os_cnt} <= N_OS_WINDOW));

   T_BOUND_PUBLIC_OUTSTANDING_LE_WINDOW: assert property (@(posedge clk)
      disable iff (!reset_n)
      (pub_out <= N_OS_WINDOW));

   T_BOUND_CLIENT_HELD_BEATS: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((beats_owed[0] <= N_CLIENT_HOLD) && (beats_owed[1] <= N_CLIENT_HOLD) &&
       (beats_owed[2] <= N_CLIENT_HOLD) && (beats_owed[3] <= N_CLIENT_HOLD)));

   T_BOUND_COMMAND_QUEUE_NEVER_WRAPS: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((q_ovf[0] == 1'b0) && (q_ovf[1] == 1'b0) &&
       (q_ovf[2] == 1'b0) && (q_ovf[3] == 1'b0)));

   T_BOUND_LATFIFO_LE_DEPTH: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((lat_cnt[0] <= 3'd4) && (lat_cnt[1] <= 3'd4) &&
       (lat_cnt[2] <= 3'd4) && (lat_cnt[3] <= 3'd4)));

   T_BOUND_BPT_LATENCY_CREDITS: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((bpt_lat[0] <= 8'd245) && (bpt_lat[1] <= 8'd80) &&
       (bpt_lat[2] <= 8'd61)  && (bpt_lat[3] <= 8'd61)));

   // =====================================================================
   // 7 -- ALLOCATOR DISCIPLINE
   // =====================================================================
   T_ALLOC_CQ_INDEX_IN_RANGE: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_push |-> (cq_push_adr <= 8'd254));

   T_ALLOC_CQ_NO_POP_WHEN_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_pop |-> (cq_count != 9'd0));

   T_ALLOC_BPT_SINGLE_TRANSACTION_COMMANDS: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((bpt_cnt_req[0] == 13'd0) && (bpt_cnt_req[1] == 13'd0) &&
       (bpt_cnt_req[2] == 13'd0) && (bpt_cnt_req[3] == 13'd0)));

   // =====================================================================
   // 8 -- REQUEST / RESPONSE CORRESPONDENCE
   // =====================================================================
   T_REQRSP_RESPONSE_HAS_A_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      (((rsp_valid[0] && (rsp_atoms[0] == 0)) ||
        (rsp_valid[1] && (rsp_atoms[1] == 0)) ||
        (rsp_valid[2] && (rsp_atoms[2] == 0)) ||
        (rsp_valid[3] && (rsp_atoms[3] == 0))) == 1'b0));

   T_REQRSP_AR_HAS_A_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ar_valid && ar_active) |-> (atoms_owed[ar_c] != 0));

   T_REQRSP_CQ_WRITE_NAMES_A_REQUESTING_CLIENT: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_wr_pvld |-> ((cq_wr_tid < 4'd4) && (atoms_owed[cq_wr_tid[1:0]] != 0)));

   // =====================================================================
   // 9 -- PROTOCOL CONFORMANCE
   // =====================================================================
   T_PROTO_AR_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ar_valid && !ar_ready) |=> ar_valid);

   T_PROTO_AR_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ar_valid && !ar_ready) |=>
         ($stable(ar_id) && $stable(ar_len) && $stable(ar_addr)));

   T_PROTO_AR_ADDR_64B_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ar_valid |-> (ar_addr[5:0] == 6'd0));

   T_PROTO_RSP_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((rsp_stall_q & ~rsp_valid) == 4'd0));

   T_PROTO_RSP_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((!rsp_stall_q[0] || $stable(rsp_pd[   0 +: 514])) &&
       (!rsp_stall_q[1] || $stable(rsp_pd[ 514 +: 514])) &&
       (!rsp_stall_q[2] || $stable(rsp_pd[1028 +: 514])) &&
       (!rsp_stall_q[3] || $stable(rsp_pd[1542 +: 514]))));

   // =====================================================================
   // 10 -- ARBITRATION FAIRNESS (bounded-safety form)
   // =====================================================================
   T_FAIR_IG_ARB_BYPASS_BOUNDED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((ctr_ig_bypass[0] <= N_ARB_BYPASS) && (ctr_ig_bypass[1] <= N_ARB_BYPASS) &&
       (ctr_ig_bypass[2] <= N_ARB_BYPASS) && (ctr_ig_bypass[3] <= N_ARB_BYPASS)));

   T_FAIR_EG_ARB_BYPASS_BOUNDED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((ctr_eg_bypass[0] <= N_ARB_BYPASS) && (ctr_eg_bypass[1] <= N_ARB_BYPASS) &&
       (ctr_eg_bypass[2] <= N_ARB_BYPASS) && (ctr_eg_bypass[3] <= N_ARB_BYPASS)));

   T_FAIR_ZERO_WEIGHT_SOURCE_NEVER_GRANTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((ig_gnt & 10'h3f0) == 10'd0));

   // =====================================================================
   // 11 -- BOUNDED RESPONSE (bounded-safety form)
   // =====================================================================
   T_BOUNDRSP_EGRESS_DRAINS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_drain <= N_DRAIN));

   T_BOUNDRSP_INGRESS_ISSUES_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_issue <= N_ISSUE));

   // =====================================================================
   // 12 -- DEADLOCK FREEDOM (bounded-safety form)
   // =====================================================================
   T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_stall <= N_STALL));

   T_DEADLOCK_IG_ARB_GRANTS_WHEN_ASKED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((|(ig_req & 10'h00f)) && ig_arb_ready) |-> (ig_gnt != 10'd0));

   T_DEADLOCK_EG_ARB_GRANTS_WHEN_ASKED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (|eg_req) |-> (eg_gnt != 10'd0));

   // =====================================================================
   // 13 -- RESET / INITIALISATION
   // =====================================================================
   T_RESET_CQ_FREE_LIST_COMPLETE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((cq_free == {255{1'b1}}) && (cq_count == 9'd0) && !cq_busy));

   T_RESET_EGRESS_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (!p1_pv && !p1_sv &&
         (lat_cnt[0] == 0) && (lat_cnt[1] == 0) &&
         (lat_cnt[2] == 0) && (lat_cnt[3] == 0) &&
         (ro0_cnt[0] == 0) && (ro0_cnt[1] == 0) &&
         (ro0_cnt[2] == 0) && (ro0_cnt[3] == 0) &&
         (eg_wrr == 10'd0)));

   T_RESET_NO_OUTPUT_OFFERED: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (!ar_valid && (rsp_valid == 4'd0) && (dead_rsp_valid == 6'd0)));

   T_RESET_INGRESS_IDLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((os_cnt == 9'd0) && !os_sub_d && (spt_beat == 2'd0) &&
                       (ig_wrr == 10'd0) &&
                       (bpt_lat[0] == 0) && (bpt_lat[1] == 0) &&
                       (bpt_lat[2] == 0) && (bpt_lat[3] == 0) &&
                       (bpt_cnt_req[0] == 0) && (bpt_cnt_req[1] == 0) &&
                       (bpt_cnt_req[2] == 0) && (bpt_cnt_req[3] == 0)));

   // =====================================================================
   // 14 -- LIFECYCLE / ACCESS CONTROL
   // =====================================================================
   T_LIFECYCLE_TIED_OFF_CLIENT_NEVER_ANSWERED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (dead_rsp_valid == 6'd0));

   T_LIFECYCLE_TIED_OFF_LATFIFO_STAYS_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((dead_lat_cnt[0] == 0) && (dead_lat_cnt[1] == 0) &&
       (dead_lat_cnt[2] == 0) && (dead_lat_cnt[3] == 0) &&
       (dead_lat_cnt[4] == 0) && (dead_lat_cnt[5] == 0)));

   T_LIFECYCLE_EG_NEVER_SERVES_TIED_OFF_CLIENT: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((eg_gnt & 10'h3f0) == 10'd0));

   // =====================================================================
   // COVERS -- at least one per category used, showing the scenario each
   // target constrains is reachable.
   // =====================================================================
   C_ORDER_AR_RUN_LAST_BEAT: cover property (@(posedge clk)
      disable iff (!reset_n) (ar_fire && (g_sub == 2'd3)));
   C_ORDER_TWO_COMMANDS_QUEUED: cover property (@(posedge clk)
      disable iff (!reset_n) (q_occ[0] >= 4'd2));
   C_ORDER_TWO_CLIENTS_QUEUED: cover property (@(posedge clk)
      disable iff (!reset_n) ((q_occ[0] != 0) && (q_occ[1] != 0)));

   C_DATA_AR_ADDRESS_CHECKED: cover property (@(posedge clk)
      disable iff (!reset_n) ar_checkable);
   C_DATA_XOR_CHECKED_AFTER_TRAFFIC: cover property (@(posedge clk)
      disable iff (!reset_n) (clients_drained && (rsp_xor[0] != 512'd0)));
   C_DATA_EG_GRANT_WITH_CONTEXT: cover property (@(posedge clk)
      disable iff (!reset_n) eg_evt);

   C_UNIQ_CQ_ALLOCATED: cover property (@(posedge clk)
      disable iff (!reset_n) cq_push);
   C_UNIQ_CQ_FREED: cover property (@(posedge clk)
      disable iff (!reset_n) cq_pop);

   C_CONSERV_EG_PIPE_BOTH_STAGES: cover property (@(posedge clk)
      disable iff (!reset_n) (p1_pv && p1_sv));
   C_CONSERV_TWO_CLIENTS_HOLDING: cover property (@(posedge clk)
      disable iff (!reset_n) ((held[0] != 0) && (held[1] != 0)));

   C_MUTEX_IG_ARB_GRANTS: cover property (@(posedge clk)
      disable iff (!reset_n) (ig_gnt != 10'd0));
   C_MUTEX_EG_ARB_GRANTS: cover property (@(posedge clk)
      disable iff (!reset_n) (eg_gnt != 10'd0));
   C_MUTEX_LATFIFO_WRITTEN: cover property (@(posedge clk)
      disable iff (!reset_n) (lat_wr_pvld != 10'd0));

   C_BOUND_OS_CNT_HALF_WINDOW: cover property (@(posedge clk)
      disable iff (!reset_n) (os_cnt >= 9'd8));
   C_BOUND_LATFIFO_TWO_DEEP: cover property (@(posedge clk)
      disable iff (!reset_n) (lat_cnt[0] >= 3'd2));
   C_BOUND_FOUR_CLIENTS_HOLDING: cover property (@(posedge clk)
      disable iff (!reset_n) ((beats_owed[0] != 0) && (beats_owed[1] != 0) &&
                              (beats_owed[2] != 0) && (beats_owed[3] != 0)));

   C_ALLOC_CQ_FOUR_ALLOCATED: cover property (@(posedge clk)
      disable iff (!reset_n) (cq_count >= 9'd4));
   C_ALLOC_BPT_CREDITS_SPENT: cover property (@(posedge clk)
      disable iff (!reset_n) (bpt_lat[0] >= 8'd8));

   C_REQRSP_RESPONSE_DELIVERED: cover property (@(posedge clk)
      disable iff (!reset_n) (|rsp_fire));
   C_REQRSP_ALL_FOUR_COMMANDED: cover property (@(posedge clk)
      disable iff (!reset_n) ((atoms_owed[0] != 0) && (atoms_owed[1] != 0) &&
                              (atoms_owed[2] != 0) && (atoms_owed[3] != 0)));

   C_PROTO_AR_BACKPRESSURE: cover property (@(posedge clk)
      disable iff (!reset_n) (ar_valid && !ar_ready));
   C_PROTO_RSP_BACKPRESSURE: cover property (@(posedge clk)
      disable iff (!reset_n) (rsp_stall_q != 4'd0));

   C_FAIR_IG_ARB_BYPASSED_TWICE: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_ig_bypass[0] >= 6'd2));
   C_FAIR_EG_ARB_BYPASSED_TWICE: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_eg_bypass[0] >= 6'd2));

   C_BOUNDRSP_DRAIN_WAIT_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_drain >= 10'd4));
   C_BOUNDRSP_ISSUE_WAIT_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_issue >= 10'd4));

   C_DEADLOCK_STALL_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_stall >= 10'd4));

   C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
      disable iff (!reset_n) !post_reset);

   C_LIFECYCLE_ACTIVE_CLIENT_SERVED: cover property (@(posedge clk)
      disable iff (!reset_n) ((eg_gnt & 10'h00f) != 10'd0));

endmodule

bind nvdla_mcif_order_ft nvdla_mcif_targets u_targets (
   .clk(nvdla_core_clk), .reset_n(nvdla_core_rstn));
