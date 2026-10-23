// ===========================================================================
// Candidate target assertions for the real NVDLA CDP synchronization FIFO.
//
// Bound into the formal top, so every reference below is a hierarchical name
// from `nvdla_cdp_syncfifo_order_ft`.  NOTHING HERE IS AN ASSUMPTION.  This
// task has NO assumptions at all -- not in the diag and not in the package --
// and this file adds none.  Both input valids, both input payloads and all
// three output readies stay free.
//
// WHAT THE BLOCK DOES.  Three stateful streams share nothing but a clock:
//
//   cvt2sync  -- one 87-bit beat is a PAIR.  Bits 71:0 go down the `data`
//                path (one bubble-collapse pipe stage p1, then the 80x72
//                data FIFO) and leave on sync2mul.  Bits 86:72 go down the
//                `info` path (pipe stage p2, then the 80x15 info FIFO) and
//                leave on sync2ocvt.  The pair enters BOTH or NEITHER --
//                cvt2sync_prdy is the AND of the two pipe readies -- and then
//                the halves drain independently.
//   sum2sync  -- 168-bit beats straight into the 60x168 sumpd FIFO, out on
//                sync2itp.  No input pipe stage.
//
// So the data path holds at most 1 (pipe) + 80 (RAM) + 1 (output register)
// == 82 beats, the info path the same, and the sum path 60 + 1 == 61.
//
// THE ORACLES ARE THIS FILE'S OWN.
//
//   * three DIFFERENCE COUNTERS driven only by the five public handshakes --
//     beats accepted minus beats delivered, one per stream.  The package
//     checker keeps positional reference QUEUES; these are counts, and the
//     interesting claim is that a count reconstructed at the boundary equals
//     the design's own distributed occupancy, stage by stage.
//   * three XOR ACCUMULATORS, one per stream, over the accepted input payload
//     and over the delivered output payload.  That catches a dropped,
//     duplicated or corrupted beat BY CONTENT, which is a different oracle
//     from the checker's positional `data_ref` / `info_ref` / `sum_ref`.
//   * POINTER ARITHMETIC done here: the modulo-depth gap between a FIFO's
//     write and read address must equal its occupancy.  The design never
//     computes that quantity.
//   * SATURATING COUNTERS, which is how a bounded-response or deadlock
//     obligation is written as a safety property.  There is no `s_eventually`
//     and no unbounded liveness anywhere in this file.
//
// RESET.  This module's registers are reset-initialised and every claim that
// reads one is stated for a run that starts in the design's reset state.
// Under `ENTER_FRA_KEEP` only registers matched by the task's `design_keep`
// are given their reset value, and that pattern names `u_checker.*` and
// nothing else.  So a screen of the oracle-backed claims below must be run
// with
//
//     --keep-extra 'u_targets\.'
//
// or those claims are falsified at cycle 0 for a reason that is not the
// design's.  The claims that read only design signals need no such flag.
// `taskdef.json` is deliberately NOT edited: adding to `design_keep` would
// change the abstraction the existing target T_SYNCFIFO_DATA_ORDER is
// measured under.
// ===========================================================================

module nvdla_cdp_targets (input wire clk, input wire reset_n);

   localparam [7:0] N_CVT_PATH = 8'd82;   // 1 pipe + 80 RAM + 1 output reg
   localparam [7:0] N_SUM_PATH = 8'd61;   // 60 RAM + 1 output reg
   localparam [9:0] N_DELIVER  = 10'd32;
   localparam [9:0] N_STALL    = 10'd64;

   // ------------------------------------------------------------- boundary
   wire         cvt_valid  = nvdla_cdp_syncfifo_order_ft.cvt2sync_pvld;
   wire         cvt_ready  = nvdla_cdp_syncfifo_order_ft.cvt2sync_prdy;
   wire [86:0]  cvt_pd     = nvdla_cdp_syncfifo_order_ft.cvt2sync_pd;
   wire         sum_valid  = nvdla_cdp_syncfifo_order_ft.sum2sync_pvld;
   wire         sum_ready  = nvdla_cdp_syncfifo_order_ft.sum2sync_prdy;
   wire [167:0] sum_pd     = nvdla_cdp_syncfifo_order_ft.sum2sync_pd;

   wire         mul_valid  = nvdla_cdp_syncfifo_order_ft.sync2mul_pvld;
   wire         mul_ready  = nvdla_cdp_syncfifo_order_ft.sync2mul_prdy;
   wire [71:0]  mul_pd     = nvdla_cdp_syncfifo_order_ft.sync2mul_pd;
   wire         ocvt_valid = nvdla_cdp_syncfifo_order_ft.sync2ocvt_pvld;
   wire         ocvt_ready = nvdla_cdp_syncfifo_order_ft.sync2ocvt_prdy;
   wire [14:0]  ocvt_pd    = nvdla_cdp_syncfifo_order_ft.sync2ocvt_pd;
   wire         itp_valid  = nvdla_cdp_syncfifo_order_ft.sync2itp_pvld;
   wire         itp_ready  = nvdla_cdp_syncfifo_order_ft.sync2itp_prdy;
   wire [167:0] itp_pd     = nvdla_cdp_syncfifo_order_ft.sync2itp_pd;

   wire cvt_fire  = cvt_valid  && cvt_ready;
   wire sum_fire  = sum_valid  && sum_ready;
   wire mul_fire  = mul_valid  && mul_ready;
   wire ocvt_fire = ocvt_valid && ocvt_ready;
   wire itp_fire  = itp_valid  && itp_ready;

   // ------------------------------------------------------- design windows
   // the two bubble-collapse input pipe stages
   wire p1_valid = nvdla_cdp_syncfifo_order_ft.u_dut.p1_pipe_valid;
   wire p2_valid = nvdla_cdp_syncfifo_order_ft.u_dut.p2_pipe_valid;

   // 80x72 data FIFO
   wire [6:0] d_wr_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.data_wr_count;
   wire [6:0] d_rd_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.data_rd_count_p;
   wire [6:0] d_wr_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.data_wr_adr;
   wire [6:0] d_rd_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.data_rd_adr;
   wire       d_push     = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.wr_pushing;
   wire       d_pop      = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.rd_popping;

   // 80x15 info FIFO
   wire [6:0] i_wr_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.info_wr_count;
   wire [6:0] i_rd_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.info_rd_count_p;
   wire [6:0] i_wr_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.info_wr_adr;
   wire [6:0] i_rd_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.info_rd_adr;
   wire       i_push     = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.wr_pushing;
   wire       i_pop      = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.rd_popping;

   // 60x168 sumpd FIFO
   wire [5:0] s_wr_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.sumpd_wr_count;
   wire [5:0] s_rd_count = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.sumpd_rd_count_p;
   wire [5:0] s_wr_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.sumpd_wr_adr;
   wire [5:0] s_rd_adr   = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.sumpd_rd_adr;
   wire       s_push     = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.wr_pushing;
   wire       s_pop      = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.rd_popping;
   wire       s_rd_push  = nvdla_cdp_syncfifo_order_ft.u_dut.u_sumpd_sync_fifo.rd_pushing;
   wire       d_rd_push  = nvdla_cdp_syncfifo_order_ft.u_dut.u_data_sync_fifo.rd_pushing;
   wire       i_rd_push  = nvdla_cdp_syncfifo_order_ft.u_dut.u_info_sync_fifo.rd_pushing;

   // the package checker's own ledger -- kept across the FRA cut
   wire [7:0] pkg_data_count = nvdla_cdp_syncfifo_order_ft.u_checker.data_count;
   wire [7:0] pkg_info_count = nvdla_cdp_syncfifo_order_ft.u_checker.info_count;
   wire [6:0] pkg_sum_count  = nvdla_cdp_syncfifo_order_ft.u_checker.sum_count;

   // =====================================================================
   // ORACLE 1 -- one difference counter per stream, driven only by the five
   // public handshakes.  Nothing here reads a design register.
   // =====================================================================
   reg [7:0] data_held;   // cvt beats accepted, not yet out on sync2mul
   reg [7:0] info_held;   // cvt beats accepted, not yet out on sync2ocvt
   reg [7:0] sum_held;    // sum beats accepted, not yet out on sync2itp

   // =====================================================================
   // ORACLE 2 -- XOR accumulators, one per stream and per side.
   // =====================================================================
   reg [71:0]  cvt_data_xor, mul_xor;
   reg [14:0]  cvt_info_xor, ocvt_xor;
   reg [167:0] sum_in_xor,   itp_xor;

   // =====================================================================
   // ORACLE 3 -- saturating counters, the safety form of the bounded
   // response and deadlock obligations.
   // =====================================================================
   reg [9:0] ctr_mul, ctr_ocvt, ctr_itp, ctr_stall;

   reg post_reset;
   reg mul_stall_q, ocvt_stall_q, itp_stall_q;

   wire can_mul  = mul_ready  && (data_held != 8'd0);
   wire can_ocvt = ocvt_ready && (info_held != 8'd0);
   wire can_itp  = itp_ready  && (sum_held  != 8'd0);
   wire any_out  = mul_fire || ocvt_fire || itp_fire;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         data_held    <= 8'd0;
         info_held    <= 8'd0;
         sum_held     <= 8'd0;
         cvt_data_xor <= 72'd0;
         mul_xor      <= 72'd0;
         cvt_info_xor <= 15'd0;
         ocvt_xor     <= 15'd0;
         sum_in_xor   <= 168'd0;
         itp_xor      <= 168'd0;
         ctr_mul      <= 10'd0;
         ctr_ocvt     <= 10'd0;
         ctr_itp      <= 10'd0;
         ctr_stall    <= 10'd0;
         post_reset   <= 1'b0;
         mul_stall_q  <= 1'b0;
         ocvt_stall_q <= 1'b0;
         itp_stall_q  <= 1'b0;
      end else begin
         post_reset   <= 1'b1;
         mul_stall_q  <= mul_valid  && !mul_ready;
         ocvt_stall_q <= ocvt_valid && !ocvt_ready;
         itp_stall_q  <= itp_valid  && !itp_ready;

         data_held <= data_held + (cvt_fire ? 8'd1 : 8'd0)
                                - (mul_fire ? 8'd1 : 8'd0);
         info_held <= info_held + (cvt_fire  ? 8'd1 : 8'd0)
                                - (ocvt_fire ? 8'd1 : 8'd0);
         sum_held  <= sum_held  + (sum_fire ? 8'd1 : 8'd0)
                                - (itp_fire ? 8'd1 : 8'd0);

         if (cvt_fire)  cvt_data_xor <= cvt_data_xor ^ cvt_pd[71:0];
         if (cvt_fire)  cvt_info_xor <= cvt_info_xor ^ cvt_pd[86:72];
         if (sum_fire)  sum_in_xor   <= sum_in_xor   ^ sum_pd;
         if (mul_fire)  mul_xor      <= mul_xor      ^ mul_pd;
         if (ocvt_fire) ocvt_xor     <= ocvt_xor     ^ ocvt_pd;
         if (itp_fire)  itp_xor      <= itp_xor      ^ itp_pd;

         ctr_mul   <= !(can_mul  && !mul_fire)  ? 10'd0
                    : (ctr_mul  == 10'd1023) ? ctr_mul  : ctr_mul  + 10'd1;
         ctr_ocvt  <= !(can_ocvt && !ocvt_fire) ? 10'd0
                    : (ctr_ocvt == 10'd1023) ? ctr_ocvt : ctr_ocvt + 10'd1;
         ctr_itp   <= !(can_itp  && !itp_fire)  ? 10'd0
                    : (ctr_itp  == 10'd1023) ? ctr_itp  : ctr_itp  + 10'd1;
         ctr_stall <= !((can_mul || can_ocvt || can_itp) && !any_out) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   // ------------------------------------------------- derived oracle views
   // modulo-depth pointer gaps.  This arithmetic exists nowhere in the design.
   wire [7:0] d_gap = (d_wr_adr >= d_rd_adr) ? ({1'b0, d_wr_adr} - {1'b0, d_rd_adr})
                                             : ({1'b0, d_wr_adr} + 8'd80 - {1'b0, d_rd_adr});
   wire [7:0] i_gap = (i_wr_adr >= i_rd_adr) ? ({1'b0, i_wr_adr} - {1'b0, i_rd_adr})
                                             : ({1'b0, i_wr_adr} + 8'd80 - {1'b0, i_rd_adr});
   wire [7:0] s_gap = (s_wr_adr >= s_rd_adr) ? ({2'd0, s_wr_adr} - {2'd0, s_rd_adr})
                                             : ({2'd0, s_wr_adr} + 8'd60 - {2'd0, s_rd_adr});

   // the design's own distributed occupancy, added up here
   wire [7:0] d_stages = {7'd0, p1_valid} + {1'b0, d_rd_count} + {7'd0, mul_valid};
   wire [7:0] i_stages = {7'd0, p2_valid} + {1'b0, i_rd_count} + {7'd0, ocvt_valid};
   wire [7:0] s_stages = {2'd0, s_rd_count} + {7'd0, itp_valid};

   // =====================================================================
   // 1 -- END-TO-END ORDERING
   // =====================================================================
   T_ORDER_CVT_PAIR_ENTERS_BOTH_PIPES_TOGETHER: assert property (@(posedge clk)
      disable iff (!reset_n)
      cvt_fire |=> (p1_valid && p2_valid));

   T_ORDER_INPUT_PIPES_REALIGN_WHEN_NEITHER_FIFO_IS_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((d_wr_count != 7'd80) && (i_wr_count != 7'd80)) |=> (p1_valid == p2_valid));

   T_ORDER_MUL_NEVER_OUTRUNS_THE_CVT_STREAM: assert property (@(posedge clk)
      disable iff (!reset_n)
      mul_valid |-> (data_held != 8'd0));

   T_ORDER_OCVT_NEVER_OUTRUNS_THE_CVT_STREAM: assert property (@(posedge clk)
      disable iff (!reset_n)
      ocvt_valid |-> (info_held != 8'd0));

   T_ORDER_ITP_NEVER_OUTRUNS_THE_SUM_STREAM: assert property (@(posedge clk)
      disable iff (!reset_n)
      itp_valid |-> (sum_held != 8'd0));

   // =====================================================================
   // 2 -- DATA INTEGRITY
   // =====================================================================
   T_DATA_MUL_XOR_CONSERVED_WHEN_DRAINED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (data_held == 8'd0) |-> (cvt_data_xor == mul_xor));

   T_DATA_OCVT_XOR_CONSERVED_WHEN_DRAINED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (info_held == 8'd0) |-> (cvt_info_xor == ocvt_xor));

   T_DATA_ITP_XOR_CONSERVED_WHEN_DRAINED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sum_held == 8'd0) |-> (sum_in_xor == itp_xor));

   // =====================================================================
   // 3 -- UNIQUENESS / NO DUPLICATION
   // The modulo-depth gap between a FIFO's two addresses is exactly its
   // occupancy, so no live entry is ever written over and no entry is ever
   // read twice.
   // =====================================================================
   T_UNIQ_DATA_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((d_wr_count == 7'd80) ? (d_gap == 8'd0) : (d_gap == {1'b0, d_wr_count})));

   T_UNIQ_INFO_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((i_wr_count == 7'd80) ? (i_gap == 8'd0) : (i_gap == {1'b0, i_wr_count})));

   T_UNIQ_SUM_FIFO_POINTER_GAP_IS_ITS_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((s_wr_count == 6'd60) ? (s_gap == 8'd0) : (s_gap == {2'd0, s_wr_count})));

   // =====================================================================
   // 4 -- NO LOSS / CONSERVATION
   // =====================================================================
   T_CONSERV_DATA_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (data_held == d_stages));

   T_CONSERV_INFO_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (info_held == i_stages));

   T_CONSERV_SUM_PATH_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sum_held == s_stages));

   T_CONSERV_DATA_FIFO_SIDES_AGREE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (d_wr_count == d_rd_count));

   T_CONSERV_INFO_FIFO_SIDES_AGREE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (i_wr_count == i_rd_count));

   T_CONSERV_SUM_FIFO_SIDES_AGREE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (s_wr_count == s_rd_count));

   T_CONSERV_MY_LEDGER_MATCHES_THE_PACKAGE_DATA_COUNT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (data_held == pkg_data_count));

   T_CONSERV_MY_LEDGER_MATCHES_THE_PACKAGE_INFO_COUNT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (info_held == pkg_info_count));

   T_CONSERV_MY_LEDGER_MATCHES_THE_PACKAGE_SUM_COUNT: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sum_held == {1'b0, pkg_sum_count}));

   // =====================================================================
   // 5 -- MUTUAL EXCLUSION / ONE-HOT: NOT ADMITTED.
   // Three streams that share no resource: no arbiter, no grant vector, no
   // owner field, no one-hot state anywhere in the block.  The one "never
   // one without the other" fact -- that a CVT beat enters both pipes or
   // neither -- is a pairing claim, not an exclusion claim, and is stated
   // under end-to-end ordering above.
   // =====================================================================

   // =====================================================================
   // 6 -- OCCUPANCY AND BOUNDS
   // =====================================================================
   T_BOUND_DATA_FIFO_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((d_wr_count <= 7'd80) && (d_rd_count <= 7'd80)));

   T_BOUND_INFO_FIFO_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((i_wr_count <= 7'd80) && (i_rd_count <= 7'd80)));

   T_BOUND_SUM_FIFO_OCCUPANCY: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((s_wr_count <= 6'd60) && (s_rd_count <= 6'd60)));

   T_BOUND_FIFO_POINTERS_IN_RANGE: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((d_wr_adr <= 7'd79) && (d_rd_adr <= 7'd79) &&
       (i_wr_adr <= 7'd79) && (i_rd_adr <= 7'd79) &&
       (s_wr_adr <= 6'd59) && (s_rd_adr <= 6'd59)));

   T_BOUND_DATA_PATH_HOLDING: assert property (@(posedge clk)
      disable iff (!reset_n)
      (data_held <= N_CVT_PATH));

   T_BOUND_INFO_PATH_HOLDING: assert property (@(posedge clk)
      disable iff (!reset_n)
      (info_held <= N_CVT_PATH));

   T_BOUND_SUM_PATH_HOLDING: assert property (@(posedge clk)
      disable iff (!reset_n)
      (sum_held <= N_SUM_PATH));

   // =====================================================================
   // 7 -- ALLOCATOR DISCIPLINE
   // =====================================================================
   T_ALLOC_DATA_FIFO_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      d_push |-> (d_wr_count != 7'd80));

   T_ALLOC_INFO_FIFO_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      i_push |-> (i_wr_count != 7'd80));

   T_ALLOC_SUM_FIFO_NO_PUSH_WHEN_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      s_push |-> (s_wr_count != 6'd60));

   T_ALLOC_NO_POP_FROM_AN_EMPTY_FIFO: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((!d_pop || (d_rd_count != 7'd0) || d_rd_push) &&
       (!i_pop || (i_rd_count != 7'd0) || i_rd_push) &&
       (!s_pop || (s_rd_count != 6'd0) || s_rd_push)));

   // =====================================================================
   // 8 -- REQUEST / RESPONSE CORRESPONDENCE: NOT ADMITTED.
   // Nothing in this block carries a request identifier or matches a reply
   // to it: all three streams are unidentified FIFO traffic.  The half of
   // the shape that does apply -- no unsolicited output -- is stated under
   // end-to-end ordering as the three "never outruns" claims.
   // =====================================================================

   // =====================================================================
   // 9 -- PROTOCOL CONFORMANCE (on the DUT's own outputs; the inputs are
   // free by construction and carry no obligation)
   // =====================================================================
   T_PROTO_MUL_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (mul_valid && !mul_ready) |=> mul_valid);

   T_PROTO_MUL_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      mul_stall_q |-> $stable(mul_pd));

   T_PROTO_OCVT_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ocvt_valid && !ocvt_ready) |=> ocvt_valid);

   T_PROTO_OCVT_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      ocvt_stall_q |-> $stable(ocvt_pd));

   T_PROTO_ITP_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (itp_valid && !itp_ready) |=> itp_valid);

   T_PROTO_ITP_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      itp_stall_q |-> $stable(itp_pd));

   // =====================================================================
   // 10 -- ARBITRATION FAIRNESS: NOT ADMITTED.
   // No arbiter and no contended resource.  The three streams have separate
   // RAMs, separate pointers and separate output ports; nothing is ever
   // bypassed in favour of anything else.
   // =====================================================================

   // =====================================================================
   // 11 -- BOUNDED RESPONSE (bounded-safety form)
   // =====================================================================
   T_BOUNDRSP_MUL_DELIVERS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_mul <= N_DELIVER));

   T_BOUNDRSP_OCVT_DELIVERS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_ocvt <= N_DELIVER));

   T_BOUNDRSP_ITP_DELIVERS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_itp <= N_DELIVER));

   // =====================================================================
   // 12 -- DEADLOCK FREEDOM (bounded-safety form)
   // =====================================================================
   T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_stall <= N_STALL));

   T_DEADLOCK_CVT_INPUT_STALLS_ONLY_ON_A_FULL_FIFO: assert property (@(posedge clk)
      disable iff (!reset_n)
      !cvt_ready |-> ((d_wr_count == 7'd80) || (i_wr_count == 7'd80)));

   T_DEADLOCK_SUM_INPUT_STALLS_ONLY_ON_A_FULL_FIFO: assert property (@(posedge clk)
      disable iff (!reset_n)
      !sum_ready |-> (s_wr_count == 6'd60));

   // =====================================================================
   // 13 -- RESET / INITIALISATION
   // =====================================================================
   T_RESET_FIFOS_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((d_wr_count == 7'd0) && (d_rd_count == 7'd0) &&
                       (i_wr_count == 7'd0) && (i_rd_count == 7'd0) &&
                       (s_wr_count == 6'd0) && (s_rd_count == 6'd0)));

   T_RESET_POINTERS_ZERO: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((d_wr_adr == 7'd0) && (d_rd_adr == 7'd0) &&
                       (i_wr_adr == 7'd0) && (i_rd_adr == 7'd0) &&
                       (s_wr_adr == 6'd0) && (s_rd_adr == 6'd0)));

   T_RESET_NO_OUTPUT_OFFERED_AND_PIPES_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (!mul_valid && !ocvt_valid && !itp_valid &&
                       !p1_valid && !p2_valid));

   // =====================================================================
   // 14 -- LIFECYCLE / ACCESS CONTROL: NOT ADMITTED.
   // The block has no configuration input, no mode register and no state
   // that grants or withholds anything; every port is unconditional stream
   // traffic.
   //
   // 15 -- COHERENCE: NOT ADMITTED.  One writer and one reader per stream,
   // no shared permission state.
   // =====================================================================

   // =====================================================================
   // COVERS -- at least one per category used.
   // =====================================================================
   C_ORDER_CVT_BEAT_ACCEPTED: cover property (@(posedge clk)
      disable iff (!reset_n) cvt_fire);
   C_ORDER_BOTH_PIPES_LOADED: cover property (@(posedge clk)
      disable iff (!reset_n) (p1_valid && p2_valid));
   C_ORDER_HALVES_SKEWED: cover property (@(posedge clk)
      disable iff (!reset_n) ((data_held >= 8'd8) && (info_held == 8'd0)));

   C_DATA_MUL_DELIVERED: cover property (@(posedge clk)
      disable iff (!reset_n) mul_fire);
   C_DATA_XOR_CHECKED_AFTER_TRAFFIC: cover property (@(posedge clk)
      disable iff (!reset_n) ((data_held == 8'd0) && (mul_xor != 72'd0)));
   C_DATA_ITP_DELIVERED: cover property (@(posedge clk)
      disable iff (!reset_n) itp_fire);

   C_UNIQ_DATA_FIFO_WRAPS: cover property (@(posedge clk)
      disable iff (!reset_n) ((d_wr_adr < d_rd_adr) && (d_wr_count != 7'd0)));
   C_UNIQ_SUM_FIFO_WRAPS: cover property (@(posedge clk)
      disable iff (!reset_n) ((s_wr_adr < s_rd_adr) && (s_wr_count != 6'd0)));

   C_CONSERV_ALL_THREE_PATHS_LOADED: cover property (@(posedge clk)
      disable iff (!reset_n) ((data_held != 8'd0) && (info_held != 8'd0) &&
                              (sum_held != 8'd0)));
   C_CONSERV_PIPE_AND_FIFO_BOTH_HOLD: cover property (@(posedge clk)
      disable iff (!reset_n) (p1_valid && (d_rd_count != 7'd0) && mul_valid));

   C_BOUND_DATA_FIFO_HALF_FULL: cover property (@(posedge clk)
      disable iff (!reset_n) (d_wr_count >= 7'd40));
   C_BOUND_SUM_FIFO_HALF_FULL: cover property (@(posedge clk)
      disable iff (!reset_n) (s_wr_count >= 6'd30));
   C_BOUND_DATA_FIFO_FULL: cover property (@(posedge clk)
      disable iff (!reset_n) (d_wr_count == 7'd80));

   C_ALLOC_PUSH_AND_POP_TOGETHER: cover property (@(posedge clk)
      disable iff (!reset_n) (d_push && d_pop));
   C_ALLOC_SUM_PUSH_AND_POP_TOGETHER: cover property (@(posedge clk)
      disable iff (!reset_n) (s_push && s_pop));

   C_PROTO_MUL_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (mul_valid && !mul_ready));
   C_PROTO_ALL_THREE_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (mul_stall_q && ocvt_stall_q && itp_stall_q));

   C_BOUNDRSP_MUL_WAIT_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_mul >= 10'd2));
   C_BOUNDRSP_ITP_WAIT_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_itp >= 10'd2));

   C_DEADLOCK_STALL_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_stall >= 10'd2));
   C_DEADLOCK_CVT_INPUT_STALLED: cover property (@(posedge clk)
      disable iff (!reset_n) (cvt_valid && !cvt_ready));

   C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
      disable iff (!reset_n) !post_reset);

endmodule

bind nvdla_cdp_syncfifo_order_ft nvdla_cdp_targets u_targets (
   .clk(nvdla_core_clk), .reset_n(nvdla_core_rstn));
