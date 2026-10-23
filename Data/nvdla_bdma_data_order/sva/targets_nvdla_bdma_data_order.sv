// ===========================================================================
// Candidate target assertions for the real NVDLA BDMA load / context-queue /
// store path.
//
// Bound into the formal top, so every reference below is a hierarchical name
// from `nvdla_bdma_data_order_ft`.  NOTHING HERE IS AN ASSUMPTION -- the five
// the task already carries live in sva/nvdla_bdma_data_order_checker.sv
// (A_CMD_HOLD, A_RSP_HOLD, A_RSP_HAS_REQUEST, A_READ_WINDOW,
// A_REFERENCE_WINDOW) and this file adds none.
//
// WHAT THE BLOCK DOES under the frozen configuration -- reg2dp_line_size=15,
// reg2dp_line_repeat_number=1, reg2dp_surf_repeat_number=0, src 0x20000, dst
// 0x40000, both line strides 32 (<<5 = 1024 B), both surface strides 64
// (<<5 = 2048 B), src and dst RAM type both MCIF, CVIF tied off:
//
//   one csb2ld command
//     -> LOAD: two read transactions (line_count 0 then 1), each size 15,
//        i.e. sixteen 32 B atoms == eight 512 b beats, at 0x20000 and 0x20400
//     -> the same command pushed once into the 20-entry context queue
//     -> STORE: per popped context, two lines; each line is one write COMMAND
//        packet (bit 514 == 0) followed by eight write DATA packets
//        (bit 514 == 1), so 2 commands and 16 data beats per csb command
//     -> the 245-entry latency FIFO is the only thing between an accepted MCIF
//        read response and an accepted MCIF write-data packet.
//
// THE ORACLES ARE THIS FILE'S OWN.
//
//   * five DIFFERENCE COUNTERS driven only by the five public handshakes --
//     read requests owed, read beats owed, beats held in the store, write
//     commands owed, write data beats owed.  They repeat none of the package
//     checker's positional queue; two of them recompute what the checker's
//     own ledger holds, and asserting the two agree is the point.
//   * two 512-bit XOR ACCUMULATORS, one over accepted read-response payloads
//     and one over accepted write-data payloads.  This catches a dropped,
//     duplicated or corrupted beat BY CONTENT, which is a different oracle
//     from the checker's positional `ref_mem`.
//   * SATURATING COUNTERS, which is how a bounded-response or deadlock
//     obligation is written as a safety property.  There is no `s_eventually`
//     and no unbounded liveness anywhere in this file.
//
// TWO THINGS A READER OF A RESULT FROM THIS FILE NEEDS.
//
// 1. RESET.  This module's registers are reset-initialised and every claim
//    that reads one is stated for a run that starts in the design's reset
//    state.  Under `ENTER_FRA_KEEP` only registers matched by the task's
//    `design_keep` are given their reset value, and that pattern names
//    `u_checker.*` and nothing else.  So a screen of the oracle-backed claims
//    below must be run with
//
//        --keep-extra 'u_targets\.'
//
//    or those claims are falsified at cycle 0 for a reason that is not the
//    design's.  The claims that read only design signals need no such flag.
//    `taskdef.json` is deliberately NOT edited: adding to `design_keep` would
//    change the abstraction the existing target T_DATA_ORDER is measured
//    under.
//
// 2. WHICH CLAIMS ARE ANCHORED IN THE PACKAGE'S KEPT STATE.  `commands_seen`,
//    `ref_count` and `outstanding_beats` ARE in the task's keep pattern, so
//    `cmd_seen` below survives the cut and the claims gated on it are stated
//    against a real post-command state rather than an arbitrary one.
// ===========================================================================

module nvdla_bdma_targets (input wire clk, input wire reset_n);

   // the bounds asserted below, gathered so the numbers are readable
   localparam [7:0]  N_REQ_OWED   = 8'd8;     // read requests owed at once
   localparam [7:0]  N_BEAT_OWED  = 8'd64;    // A_READ_WINDOW 56 + one 8-beat
   localparam [7:0]  N_HELD       = 8'd64;    // A_REFERENCE_WINDOW / REF_DEPTH
   localparam [7:0]  N_WCMD_OWED  = 8'd64;    // 20-deep context queue + store
   localparam [9:0]  N_WDAT_OWED  = 10'd512;  // 16 beats per queued command
   localparam [9:0]  N_ISSUE      = 10'd64;
   localparam [9:0]  N_DRAIN      = 10'd128;
   localparam [9:0]  N_STALL      = 10'd256;

   // ------------------------------------------------------------- boundary
   wire         cmd_valid  = nvdla_bdma_data_order_ft.csb2ld_vld;
   wire         cmd_ready  = nvdla_bdma_data_order_ft.csb2ld_rdy;

   wire         rreq_valid = nvdla_bdma_data_order_ft.bdma2mcif_rd_req_valid;
   wire         rreq_ready = nvdla_bdma_data_order_ft.bdma2mcif_rd_req_ready;
   wire [78:0]  rreq_pd    = nvdla_bdma_data_order_ft.bdma2mcif_rd_req_pd;

   wire         rrsp_valid = nvdla_bdma_data_order_ft.mcif2bdma_rd_rsp_valid;
   wire         rrsp_ready = nvdla_bdma_data_order_ft.mcif2bdma_rd_rsp_ready;
   wire [513:0] rrsp_pd    = nvdla_bdma_data_order_ft.mcif2bdma_rd_rsp_pd;

   wire         wreq_valid = nvdla_bdma_data_order_ft.bdma2mcif_wr_req_valid;
   wire         wreq_ready = nvdla_bdma_data_order_ft.bdma2mcif_wr_req_ready;
   wire [514:0] wreq_pd    = nvdla_bdma_data_order_ft.bdma2mcif_wr_req_pd;

   // the tied-off CVIF side, which must stay silent
   wire         cv_rreq_valid = nvdla_bdma_data_order_ft.bdma2cvif_rd_req_valid;
   wire         cv_wreq_valid = nvdla_bdma_data_order_ft.bdma2cvif_wr_req_valid;
   wire         grp0_done     = nvdla_bdma_data_order_ft.st2csb_grp0_done;
   wire         grp1_done     = nvdla_bdma_data_order_ft.st2csb_grp1_done;

   wire cmd_fire  = cmd_valid  && cmd_ready;
   wire rreq_fire = rreq_valid && rreq_ready;
   wire rrsp_fire = rrsp_valid && rrsp_ready;
   wire wreq_fire = wreq_valid && wreq_ready;
   wire wcmd_fire = wreq_fire && !wreq_pd[514];   // write COMMAND packet
   wire wdat_fire = wreq_fire &&  wreq_pd[514];   // write DATA packet

   // ------------------------------------------------------- design windows
   // load
   wire        ld_tran_valid = nvdla_bdma_data_order_ft.u_load.tran_valid;
   wire        ld_cmd_ready  = nvdla_bdma_data_order_ft.u_load.cmd_ready;
   wire [23:0] ld_line_count = nvdla_bdma_data_order_ft.u_load.line_count;
   wire [23:0] ld_surf_count = nvdla_bdma_data_order_ft.u_load.surf_count;
   wire [63:0] ld_line_addr  = nvdla_bdma_data_order_ft.u_load.line_addr;
   wire [63:0] ld_surf_addr  = nvdla_bdma_data_order_ft.u_load.surf_addr;
   wire [12:0] ld_line_size  = nvdla_bdma_data_order_ft.u_load.reg_line_size;
   wire [31:0] ld_line_strd  = nvdla_bdma_data_order_ft.u_load.reg_line_stride;
   wire [31:0] ld_surf_strd  = nvdla_bdma_data_order_ft.u_load.reg_surf_stride;
   wire [23:0] ld_line_rpt   = nvdla_bdma_data_order_ft.u_load.reg_line_repeat_number;
   wire [23:0] ld_surf_rpt   = nvdla_bdma_data_order_ft.u_load.reg_surf_repeat_number;
   wire        ld_src_type   = nvdla_bdma_data_order_ft.u_load.reg_cmd_src_ram_type;
   wire        ld_cv_req_vld = nvdla_bdma_data_order_ft.u_load.cv_dma_rd_req_vld;
   wire        ld_mc_req_vld = nvdla_bdma_data_order_ft.u_load.mc_dma_rd_req_vld;

   // 20-entry context queue
   wire [4:0] cq_wr_count = nvdla_bdma_data_order_ft.u_cq.ld2st_wr_count;
   wire [4:0] cq_rd_count = nvdla_bdma_data_order_ft.u_cq.ld2st_rd_count_p;
   wire [4:0] cq_wr_adr   = nvdla_bdma_data_order_ft.u_cq.ld2st_wr_adr;
   wire [4:0] cq_rd_adr   = nvdla_bdma_data_order_ft.u_cq.ld2st_rd_adr;
   wire       cq_push     = nvdla_bdma_data_order_ft.u_cq.wr_pushing;
   wire       cq_pop      = nvdla_bdma_data_order_ft.u_cq.rd_popping;
   wire       cq_rd_pvld  = nvdla_bdma_data_order_ft.u_cq.ld2st_rd_pvld_int;

   // store
   wire        st_cmd_en     = nvdla_bdma_data_order_ft.u_store.cmd_en;
   wire        st_dat_en     = nvdla_bdma_data_order_ft.u_store.dat_en;
   wire        st_tran_cmd_v = nvdla_bdma_data_order_ft.u_store.tran_cmd_valid;
   wire [11:0] st_beat_count = nvdla_bdma_data_order_ft.u_store.beat_count;
   wire [12:0] st_line_count = nvdla_bdma_data_order_ft.u_store.line_count;
   wire [12:0] st_surf_count = nvdla_bdma_data_order_ft.u_store.surf_count;
   wire [12:0] st_line_size  = nvdla_bdma_data_order_ft.u_store.reg_line_size;
   wire        st_mc_rsp_vld = nvdla_bdma_data_order_ft.u_store.mc_dma_rd_rsp_vld;
   wire        st_cv_rsp_vld = nvdla_bdma_data_order_ft.u_store.cv_dma_rd_rsp_vld;
   wire        st_cv_wr_vld  = nvdla_bdma_data_order_ft.u_store.cv_dma_wr_req_vld;
   wire        st_mc_wr_vld  = nvdla_bdma_data_order_ft.u_store.mc_dma_wr_req_vld;
   wire        st_intr_wr    = nvdla_bdma_data_order_ft.u_store.fifo_intr_wr_pvld;

   // 245-entry store latency FIFO
   wire [7:0] lat_wr_count = nvdla_bdma_data_order_ft.u_store.lat_fifo.lat_fifo_wr_count;
   wire [7:0] lat_rd_count = nvdla_bdma_data_order_ft.u_store.lat_fifo.lat_fifo_rd_count_p;
   wire [7:0] lat_wr_adr   = nvdla_bdma_data_order_ft.u_store.lat_fifo.lat_fifo_wr_adr;
   wire [7:0] lat_rd_adr   = nvdla_bdma_data_order_ft.u_store.lat_fifo.lat_fifo_rd_adr;
   wire       lat_push     = nvdla_bdma_data_order_ft.u_store.lat_fifo.wr_pushing;
   wire       lat_pop      = nvdla_bdma_data_order_ft.u_store.lat_fifo.rd_popping;
   wire       lat_rd_push  = nvdla_bdma_data_order_ft.u_store.lat_fifo.rd_pushing;
   wire       lat_wr_pop   = nvdla_bdma_data_order_ft.u_store.lat_fifo.wr_popping;

   // the package checker's own ledger -- kept across the FRA cut, so this is
   // the one piece of anchored state a claim here can lean on
   wire [6:0] pkg_ref_count = nvdla_bdma_data_order_ft.u_checker.ref_count;
   wire [6:0] pkg_os_beats  = nvdla_bdma_data_order_ft.u_checker.outstanding_beats;
   wire [2:0] pkg_cmds_seen = nvdla_bdma_data_order_ft.u_checker.commands_seen;
   wire       cmd_seen      = (pkg_cmds_seen != 3'd0);

   // =====================================================================
   // ORACLE 1 -- difference counters driven only by the public handshakes.
   // Nothing here reads a design register.
   // =====================================================================
   reg [7:0] req_owed;    // +2 per csb command, -1 per read request accepted
   reg [7:0] beat_owed;   // +8 per read request, -1 per read response
   reg [7:0] held;        // +1 per read response, -1 per write data beat
   reg [7:0] wcmd_owed;   // +2 per csb command, -1 per write command
   reg [9:0] wdat_owed;   // +16 per csb command, -1 per write data beat

   // =====================================================================
   // ORACLE 2 -- 512-bit XOR accumulators on the two sides of the copy.
   // Catches a dropped, duplicated or corrupted beat by CONTENT.
   // =====================================================================
   reg [511:0] rsp_xor;
   reg [511:0] wr_xor;

   // =====================================================================
   // ORACLE 3 -- saturating counters.  Every bounded-response and deadlock
   // claim below is the safety statement that one never passes its bound.
   // =====================================================================
   reg [9:0] ctr_issue;
   reg [9:0] ctr_drain;
   reg [9:0] ctr_stall;

   reg       post_reset;
   reg [3:0] settle;      // saturating cycles since reset
   reg       rreq_stall_q;
   reg       wreq_stall_q;

   wire warm = (settle == 4'd15);

   wire can_issue = rreq_ready && (req_owed != 8'd0) && (beat_owed <= 8'd56);
   wire can_drain = wreq_ready && (held != 8'd0);
   wire any_fire  = rreq_fire || rrsp_fire || wreq_fire;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         req_owed   <= 8'd0;
         beat_owed  <= 8'd0;
         held       <= 8'd0;
         wcmd_owed  <= 8'd0;
         wdat_owed  <= 10'd0;
         rsp_xor    <= 512'd0;
         wr_xor     <= 512'd0;
         ctr_issue  <= 10'd0;
         ctr_drain  <= 10'd0;
         ctr_stall  <= 10'd0;
         post_reset <= 1'b0;
         settle     <= 4'd0;
         rreq_stall_q <= 1'b0;
         wreq_stall_q <= 1'b0;
      end else begin
         post_reset <= 1'b1;
         if (settle != 4'd15) settle <= settle + 4'd1;
         rreq_stall_q <= rreq_valid && !rreq_ready;
         wreq_stall_q <= wreq_valid && !wreq_ready;

         req_owed  <= req_owed  + (cmd_fire  ? 8'd2  : 8'd0)
                                - (rreq_fire ? 8'd1  : 8'd0);
         beat_owed <= beat_owed + (rreq_fire ? 8'd8  : 8'd0)
                                - (rrsp_fire ? 8'd1  : 8'd0);
         held      <= held      + (rrsp_fire ? 8'd1  : 8'd0)
                                - (wdat_fire ? 8'd1  : 8'd0);
         wcmd_owed <= wcmd_owed + (cmd_fire  ? 8'd2  : 8'd0)
                                - (wcmd_fire ? 8'd1  : 8'd0);
         wdat_owed <= wdat_owed + (cmd_fire  ? 10'd16 : 10'd0)
                                - (wdat_fire ? 10'd1  : 10'd0);

         if (rrsp_fire) rsp_xor <= rsp_xor ^ rrsp_pd[511:0];
         if (wdat_fire) wr_xor  <= wr_xor  ^ wreq_pd[511:0];

         ctr_issue <= !(can_issue && !rreq_fire) ? 10'd0
                    : (ctr_issue == 10'd1023) ? ctr_issue : ctr_issue + 10'd1;
         ctr_drain <= !(can_drain && !wreq_fire) ? 10'd0
                    : (ctr_drain == 10'd1023) ? ctr_drain : ctr_drain + 10'd1;
         ctr_stall <= !((can_issue || can_drain) && !any_fire) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   // =====================================================================
   // 1 -- END-TO-END ORDERING
   // =====================================================================

   T_ORDER_WCMD_NEVER_RUNS_AHEAD_OF_ITS_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      wcmd_fire |-> (wcmd_owed != 8'd0));




   // =====================================================================
   // 2 -- DATA INTEGRITY
   // =====================================================================
   T_DATA_XOR_CONSERVED_WHEN_DRAINED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (held == 8'd0) |-> (rsp_xor == wr_xor));

   T_DATA_WRITE_MASK_IS_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      wdat_fire |-> (wreq_pd[513:512] == 2'b11));

   T_DATA_WRITE_COMMAND_SIZE_IS_ONE_LINE: assert property (@(posedge clk)
      disable iff (!reset_n)
      wcmd_fire |-> (wreq_pd[76:64] == 13'd15));

   T_DATA_READ_REQUEST_SIZE_IS_ONE_LINE: assert property (@(posedge clk)
      disable iff (!reset_n)
      rreq_fire |-> (rreq_pd[78:64] == 15'd15));

   T_DATA_BOTH_ADDRESSES_ARE_LINE_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((!rreq_fire || (rreq_pd[9:0] == 10'd0)) &&
       (!wcmd_fire || (wreq_pd[9:0] == 10'd0))));

   T_DATA_LOAD_HOLDS_THE_FROZEN_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      cmd_seen |-> ((ld_line_size == 13'd15) && (ld_src_type == 1'b1) &&
                    (ld_line_strd == 32'd1024) && (ld_surf_strd == 32'd2048) &&
                    (ld_line_rpt == 24'd1) && (ld_surf_rpt == 24'd0)));

   T_DATA_LOAD_ADDRESS_STAYS_LINE_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      cmd_seen |-> ((ld_line_addr[9:0] == 10'd0) && (ld_surf_addr[10:0] == 11'd0)));

   // =====================================================================
   // 3 -- UNIQUENESS / NO DUPLICATION
   // =====================================================================
   T_UNIQ_CONTEXT_QUEUE_NEVER_OVERWRITES_A_LIVE_ENTRY: assert property (@(posedge clk)
      disable iff (!reset_n)
      (cq_push && (cq_rd_count != 5'd0) && !cq_pop) |-> (cq_wr_adr != cq_rd_adr));

   T_UNIQ_LATENCY_FIFO_NEVER_OVERWRITES_A_LIVE_ENTRY: assert property (@(posedge clk)
      disable iff (!reset_n)
      (lat_push && (lat_wr_count != 8'd0)) |-> (lat_wr_adr != lat_rd_adr));

   T_UNIQ_NO_WRITE_BEAT_WITHOUT_A_HELD_RESPONSE: assert property (@(posedge clk)
      disable iff (!reset_n)
      wdat_fire |-> (held != 8'd0));


   // =====================================================================
   // 4 -- NO LOSS / CONSERVATION
   // =====================================================================
   T_CONSERV_MY_LEDGER_MATCHES_THE_PACKAGE_REFERENCE_COUNT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (held == {1'b0, pkg_ref_count}));

   T_CONSERV_MY_LEDGER_MATCHES_THE_PACKAGE_OUTSTANDING_COUNT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (beat_owed == {1'b0, pkg_os_beats}));

   T_CONSERV_CONTEXT_QUEUE_SIDES_AGREE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (cq_wr_count == cq_rd_count));

   T_CONSERV_LATENCY_FIFO_SIDE_SKEW_IS_THE_BOUNDARY_PAIR: assert property (@(posedge clk)
      disable iff (!reset_n)
      (lat_wr_count == (lat_rd_count + {7'd0, lat_rd_push} + {7'd0, lat_wr_pop})));

   T_CONSERV_HELD_BEATS_FIT_THE_LATENCY_FIFO_AND_ITS_PIPES: assert property (@(posedge clk)
      disable iff (!reset_n)
      (held >= lat_rd_count));

   // =====================================================================
   // 5 -- MUTUAL EXCLUSION / ONE-HOT
   // =====================================================================
   T_MUTEX_ONE_READ_REQUEST_DESTINATION: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(ld_cv_req_vld && ld_mc_req_vld));

   T_MUTEX_ONE_WRITE_REQUEST_DESTINATION: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(st_cv_wr_vld && st_mc_wr_vld));

   T_MUTEX_ONE_RESPONSE_SOURCE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(st_mc_rsp_vld && st_cv_rsp_vld));

   T_MUTEX_STORE_IS_IN_COMMAND_OR_DATA_PHASE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(st_cmd_en && st_dat_en));


   // =====================================================================
   // 6 -- OCCUPANCY AND BOUNDS
   // =====================================================================
   T_BOUND_CONTEXT_QUEUE_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((cq_wr_count <= 5'd20) && (cq_rd_count <= 5'd20)));


   T_BOUND_LATENCY_FIFO_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((lat_wr_count <= 8'd245) && (lat_rd_count <= 8'd245)));


   T_BOUND_READ_REQUESTS_OWED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (req_owed <= N_REQ_OWED));

   T_BOUND_READ_BEATS_OWED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (beat_owed <= N_BEAT_OWED));

   T_BOUND_BEATS_HELD_IN_THE_STORE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (held <= N_HELD));

   T_BOUND_WRITE_COMMANDS_OWED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wcmd_owed <= N_WCMD_OWED));

   T_BOUND_WRITE_DATA_BEATS_OWED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wdat_owed <= N_WDAT_OWED));

   T_BOUND_STORE_BEAT_INDEX: assert property (@(posedge clk)
      disable iff (!reset_n)
      (st_beat_count <= 12'd7));

   T_BOUND_LOAD_LINE_AND_SURFACE_INDEX: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((ld_line_count <= 24'd1) && (ld_surf_count == 24'd0)));

   // =====================================================================
   // 7 -- ALLOCATOR DISCIPLINE
   // =====================================================================
   T_ALLOC_CONTEXT_QUEUE_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_push |-> (cq_wr_count != 5'd20));

   T_ALLOC_CONTEXT_QUEUE_NO_POP_WHEN_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      cq_pop |-> ((cq_rd_count != 5'd0) || cq_push));

   T_ALLOC_LATENCY_FIFO_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      lat_push |-> (lat_wr_count != 8'd245));

   T_ALLOC_LATENCY_FIFO_NO_POP_WHEN_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      lat_pop |-> ((lat_rd_count != 8'd0) || lat_rd_push));

   // =====================================================================
   // 8 -- REQUEST / RESPONSE CORRESPONDENCE
   // =====================================================================


   T_REQRSP_STORE_ONLY_OFFERS_DATA_AFTER_ITS_COMMAND: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wreq_valid && wreq_pd[514]) |-> (wdat_owed != 10'd0));

   T_REQRSP_READ_REQUEST_IMPLIES_AN_OWED_TRANSACTION: assert property (@(posedge clk)
      disable iff (!reset_n)
      rreq_valid |-> (req_owed != 8'd0));

   // =====================================================================
   // 9 -- PROTOCOL CONFORMANCE
   // =====================================================================
   T_PROTO_READ_REQUEST_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (rreq_valid && !rreq_ready) |=> rreq_valid);

   T_PROTO_READ_REQUEST_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      rreq_stall_q |-> $stable(rreq_pd));

   T_PROTO_WRITE_REQUEST_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wreq_valid && !wreq_ready) |=> wreq_valid);

   T_PROTO_WRITE_REQUEST_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      wreq_stall_q |-> $stable(wreq_pd));



   // =====================================================================
   // 10 -- ARBITRATION FAIRNESS: NOT ADMITTED.
   // This block has no arbiter.  The load drives one transaction generator,
   // the context queue is a single FIFO and the store drives one write
   // stream; the only fan-out is the MCIF/CVIF destination decode, which is
   // a decode and not a grant.  It is covered under mutual exclusion above.
   // =====================================================================

   // =====================================================================
   // 11 -- BOUNDED RESPONSE (bounded-safety form)
   // =====================================================================
   T_BOUNDRSP_READ_REQUEST_ISSUES_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_issue <= N_ISSUE));

   T_BOUNDRSP_STORE_DRAINS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_drain <= N_DRAIN));

   // =====================================================================
   // 12 -- DEADLOCK FREEDOM (bounded-safety form)
   // =====================================================================
   T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_stall <= N_STALL));

   T_DEADLOCK_CONTEXT_QUEUE_OFFERS_WHAT_IT_HOLDS: assert property (@(posedge clk)
      disable iff (!reset_n)
      (cq_rd_count != 5'd0) |-> (cq_rd_pvld || cq_pop));

   // =====================================================================
   // 13 -- RESET / INITIALISATION
   // =====================================================================
   T_RESET_QUEUES_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((cq_wr_count == 5'd0) && (cq_rd_count == 5'd0) &&
                       (lat_wr_count == 8'd0) && (lat_rd_count == 8'd0) &&
                       (cq_wr_adr == 5'd0) && (cq_rd_adr == 5'd0) &&
                       (lat_wr_adr == 8'd0) && (lat_rd_adr == 8'd0)));

   T_RESET_NO_OUTPUT_OFFERED: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (!rreq_valid && !wreq_valid &&
                       !cv_rreq_valid && !cv_wreq_valid));

   T_RESET_STORE_STARTS_IN_COMMAND_PHASE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (st_cmd_en && !st_dat_en && !st_tran_cmd_v &&
                       (st_beat_count == 12'd0) && (st_line_count == 13'd0) &&
                       (st_surf_count == 13'd0)));

   // =====================================================================
   // 14 -- LIFECYCLE / ACCESS CONTROL
   // =====================================================================
   T_LIFECYCLE_CVIF_READ_NEVER_REQUESTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      cmd_seen |-> !ld_cv_req_vld);

   T_LIFECYCLE_CVIF_NEVER_ADDRESSED_AT_THE_BOUNDARY: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm |-> (!cv_rreq_valid && !cv_wreq_valid));

   T_LIFECYCLE_INTERRUPT_NEVER_ARMED: assert property (@(posedge clk)
      disable iff (!reset_n)
      wcmd_fire |-> (wreq_pd[77] == 1'b0));

   T_LIFECYCLE_NO_GROUP_DONE_WITHOUT_AN_ARMED_INTERRUPT: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm |-> (!grp0_done && !grp1_done && !st_intr_wr));

   // =====================================================================
   // 15 -- COHERENCE: NOT ADMITTED.  One agent, one memory, no shared
   // permission state anywhere in this block.
   // =====================================================================

   // =====================================================================
   // COVERS -- at least one per category used.
   // =====================================================================
   C_ORDER_WRITE_COMMAND_ACCEPTED: cover property (@(posedge clk)
      disable iff (!reset_n) wcmd_fire);
   C_ORDER_EIGHT_DATA_BEATS_SEEN: cover property (@(posedge clk)
      disable iff (!reset_n) (wdat_fire && (st_beat_count == 12'd7)));
   C_ORDER_TWO_COMMANDS_IN_FLIGHT: cover property (@(posedge clk)
      disable iff (!reset_n) (wcmd_owed >= 8'd3));

   C_DATA_WRITE_DATA_ACCEPTED: cover property (@(posedge clk)
      disable iff (!reset_n) wdat_fire);
   C_DATA_XOR_CHECKED_AFTER_TRAFFIC: cover property (@(posedge clk)
      disable iff (!reset_n) ((held == 8'd0) && (wr_xor != 512'd0)));
   C_DATA_LOAD_ON_SECOND_LINE: cover property (@(posedge clk)
      disable iff (!reset_n) (cmd_seen && (ld_line_count == 24'd1)));

   C_UNIQ_LATENCY_FIFO_HOLDS_EIGHT: cover property (@(posedge clk)
      disable iff (!reset_n) (lat_rd_count >= 8'd8));
   C_UNIQ_CONTEXT_QUEUE_HOLDS_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (cq_rd_count >= 5'd2));

   C_CONSERV_SIMULTANEOUS_RESPONSE_AND_WRITE: cover property (@(posedge clk)
      disable iff (!reset_n) (rrsp_fire && wdat_fire));
   C_CONSERV_SIXTEEN_BEATS_HELD: cover property (@(posedge clk)
      disable iff (!reset_n) (held >= 8'd16));

   C_MUTEX_STORE_IN_DATA_PHASE: cover property (@(posedge clk)
      disable iff (!reset_n) st_dat_en);
   C_MUTEX_STORE_IN_COMMAND_PHASE_WITH_CONTEXT: cover property (@(posedge clk)
      disable iff (!reset_n) (st_cmd_en && st_tran_cmd_v));

   C_BOUND_READ_WINDOW_HALF_OPEN: cover property (@(posedge clk)
      disable iff (!reset_n) (beat_owed >= 8'd32));
   C_BOUND_REFERENCE_QUEUE_HALF_FULL: cover property (@(posedge clk)
      disable iff (!reset_n) (held >= 8'd32));

   C_ALLOC_CONTEXT_QUEUE_PUSH: cover property (@(posedge clk)
      disable iff (!reset_n) cq_push);
   C_ALLOC_CONTEXT_QUEUE_POP: cover property (@(posedge clk)
      disable iff (!reset_n) cq_pop);
   C_ALLOC_LATENCY_FIFO_PUSH_AND_POP: cover property (@(posedge clk)
      disable iff (!reset_n) (lat_push && lat_pop));

   C_REQRSP_READ_REQUEST_ACCEPTED: cover property (@(posedge clk)
      disable iff (!reset_n) rreq_fire);
   C_REQRSP_BOTH_LINES_REQUESTED: cover property (@(posedge clk)
      disable iff (!reset_n) (req_owed == 8'd0));

   C_PROTO_READ_REQUEST_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (rreq_valid && !rreq_ready));
   C_PROTO_WRITE_REQUEST_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (wreq_valid && !wreq_ready));

   C_BOUNDRSP_ISSUE_WAIT_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_issue >= 10'd4));
   C_BOUNDRSP_DRAIN_WAIT_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_drain >= 10'd4));

   C_DEADLOCK_STALL_FOUR: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_stall >= 10'd4));

   C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
      disable iff (!reset_n) !post_reset);

   C_LIFECYCLE_WARM_WITH_TRAFFIC: cover property (@(posedge clk)
      disable iff (!reset_n) (warm && wdat_fire));

endmodule

bind nvdla_bdma_data_order_ft nvdla_bdma_targets u_targets (
   .clk(nvdla_core_clk), .reset_n(nvdla_core_rstn));
