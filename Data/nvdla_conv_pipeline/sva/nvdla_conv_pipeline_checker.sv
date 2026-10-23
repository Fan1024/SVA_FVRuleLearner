// ===========================================================================
// Independent oracle and candidate targets for the NVDLA convolution
// datapath: CDMA -> CBUF -> CSC -> CMAC_A/B -> CACC.
//
// Everything observed here is a signal that crosses a block boundary in
// `nvdla_conv_pipeline_ft`.  Nothing reaches inside CDMA's sequencers, CBUF's
// bank decode, CSC's dual-line buffer, CMAC's MAC array or CACC's assembly
// and delivery buffers.  The oracles are this file's own arithmetic:
//
//  1. A SYMBOLIC HALF-LINE of CBUF.  `sym_addr` / `sym_col` name one 512-bit
//     column entry, frozen by A_SYM_FROZEN.  `shadow` records what CDMA last
//     wrote there, `quiet` counts cycles since anything could have disturbed
//     it, and three arming shift registers -- one per CBUF read port -- carry
//     an armed read to the cycle its data is due.  The read-back targets are
//     the whole cdma->cbuf->csc closure: what came out is what went in,
//     through a 512 KiB banked memory with a two-deep write pipeline and a
//     six-deep read pipeline that this file does not model.
//
//     The disturbance rules are the file's own, and they are conservative:
//     CBUF's two write ports OR their decoded bank addresses together, so a
//     same-bank collision between the dat and the wt writer can land anywhere
//     in that bank and POISONS the shadow rather than updating it.  Likewise
//     the three read ports OR into one address per RAM, so a read of the
//     symbolic bank by another port DISARMS instead of being modelled.
//
//  2. A TOKEN QUEUE per MAC half.  `sc2mac_dat_*_pd` is pushed on its valid,
//     `mac_*2accu_pd` pops.  The queue, its pointers and its occupancy are
//     this file's; the design is asked only to deliver the head.
//
//  3. LEDGERS: CBUF entry credits granted versus released, SDP beats accepted
//     versus credits returned to CSC, and the fetch-side atom ledger the four
//     bounded responders publish.
//
//  4. SATURATING WAIT COUNTERS, which is how fairness, bounded response and
//     deadlock freedom are written as safety here.  No `s_eventually`: the
//     reset cut admits states unreachable from reset, so a liveness property
//     would be vacuous or false for a reason the design cannot correct.
//
// Field positions used, all read out of the generated RTL rather than a spec:
//   dma read command   pd[63:0] byte address, pd[78:64] atoms MINUS ONE
//   dma read response  pd[511:0] data, pd[513:512] one bit per 32-byte atom
//   CSB request        pd[21:0] word address, pd[53:22] write data,
//                      pd[54] write, pd[55] non-posted
//   sc2mac / mac2accu  pd[4:0] batch index, pd[5] stripe start,
//                      pd[6] stripe end, pd[7] channel end, pd[8] layer end
//   CBUF address       addr[11:8] bank, addr[7:0] row; the dat port reaches
//                      banks 0..14, the wt port 1..15, the wmb port 15 only
// ===========================================================================

module nvdla_conv_pipeline_checker (
   input wire         clk,
   input wire         reset_n,

   input wire [11:0]  sym_addr,
   input wire         sym_col,

   input wire [3:0]   mem_req_valid,
   input wire [3:0]   mem_req_ready,
   input wire [315:0] mem_req_pd_flat,
   input wire [3:0]   mem_rsp_valid,
   input wire [3:0]   mem_rsp_ready,
   input wire [63:0]  mem_owed_flat,

   input wire         buf_dat_wr_en,
   input wire [11:0]  buf_dat_wr_addr,
   input wire [1:0]   buf_dat_wr_hsel,
   input wire [1023:0] buf_dat_wr_data,
   input wire         buf_wt_wr_en,
   input wire [11:0]  buf_wt_wr_addr,
   input wire         buf_wt_wr_hsel,
   input wire [511:0] buf_wt_wr_data,

   input wire         buf_dat_rd_en,
   input wire [11:0]  buf_dat_rd_addr,
   input wire         buf_dat_rd_valid,
   input wire [1023:0] buf_dat_rd_data,
   input wire         buf_wt_rd_en,
   input wire [11:0]  buf_wt_rd_addr,
   input wire         buf_wt_rd_valid,
   input wire [1023:0] buf_wt_rd_data,
   input wire         buf_wmb_rd_en,
   input wire [7:0]   buf_wmb_rd_addr,
   input wire         buf_wmb_rd_valid,
   input wire [1023:0] buf_wmb_rd_data,

   input wire         cdma2sc_dat_updt,
   input wire [11:0]  cdma2sc_dat_entries,
   input wire         sc2cdma_dat_updt,
   input wire [11:0]  sc2cdma_dat_entries,
   input wire         cdma2sc_wt_updt,
   input wire [11:0]  cdma2sc_wt_entries,
   input wire         sc2cdma_wt_updt,
   input wire [11:0]  sc2cdma_wt_entries,
   input wire         cdma2sc_dat_pending_ack,
   input wire         sc2cdma_dat_pending_req,
   input wire         cdma2sc_wt_pending_ack,
   input wire         sc2cdma_wt_pending_req,

   input wire [1:0]   sc2mac_dat_pvld,
   input wire [17:0]  sc2mac_dat_pd_flat,
   input wire [1:0]   sc2mac_wt_pvld,

   input wire [1:0]   mac2accu_pvld,
   input wire [17:0]  mac2accu_pd_flat,

   input wire         sdp_valid,
   input wire         sdp_ready,
   input wire [513:0] sdp_pd,
   input wire         accu2sc_credit_vld,
   input wire [2:0]   accu2sc_credit_size,

   input wire [4:0]   csb_req_pvld,
   input wire [4:0]   csb_req_prdy,
   input wire [314:0] csb_req_pd_flat,
   input wire [4:0]   csb_resp_valid
);
   // ------------------------------------------------------------------ ages
   // `age` is the one gate every post-reset-pipeline obligation is written
   // against.  Under the reset cut the design's flops start arbitrary; a
   // property about a pipeline of depth d is meaningless before the pipeline
   // has been driven for d cycles, and saying so with a counter of this
   // file's own is the honest way to write it.  `age` is a KEPT register:
   // arbitrary, it would satisfy every gate at cycle zero and falsify targets
   // for a reason the design cannot correct.
   reg [7:0] age;
   always @(posedge clk) begin
      if (!reset_n)          age <= 8'd0;
      else if (age != 8'hff) age <= age + 8'd1;
   end

   wire warm4  = (age >= 8'd4);
   wire warm8  = (age >= 8'd8);
   wire warm16 = (age >= 8'd16);

   // ------------------------------------------------ symbolic CBUF line
   A_SYM_FROZEN: assume property (@(posedge clk)
      1'b1 |=> ($stable(sym_addr) && $stable(sym_col)));

   wire [3:0] sym_bank = sym_addr[11:8];
   wire [7:0] sym_row  = sym_addr[7:0];

   wire [3:0] dat_wr_bank = buf_dat_wr_addr[11:8];
   wire [3:0] wt_wr_bank  = buf_wt_wr_addr[11:8];
   wire [3:0] dat_rd_bank = buf_dat_rd_addr[11:8];
   wire [3:0] wt_rd_bank  = buf_wt_rd_addr[11:8];

   // CBUF ORs the two write ports' decoded addresses per RAM, so two writes
   // to one bank in one cycle produce an address that is neither of them.
   wire wr_bank_clash = buf_dat_wr_en && buf_wt_wr_en &&
                        (dat_wr_bank == wt_wr_bank);
   wire wr_poison     = wr_bank_clash &&
                        ((dat_wr_bank == sym_bank) || (wt_wr_bank == sym_bank));

   wire [511:0] dat_wr_half = sym_col ? buf_dat_wr_data[1023:512]
                                      : buf_dat_wr_data[511:0];
   wire dat_wr_hit = buf_dat_wr_en && (buf_dat_wr_addr == sym_addr) &&
                     buf_dat_wr_hsel[sym_col];
   wire wt_wr_hit  = buf_wt_wr_en  && (buf_wt_wr_addr  == sym_addr) &&
                     (buf_wt_wr_hsel == sym_col);
   wire line_write = (dat_wr_hit || wt_wr_hit) && !wr_bank_clash;
   wire line_touch = line_write || wr_poison;

   reg [511:0] shadow;
   reg         shadow_valid;
   reg [3:0]   quiet;

   always @(posedge clk) begin
      if (!reset_n) begin
         shadow       <= 512'd0;
         shadow_valid <= 1'b0;
         quiet        <= 4'd0;
      end else if (wr_poison) begin
         shadow_valid <= 1'b0;
         quiet        <= 4'd0;
      end else if (line_write) begin
         shadow       <= wt_wr_hit ? buf_wt_wr_data : dat_wr_half;
         shadow_valid <= 1'b1;
         quiet        <= 4'd0;
      end else if (quiet != 4'hf) begin
         quiet        <= quiet + 4'd1;
      end
   end

   // A write commits into the RAM two cycles after it is presented, and the
   // RAM read for a read presented at t happens on the edge ending t+1.  Four
   // quiet cycles is therefore comfortably enough for `shadow` to be what the
   // memory holds, with no read/write collision in the window.
   wire line_settled = shadow_valid && (quiet >= 4'd4);

   // Arming.  A read of the symbolic line is armed only when no other read
   // port selects the symbolic bank in the same cycle -- CBUF ORs the three
   // read ports' addresses per RAM the same way it ORs the writers'.
   wire dat_rd_issue = buf_dat_rd_en && (buf_dat_rd_addr == sym_addr);
   wire dat_rd_clash = (buf_wt_rd_en && (wt_rd_bank == sym_bank)) ||
                       (buf_wmb_rd_en && (sym_bank == 4'd15));
   wire dat_arm_now  = dat_rd_issue && (sym_bank <= 4'd14) &&
                       !dat_rd_clash && line_settled;

   wire wt_rd_issue  = buf_wt_rd_en && (buf_wt_rd_addr == sym_addr);
   wire wt_rd_clash  = (buf_dat_rd_en && (dat_rd_bank == sym_bank)) ||
                       (buf_wmb_rd_en && (sym_bank == 4'd15));
   wire wt_arm_now   = wt_rd_issue && (sym_bank >= 4'd1) &&
                       !wt_rd_clash && line_settled;

   wire wmb_rd_issue = buf_wmb_rd_en && (buf_wmb_rd_addr == sym_row);
   wire wmb_rd_clash = buf_wt_rd_en && (wt_rd_bank == 4'd15);
   wire wmb_arm_now  = wmb_rd_issue && (sym_bank == 4'd15) &&
                       !wmb_rd_clash && line_settled;

   reg [5:0]   dat_arm;  reg [511:0] dat_exp;
   reg [5:0]   wt_arm;   reg [511:0] wt_exp;
   reg [5:0]   wmb_arm;  reg [511:0] wmb_exp;

   always @(posedge clk) begin
      if (!reset_n) begin
         dat_arm <= 6'd0;  wt_arm <= 6'd0;  wmb_arm <= 6'd0;
         dat_exp <= 512'd0; wt_exp <= 512'd0; wmb_exp <= 512'd0;
      end else begin
         if (line_touch)        dat_arm <= 6'd0;
         else if (dat_arm_now)  dat_arm <= 6'b000001;
         else                   dat_arm <= {dat_arm[4:0], 1'b0};

         if (line_touch)        wt_arm <= 6'd0;
         else if (wt_arm_now)   wt_arm <= 6'b000001;
         else                   wt_arm <= {wt_arm[4:0], 1'b0};

         if (line_touch)        wmb_arm <= 6'd0;
         else if (wmb_arm_now)  wmb_arm <= 6'b000001;
         else                   wmb_arm <= {wmb_arm[4:0], 1'b0};

         if (!line_touch && dat_arm_now) dat_exp <= shadow;
         if (!line_touch && wt_arm_now)  wt_exp  <= shadow;
         if (!line_touch && wmb_arm_now) wmb_exp <= shadow;
      end
   end

   wire [511:0] dat_rd_half = sym_col ? buf_dat_rd_data[1023:512]
                                      : buf_dat_rd_data[511:0];
   wire [511:0] wt_rd_half  = sym_col ? buf_wt_rd_data[1023:512]
                                      : buf_wt_rd_data[511:0];
   wire [511:0] wmb_rd_half = sym_col ? buf_wmb_rd_data[1023:512]
                                      : buf_wmb_rd_data[511:0];

   // The last value the dat port returned for the symbolic line, and whether
   // the line has stayed untouched since.  This is what makes "the line does
   // not change on its own" and "the two read ports see one memory" statable
   // without a second shadow.
   reg [511:0] last_dat_half;
   reg         last_dat_valid;
   always @(posedge clk) begin
      if (!reset_n) begin
         last_dat_half  <= 512'd0;
         last_dat_valid <= 1'b0;
      end else if (line_touch) begin
         last_dat_valid <= 1'b0;
      end else if (dat_arm[5]) begin
         last_dat_half  <= dat_rd_half;
         last_dat_valid <= 1'b1;
      end
   end

   // ------------------------------------------- CBUF read issue shadow
   // Six-deep, one bit per port: the file's own record of what was asked for,
   // against which the design's read-valid pipeline is judged.
   reg [5:0] dat_en_sr, wt_en_sr, wmb_en_sr;
   reg [3:0] dat_inflight;
   always @(posedge clk) begin
      if (!reset_n) begin
         dat_en_sr <= 6'd0; wt_en_sr <= 6'd0; wmb_en_sr <= 6'd0;
         dat_inflight <= 4'd0;
      end else begin
         dat_en_sr <= {dat_en_sr[4:0], buf_dat_rd_en};
         wt_en_sr  <= {wt_en_sr[4:0],  buf_wt_rd_en};
         wmb_en_sr <= {wmb_en_sr[4:0], buf_wmb_rd_en};
         case ({buf_dat_rd_en, dat_en_sr[5]})
            2'b10: if (dat_inflight != 4'hf) dat_inflight <= dat_inflight + 4'd1;
            2'b01: if (dat_inflight != 4'd0) dat_inflight <= dat_inflight - 4'd1;
            default: ;
         endcase
      end
   end

   // -------------------------------------------------- MAC token queues
   // Lane 0 is CMAC_A, lane 1 is CMAC_B.  The CMAC valid path is four
   // unconditional flops on the ungated core clock, so a token pushed at t is
   // due out at t+4; the queue is depth 8, four times what can be in flight.
   wire [8:0] sc_pd   [0:1];
   wire [8:0] mac_pd  [0:1];
   assign sc_pd[0]  = sc2mac_dat_pd_flat[8:0];
   assign sc_pd[1]  = sc2mac_dat_pd_flat[17:9];
   assign mac_pd[0] = mac2accu_pd_flat[8:0];
   assign mac_pd[1] = mac2accu_pd_flat[17:9];

   reg [8:0]  tok_mem [0:15];
   reg [2:0]  tok_wr  [0:1];
   reg [2:0]  tok_rd  [0:1];
   reg [3:0]  tok_cnt [0:1];
   reg [15:0] tok_push [0:1];
   reg [15:0] tok_pop  [0:1];

   wire [1:0] tok_push_now = sc2mac_dat_pvld;
   wire [1:0] tok_pop_now  = mac2accu_pvld & {2{warm4}};

   integer L;
   always @(posedge clk) begin
      if (!reset_n) begin
         for (L = 0; L < 2; L = L + 1) begin
            tok_wr[L]   <= 3'd0;
            tok_rd[L]   <= 3'd0;
            tok_cnt[L]  <= 4'd0;
            tok_push[L] <= 16'd0;
            tok_pop[L]  <= 16'd0;
         end
      end else begin
         for (L = 0; L < 2; L = L + 1) begin
            if (tok_push_now[L]) begin
               tok_mem[(L*8) + tok_wr[L]] <= sc_pd[L];
               tok_wr[L]   <= tok_wr[L] + 3'd1;
               if (tok_push[L] != 16'hffff) tok_push[L] <= tok_push[L] + 16'd1;
            end
            if (tok_pop_now[L]) begin
               tok_rd[L]  <= tok_rd[L] + 3'd1;
               if (tok_pop[L] != 16'hffff) tok_pop[L] <= tok_pop[L] + 16'd1;
            end
            case ({tok_push_now[L], tok_pop_now[L]})
               2'b10: if (tok_cnt[L] != 4'hf) tok_cnt[L] <= tok_cnt[L] + 4'd1;
               2'b01: if (tok_cnt[L] != 4'd0) tok_cnt[L] <= tok_cnt[L] - 4'd1;
               default: ;
            endcase
         end
      end
   end

   // ------------------------------------------- SDP beats and CSC credits
   // CACC returns exactly one credit, one cycle after each accepted SDP beat.
   // Two counters over the same event stream, one of them delayed by a cycle,
   // is a conservation statement that survives a common saturation cap.
   wire sdp_fire = sdp_valid && sdp_ready;
   reg [15:0] sdp_beats, sdp_beats_d1, sdp_credits;
   always @(posedge clk) begin
      if (!reset_n) begin
         sdp_beats <= 16'd0; sdp_beats_d1 <= 16'd0; sdp_credits <= 16'd0;
      end else begin
         sdp_beats_d1 <= sdp_beats;
         if (sdp_fire && (sdp_beats != 16'hffff))
            sdp_beats <= sdp_beats + 16'd1;
         if (accu2sc_credit_vld && (sdp_credits != 16'hffff))
            sdp_credits <= sdp_credits + 16'd1;
      end
   end

   // ------------------------------------------- CBUF entry credit ledgers
   reg [15:0] dat_wr_beats;
   always @(posedge clk) begin
      if (!reset_n)                                        dat_wr_beats <= 16'd0;
      else if (buf_dat_wr_en && (dat_wr_beats != 16'hffff)) dat_wr_beats <= dat_wr_beats + 16'd1;
   end

   reg [23:0] dat_granted, dat_released, wt_granted, wt_released;
   always @(posedge clk) begin
      if (!reset_n) begin
         dat_granted <= 24'd0; dat_released <= 24'd0;
         wt_granted  <= 24'd0; wt_released  <= 24'd0;
      end else begin
         if (cdma2sc_dat_updt)
            dat_granted  <= (dat_granted  > (24'hffffff - {12'd0, cdma2sc_dat_entries}))
                            ? 24'hffffff : dat_granted + {12'd0, cdma2sc_dat_entries};
         if (sc2cdma_dat_updt)
            dat_released <= (dat_released > (24'hffffff - {12'd0, sc2cdma_dat_entries}))
                            ? 24'hffffff : dat_released + {12'd0, sc2cdma_dat_entries};
         if (cdma2sc_wt_updt)
            wt_granted   <= (wt_granted   > (24'hffffff - {12'd0, cdma2sc_wt_entries}))
                            ? 24'hffffff : wt_granted + {12'd0, cdma2sc_wt_entries};
         if (sc2cdma_wt_updt)
            wt_released  <= (wt_released  > (24'hffffff - {12'd0, sc2cdma_wt_entries}))
                            ? 24'hffffff : wt_released + {12'd0, sc2cdma_wt_entries};
      end
   end

   // ------------------------------------------------ saturating wait counters
   wire [78:0] mem_req_pd0  = mem_req_pd_flat[78:0];
   wire [78:0] mem_req_pd2  = mem_req_pd_flat[236:158];
   wire [15:0] mem_owed0    = mem_owed_flat[15:0];
   wire [15:0] mem_owed2    = mem_owed_flat[47:32];

   reg [9:0] wait_mem_rsp0;      // response offered, CDMA not taking it
   reg [9:0] wait_dat_pending;   // CSC asking CDMA for data, no ack
   reg [9:0] wait_wt_pending;
   reg [11:0] wait_owed0;        // fetch command outstanding, no beat accepted
   reg [11:0] wait_progress;     // nothing moving anywhere on the datapath

   wire any_boundary_event =
      (|(mem_req_valid & mem_req_ready)) || (|(mem_rsp_valid & mem_rsp_ready)) ||
      buf_dat_wr_en || buf_wt_wr_en ||
      buf_dat_rd_en || buf_wt_rd_en || buf_wmb_rd_en ||
      (|sc2mac_dat_pvld) || (|sc2mac_wt_pvld) || (|mac2accu_pvld) || sdp_fire;

   wire any_work_outstanding =
      (mem_owed_flat != 64'd0) || (dat_inflight != 4'd0) ||
      (tok_cnt[0] != 4'd0) || (tok_cnt[1] != 4'd0) || sdp_valid;

   always @(posedge clk) begin
      if (!reset_n) begin
         wait_mem_rsp0    <= 10'd0;
         wait_dat_pending <= 10'd0;
         wait_wt_pending  <= 10'd0;
         wait_owed0       <= 12'd0;
         wait_progress    <= 12'd0;
      end else begin
         if (mem_rsp_valid[0] && !mem_rsp_ready[0]) begin
            if (wait_mem_rsp0 != 10'h3ff) wait_mem_rsp0 <= wait_mem_rsp0 + 10'd1;
         end else wait_mem_rsp0 <= 10'd0;

         if (sc2cdma_dat_pending_req && !cdma2sc_dat_pending_ack) begin
            if (wait_dat_pending != 10'h3ff) wait_dat_pending <= wait_dat_pending + 10'd1;
         end else wait_dat_pending <= 10'd0;

         if (sc2cdma_wt_pending_req && !cdma2sc_wt_pending_ack) begin
            if (wait_wt_pending != 10'h3ff) wait_wt_pending <= wait_wt_pending + 10'd1;
         end else wait_wt_pending <= 10'd0;

         if ((mem_owed0 != 16'd0) && !(mem_rsp_valid[0] && mem_rsp_ready[0])) begin
            if (wait_owed0 != 12'hfff) wait_owed0 <= wait_owed0 + 12'd1;
         end else wait_owed0 <= 12'd0;

         if (any_work_outstanding && !any_boundary_event) begin
            if (wait_progress != 12'hfff) wait_progress <= wait_progress + 12'd1;
         end else wait_progress <= 12'd0;
      end
   end

   // ------------------------------------------------------- CSB decode
   wire [62:0] csb_pd [0:4];
   assign csb_pd[0] = csb_req_pd_flat[62:0];
   assign csb_pd[1] = csb_req_pd_flat[125:63];
   assign csb_pd[2] = csb_req_pd_flat[188:126];
   assign csb_pd[3] = csb_req_pd_flat[251:189];
   assign csb_pd[4] = csb_req_pd_flat[314:252];

   // resp_valid(t) == pvld(t-2) && (read or non-posted write), from the two
   // flops in every one of the five generated regfiles.
   wire [4:0] csb_answerable;
   assign csb_answerable[0] = csb_req_pvld[0] && (!csb_pd[0][54] || csb_pd[0][55]);
   assign csb_answerable[1] = csb_req_pvld[1] && (!csb_pd[1][54] || csb_pd[1][55]);
   assign csb_answerable[2] = csb_req_pvld[2] && (!csb_pd[2][54] || csb_pd[2][55]);
   assign csb_answerable[3] = csb_req_pvld[3] && (!csb_pd[3][54] || csb_pd[3][55]);
   assign csb_answerable[4] = csb_req_pvld[4] && (!csb_pd[4][54] || csb_pd[4][55]);

   wire [4:0] csb_posted_write;
   assign csb_posted_write[0] = csb_req_pvld[0] && csb_pd[0][54] && !csb_pd[0][55];
   assign csb_posted_write[1] = csb_req_pvld[1] && csb_pd[1][54] && !csb_pd[1][55];
   assign csb_posted_write[2] = csb_req_pvld[2] && csb_pd[2][54] && !csb_pd[2][55];
   assign csb_posted_write[3] = csb_req_pvld[3] && csb_pd[3][54] && !csb_pd[3][55];
   assign csb_posted_write[4] = csb_req_pvld[4] && csb_pd[4][54] && !csb_pd[4][55];

   // =======================================================================
   // 1. END-TO-END ORDERING
   // =======================================================================

   T_ORDER_CBUF_DAT_RD_VALID_TRACKS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm8 |-> (buf_dat_rd_valid == dat_en_sr[5]));

   T_ORDER_CBUF_WT_RD_VALID_TRACKS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm8 |-> (buf_wt_rd_valid == wt_en_sr[5]));

   T_ORDER_MAC_A_PD_IS_QUEUE_HEAD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && mac2accu_pvld[0]) |->
         ((tok_cnt[0] != 4'd0) && (mac_pd[0] == tok_mem[tok_rd[0]])));

   T_ORDER_MAC_B_PD_IS_QUEUE_HEAD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && mac2accu_pvld[1]) |->
         ((tok_cnt[1] != 4'd0) && (mac_pd[1] == tok_mem[8 + tok_rd[1]])));

   // =======================================================================
   // 2. DATA INTEGRITY
   // =======================================================================

   T_DATA_CBUF_DAT_READBACK: assert property (@(posedge clk)
      disable iff (!reset_n)
      dat_arm[5] |-> (buf_dat_rd_valid && (dat_rd_half == dat_exp)));

   T_DATA_CBUF_WT_READBACK: assert property (@(posedge clk)
      disable iff (!reset_n)
      wt_arm[5] |-> (buf_wt_rd_valid && (wt_rd_half == wt_exp)));

   T_DATA_CBUF_WMB_READBACK: assert property (@(posedge clk)
      disable iff (!reset_n)
      wmb_arm[5] |-> (buf_wmb_rd_valid && (wmb_rd_half == wmb_exp)));

   T_DATA_MAC_A_PD_PRESERVED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && mac2accu_pvld[0]) |-> (mac_pd[0] == $past(sc_pd[0], 4)));

   T_DATA_CBUF_DAT_LINE_STABLE_WITHOUT_WRITE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (dat_arm[5] && last_dat_valid) |-> (dat_rd_half == last_dat_half));

   // =======================================================================
   // 3. UNIQUENESS / NO DUPLICATION
   // =======================================================================

   T_UNIQ_MAC_A_NO_OUTPUT_WITHOUT_INPUT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && mac2accu_pvld[0]) |-> (tok_push[0] > tok_pop[0]));

   T_UNIQ_MAC_B_NO_OUTPUT_WITHOUT_INPUT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && mac2accu_pvld[1]) |-> (tok_push[1] > tok_pop[1]));

   // =======================================================================
   // 4. NO LOSS / CONSERVATION
   // =======================================================================

   T_CONSERV_SDP_BEATS_EQ_CREDITS: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm4 |-> (sdp_credits == sdp_beats_d1));

   T_CONSERV_MAC_A_TOKENS: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm8 |-> (tok_push[0] == (tok_pop[0] + {12'd0, tok_cnt[0]})));

   T_CONSERV_CBUF_DAT_ENTRIES_NOT_OVERRELEASED: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm16 |-> (dat_released <= dat_granted));

   T_CONSERV_CBUF_WT_ENTRIES_NOT_OVERRELEASED: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm16 |-> (wt_released <= wt_granted));

   // =======================================================================
   // 5. MUTUAL EXCLUSION / ONE-HOT
   // =======================================================================

   T_MUTEX_CBUF_WR_PORT_BANK_EXCLUSIVE: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm16 |-> !wr_bank_clash);

   T_MUTEX_CBUF_RD_PORT_BANK_EXCLUSIVE: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm16 |-> !((buf_dat_rd_en && buf_wt_rd_en && (dat_rd_bank == wt_rd_bank)) ||
                   (buf_wt_rd_en && buf_wmb_rd_en && (wt_rd_bank == 4'd15))));

   T_MUTEX_MEM_DAT_PORT_ONEHOT: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm16 |-> !(mem_req_valid[0] && mem_req_valid[1]));

   // =======================================================================
   // 6. OCCUPANCY AND BOUNDS
   // =======================================================================

   T_BOUND_MAC_A_TOKENS_IN_FLIGHT_LE4: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm8 |-> (tok_cnt[0] <= 4'd4));

   T_BOUND_CBUF_DAT_READS_IN_FLIGHT_LE6: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm8 |-> (dat_inflight <= 4'd6));

   T_BOUND_MEM_DAT_REQ_ATOMS_LE256: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && mem_req_valid[0]) |-> (mem_req_pd0[78:64] < 15'd256));

   T_BOUND_CBUF_DAT_WR_ADDR_IN_RANGE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && buf_dat_wr_en) |-> (buf_dat_wr_addr[11:8] <= 4'd14));

   // =======================================================================
   // 7. ALLOCATOR DISCIPLINE
   // =======================================================================

   T_ALLOC_CBUF_DAT_NO_RELEASE_WITHOUT_GRANT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && sc2cdma_dat_updt) |->
         ((dat_released + {12'd0, sc2cdma_dat_entries}) <= dat_granted));

   T_ALLOC_CBUF_WT_NO_RELEASE_WITHOUT_GRANT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && sc2cdma_wt_updt) |->
         ((wt_released + {12'd0, sc2cdma_wt_entries}) <= wt_granted));

   T_ALLOC_CBUF_DAT_NO_GRANT_BEFORE_WRITE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && cdma2sc_dat_updt && (cdma2sc_dat_entries != 12'd0)) |->
         (dat_wr_beats != 16'd0));

   // =======================================================================
   // 8. REQUEST-RESPONSE CORRESPONDENCE
   // =======================================================================

   T_REQRSP_CDMA_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm4 |-> (csb_resp_valid[0] == $past(csb_answerable[0], 2)));

   T_REQRSP_CSC_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm4 |-> (csb_resp_valid[1] == $past(csb_answerable[1], 2)));

   T_REQRSP_CACC_CSB_RESP_SOLICITED: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm4 |-> (csb_resp_valid[4] == $past(csb_answerable[4], 2)));

   T_REQRSP_ACCU_CREDIT_MATCHES_SDP_BEAT: assert property (@(posedge clk)
      disable iff (!reset_n)
      warm4 |-> (accu2sc_credit_vld == $past(sdp_fire)));

   T_REQRSP_CBUF_DAT_RD_VALID_HAS_ISSUE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && buf_dat_rd_valid) |-> (dat_inflight != 4'd0));

   // =======================================================================
   // 9. PROTOCOL CONFORMANCE
   // =======================================================================

   T_PROTO_CSB_PRDY_ALWAYS_HIGH: assert property (@(posedge clk)
      disable iff (!reset_n)
      (csb_req_prdy == 5'b11111));

   T_PROTO_MEM_DAT_REQ_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (mem_req_valid[0] && !mem_req_ready[0]) |=>
         (mem_req_valid[0] && $stable(mem_req_pd_flat[78:0])));

   T_PROTO_MEM_DAT_REQ_ADDR_ALIGNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm16 && mem_req_valid[0]) |-> (mem_req_pd0[4:0] == 5'd0));

   T_PROTO_SDP_VALID_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sdp_valid && !sdp_ready) |=> (sdp_valid && $stable(sdp_pd)));

   T_PROTO_ACCU_CREDIT_SIZE_IS_ONE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (accu2sc_credit_size == 3'd1));

   // =======================================================================
   // 10. ARBITRATION FAIRNESS  (saturating wait counters, bounded safety)
   // =======================================================================

   T_FAIR_CSC_DAT_PENDING_ACKED_WITHIN_512: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wait_dat_pending < 10'd512));

   T_FAIR_CSC_WT_PENDING_ACKED_WITHIN_512: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wait_wt_pending < 10'd512));

   // =======================================================================
   // 11. BOUNDED RESPONSE
   // =======================================================================

   T_BOUNDRSP_CBUF_DAT_RD_ANSWERED_IN_6: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && buf_dat_rd_en) |-> ##6 buf_dat_rd_valid);

   T_BOUNDRSP_MAC_A_OUTPUT_IN_4: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && sc2mac_dat_pvld[0]) |-> ##4 mac2accu_pvld[0]);

   T_BOUNDRSP_MEM_DAT_RSP_TAKEN_WITHIN_256: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wait_mem_rsp0 < 10'd256));

   // =======================================================================
   // 12. DEADLOCK FREEDOM
   // =======================================================================

   T_DEADLOCK_CONV_PIPELINE_PROGRESS_WITHIN_1024: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wait_progress < 12'd1024));

   T_DEADLOCK_MEM_DAT_COMMAND_DRAINS_WITHIN_256: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wait_owed0 < 12'd256));

   // =======================================================================
   // 13. RESET / INITIALISATION
   // =======================================================================

   T_RESET_CBUF_READ_VALIDS_LOW: assert property (@(posedge clk)
      disable iff (!reset_n)
      (age == 8'd0) |->
         (!buf_dat_rd_valid && !buf_wt_rd_valid && !buf_wmb_rd_valid));

   T_RESET_MAC_OUTPUTS_IDLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (age == 8'd0) |-> (mac2accu_pvld == 2'd0));

   T_RESET_CSB_RESPONSES_IDLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (age == 8'd0) |-> (csb_resp_valid == 5'd0));

   // =======================================================================
   // 14. LIFECYCLE / ACCESS CONTROL
   // =======================================================================

   T_LIFECYCLE_CSB_POSTED_WRITE_IS_SILENT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm4 && $past(csb_posted_write[0], 2)) |-> !csb_resp_valid[0]);

   T_LIFECYCLE_MAC_A_PD_HELD_UNLESS_VALID: assert property (@(posedge clk)
      disable iff (!reset_n)
      (warm8 && !mac2accu_pvld[0]) |-> (mac_pd[0] == $past(mac_pd[0])));

   // =======================================================================
   // 15. COHERENCE
   // =======================================================================

   T_COHERENCE_CBUF_DAT_WT_SAME_LINE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wt_arm[5] && last_dat_valid) |-> (wt_rd_half == last_dat_half));


   // =======================================================================
   // COVERS.  Not targets.  One per category at least, plus the reachability
   // witnesses the read-back oracle needs: a target whose arming condition is
   // unreachable is vacuous, and C_DATA_* is how that is seen.
   // =======================================================================

   reg seen_dat_readback, seen_wt_readback, seen_wmb_readback;
   reg seen_mem_dat_rsp, seen_mem_wt_rsp;
   always @(posedge clk) begin
      if (!reset_n) begin
         seen_dat_readback <= 1'b0; seen_wt_readback <= 1'b0;
         seen_wmb_readback <= 1'b0;
         seen_mem_dat_rsp  <= 1'b0; seen_mem_wt_rsp  <= 1'b0;
      end else begin
         if (dat_arm[5]) seen_dat_readback <= 1'b1;
         if (wt_arm[5])  seen_wt_readback  <= 1'b1;
         if (wmb_arm[5]) seen_wmb_readback <= 1'b1;
         if (mem_rsp_valid[0] && mem_rsp_ready[0]) seen_mem_dat_rsp <= 1'b1;
         if (mem_rsp_valid[2] && mem_rsp_ready[2]) seen_mem_wt_rsp  <= 1'b1;
      end
   end

   // -- 1 ordering / 2 data integrity: the symbolic line is written, settles,
   //    is read by each port, and the data comes back.
   C_DATA_CBUF_LINE_WRITTEN: cover property (@(posedge clk)
      disable iff (!reset_n) line_write);
   C_DATA_CBUF_LINE_SETTLED: cover property (@(posedge clk)
      disable iff (!reset_n) line_settled);
   C_DATA_CBUF_DAT_ARMED: cover property (@(posedge clk)
      disable iff (!reset_n) dat_arm_now);
   C_DATA_CBUF_DAT_READBACK: cover property (@(posedge clk)
      disable iff (!reset_n) dat_arm[5]);
   C_DATA_CBUF_WT_READBACK: cover property (@(posedge clk)
      disable iff (!reset_n) wt_arm[5]);
   C_DATA_CBUF_WMB_READBACK: cover property (@(posedge clk)
      disable iff (!reset_n) wmb_arm[5]);
   C_DATA_CBUF_DAT_TWO_READBACKS: cover property (@(posedge clk)
      disable iff (!reset_n) (dat_arm[5] && last_dat_valid));
   C_DATA_CBUF_WRITTEN_BY_BOTH_PORTS: cover property (@(posedge clk)
      disable iff (!reset_n) (dat_wr_hit ##[1:32] wt_wr_hit));
   C_ORDER_CBUF_DAT_RD_VALID: cover property (@(posedge clk)
      disable iff (!reset_n) (warm8 && buf_dat_rd_valid));
   C_ORDER_MAC_A_QUEUE_DEPTH_2: cover property (@(posedge clk)
      disable iff (!reset_n) (warm8 && (tok_cnt[0] >= 4'd2)));

   // -- 3 uniqueness / 4 conservation / 6 bounds
   C_CONSERV_SDP_BEAT_ACCEPTED: cover property (@(posedge clk)
      disable iff (!reset_n) sdp_fire);
   C_CONSERV_SDP_FOUR_BEATS: cover property (@(posedge clk)
      disable iff (!reset_n) (sdp_beats >= 16'd4));
   C_CONSERV_CBUF_DAT_ENTRIES_GRANTED: cover property (@(posedge clk)
      disable iff (!reset_n) (cdma2sc_dat_updt && (cdma2sc_dat_entries != 12'd0)));
   C_CONSERV_CBUF_DAT_ENTRIES_RELEASED: cover property (@(posedge clk)
      disable iff (!reset_n) (sc2cdma_dat_updt && (sc2cdma_dat_entries != 12'd0)));
   C_BOUND_MAC_A_FULL_PIPE: cover property (@(posedge clk)
      disable iff (!reset_n) (warm8 && (tok_cnt[0] == 4'd4)));
   C_BOUND_CBUF_DAT_READS_IN_FLIGHT_6: cover property (@(posedge clk)
      disable iff (!reset_n) (warm8 && (dat_inflight == 4'd6)));

   // -- 5 mutual exclusion: both CBUF writers and two readers active at once,
   //    in different banks, which is the case the exclusion targets survive.
   C_MUTEX_BOTH_WRITERS_DIFFERENT_BANKS: cover property (@(posedge clk)
      disable iff (!reset_n)
      (buf_dat_wr_en && buf_wt_wr_en && (dat_wr_bank != wt_wr_bank)));
   C_MUTEX_TWO_READERS_DIFFERENT_BANKS: cover property (@(posedge clk)
      disable iff (!reset_n)
      (buf_dat_rd_en && buf_wt_rd_en && (dat_rd_bank != wt_rd_bank)));

   // -- 7 allocator / 8 request-response / 9 protocol
   C_ALLOC_GRANT_THEN_RELEASE: cover property (@(posedge clk)
      disable iff (!reset_n) (cdma2sc_dat_updt ##[1:64] sc2cdma_dat_updt));
   C_REQRSP_CDMA_CSB_RESPONSE: cover property (@(posedge clk)
      disable iff (!reset_n) csb_resp_valid[0]);
   C_REQRSP_CSC_CSB_RESPONSE: cover property (@(posedge clk)
      disable iff (!reset_n) csb_resp_valid[1]);
   C_REQRSP_MEM_DAT_AND_WT_BOTH_SERVED: cover property (@(posedge clk)
      disable iff (!reset_n) (seen_mem_dat_rsp && seen_mem_wt_rsp));
   C_PROTO_MEM_DAT_REQ_STALLED: cover property (@(posedge clk)
      disable iff (!reset_n) (mem_req_valid[0] && !mem_req_ready[0]));
   C_PROTO_SDP_BACKPRESSURE: cover property (@(posedge clk)
      disable iff (!reset_n) (sdp_valid && !sdp_ready));

   // -- 10 fairness / 11 bounded response / 12 deadlock: the wait counters
   //    reach a depth worth bounding, otherwise the bound is trivial.
   C_FAIR_DAT_PENDING_WAIT_8: cover property (@(posedge clk)
      disable iff (!reset_n) (wait_dat_pending >= 10'd8));
   C_BOUNDRSP_MEM_DAT_RSP_WAIT_4: cover property (@(posedge clk)
      disable iff (!reset_n) (wait_mem_rsp0 >= 10'd4));
   C_DEADLOCK_PIPELINE_STALL_16: cover property (@(posedge clk)
      disable iff (!reset_n) (wait_progress >= 12'd16));
   C_DEADLOCK_WORK_OUTSTANDING: cover property (@(posedge clk)
      disable iff (!reset_n) any_work_outstanding);

   // -- 13 reset / 14 lifecycle / 15 coherence
   C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
      disable iff (!reset_n) (age == 8'd0));
   C_LIFECYCLE_CSB_POSTED_WRITE: cover property (@(posedge clk)
      disable iff (!reset_n) csb_posted_write[0]);
   C_LIFECYCLE_MAC_A_PD_HELD: cover property (@(posedge clk)
      disable iff (!reset_n) (warm8 && !mac2accu_pvld[0] && $past(mac2accu_pvld[0])));
   C_COHERENCE_DAT_THEN_WT_SAME_LINE: cover property (@(posedge clk)
      disable iff (!reset_n) (wt_arm[5] && last_dat_valid));

   // Full-depth witness: the datapath carries a symbolic CBUF line all the
   // way from a fetch response to an SDP beat within one window.
   C_E2E_FETCH_TO_SDP: cover property (@(posedge clk)
      disable iff (!reset_n)
      ((mem_rsp_valid[0] && mem_rsp_ready[0]) ##[1:200] buf_dat_wr_en
                                              ##[1:200] buf_dat_rd_valid
                                              ##[1:200] (|mac2accu_pvld)
                                              ##[1:200] sdp_fire));

endmodule
