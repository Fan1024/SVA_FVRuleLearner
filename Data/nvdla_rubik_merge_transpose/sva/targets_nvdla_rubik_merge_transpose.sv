// ===========================================================================
// Candidate target assertions for the real NVDLA RUBIK register-file core in
// MERGE mode at INT8 precision.
//
// Bound into the formal top, so every reference below is a hierarchical name
// from `nvdla_rubik_merge_transpose_ft`.  NOTHING HERE IS AN ASSUMPTION --
// the one the task already carries (A_READY_RESERVATION) lives in
// sva/nvdla_rubik_merge_transpose_checker.sv and this file adds none.
//
// WHAT THE BLOCK DOES.  The formal top runs a four-phase batch:
//
//   PH_WARMUP (3 cycles)  -> PH_WRITE: 32 rows, one per accepted rf_wr beat,
//   row index 0..31, the last one carrying rf_wr_done
//                         -> PH_READ: 32 columns, one per accepted rf_rd beat,
//   column index 0..31, the last one carrying rf_rd_done
//                         -> PH_DRAIN: wait for the last output beat.
//
// Inside the core, a beat crosses a two-entry skid pipe (p1 for writes, p2
// for reads), then the 64 32x16 RAMs organised as two ping-pong banks
// selected by rf_wptr[0] / rf_rptr[0].  A bank is claimed by rf_wr_odone and
// released by rf_rd_odone, so `rf_full` is a two-bank allocator, not a FIFO.
// MERGE + INT8 makes the write transform `shift512_16b`, a rotation of the
// 512-bit word by whole 16-bit lanes, and makes the read address vector a
// rotation of the identity sequence 0..31.
//
// THE ORACLES ARE THIS FILE'S OWN, and none of them is the checker's
// transpose.
//
//   * ROTATION-INVARIANT FOLDS.  The XOR of the thirty-two 16-bit lanes of a
//     512-bit word does not change when the word is rotated by whole lanes,
//     so it is preserved by the write transform whatever the shift.  The
//     design computes no such quantity.
//   * A PER-COLUMN BYTE FOLD.  The output word for column c is the 32 low
//     bytes and the 32 high bytes of element c of the 32 rows, so the XOR of
//     its 64 bytes equals the XOR over rows of (low byte ^ high byte) of
//     element c.  That is accumulated here at WRITE time, one 8-bit value per
//     column, and checked at OUTPUT time.  It is a necessary condition of the
//     full transpose and is computed a completely different way.
//   * A FIVE-BIT FOLD over the 160-bit RAM read-address vector.  A permutation
//     of 0..31 XOR-folds to zero.
//   * DIFFERENCE COUNTERS on the four public handshakes and on the two
//     bank-ownership events.
//   * SATURATING COUNTERS, the safety form of the bounded-response and
//     deadlock obligations.  No `s_eventually` and no unbounded liveness.
//
// RESET.  This module's registers are reset-initialised.  Under
// `ENTER_FRA_KEEP` only registers matched by the task's `design_keep` are
// given their reset value -- here that is the checker's four and the formal
// top's five sequencer registers, and nothing in the DUT.  So a screen of the
// oracle-backed claims below must be run with
//
//     --keep-extra 'u_targets\.'
//
// or those claims are falsified at cycle 0 for a reason that is not the
// design's.  `taskdef.json` is deliberately NOT edited: adding to
// `design_keep` would change the abstraction the existing target
// T_RUBIK_MERGE_TRANSPOSE is measured under.
// ===========================================================================

module nvdla_rubik_targets (input wire clk, input wire reset_n);

   localparam [9:0] N_OUT_WAIT  = 10'd8;
   localparam [9:0] N_POP_WAIT  = 10'd16;
   localparam [9:0] N_STALL     = 10'd32;

   // ------------------------------------------------------------- boundary
   wire         wr_vld     = nvdla_rubik_merge_transpose_ft.rf_wr_vld;
   wire         wr_rdy     = nvdla_rubik_merge_transpose_ft.rf_wr_rdy;
   wire         write_fire = nvdla_rubik_merge_transpose_ft.write_fire;
   wire [4:0]   write_index= nvdla_rubik_merge_transpose_ft.write_index_q;
   wire [511:0] write_data = nvdla_rubik_merge_transpose_ft.write_data_q;

   wire         rd_vld     = nvdla_rubik_merge_transpose_ft.rf_rd_vld;
   wire         rd_rdy     = nvdla_rubik_merge_transpose_ft.rf_rd_rdy;
   wire         read_fire  = nvdla_rubik_merge_transpose_ft.read_fire;
   wire [4:0]   read_index = nvdla_rubik_merge_transpose_ft.read_index_q;

   wire         out_valid  = nvdla_rubik_merge_transpose_ft.dma_wr_data_vld;
   wire         out_ready  = nvdla_rubik_merge_transpose_ft.dma_wr_data_rdy;
   wire [513:0] out_pd     = nvdla_rubik_merge_transpose_ft.dma_wr_data_pd;
   wire         out_fire   = out_valid && out_ready;

   // ------------------------------------------------------- design windows
   wire       p1_skid = nvdla_rubik_merge_transpose_ft.dut.pipe_p1.p1_skid_valid;
   wire       p1_pipe = nvdla_rubik_merge_transpose_ft.dut.pipe_p1.p1_pipe_valid;
   wire       p2_skid = nvdla_rubik_merge_transpose_ft.dut.pipe_p2.p2_skid_valid;
   wire       p2_pipe = nvdla_rubik_merge_transpose_ft.dut.pipe_p2.p2_pipe_valid;

   wire [1:0]   wptr      = nvdla_rubik_merge_transpose_ft.dut.rf_wptr;
   wire [1:0]   rptr      = nvdla_rubik_merge_transpose_ft.dut.rf_rptr;
   wire         rf_full   = nvdla_rubik_merge_transpose_ft.dut.rf_full;
   wire         rf_empty  = nvdla_rubik_merge_transpose_ft.dut.rf_empty;

   wire         wr_pop    = nvdla_rubik_merge_transpose_ft.dut.rf_wr_pop;
   wire         wr_odone  = nvdla_rubik_merge_transpose_ft.dut.rf_wr_odone;
   wire [4:0]   wr_oaddr  = nvdla_rubik_merge_transpose_ft.dut.rf_wr_oaddr;
   wire [511:0] wr_odata  = nvdla_rubik_merge_transpose_ft.dut.rf_wr_odata;
   wire         wr_osel   = nvdla_rubik_merge_transpose_ft.dut.rf_wr_osel;

   wire         rd_pop    = nvdla_rubik_merge_transpose_ft.dut.rf_rd_pop;
   wire         rd_odone  = nvdla_rubik_merge_transpose_ft.dut.rf_rd_odone;
   wire [4:0]   rd_oaddr  = nvdla_rubik_merge_transpose_ft.dut.rf_rd_oaddr;
   wire [4:0]   rd_oaddr_d= nvdla_rubik_merge_transpose_ft.dut.rf_rd_oaddr_d;
   wire         rd_osel   = nvdla_rubik_merge_transpose_ft.dut.rf_rd_osel;
   wire [159:0] ram_rd_ov = nvdla_rubik_merge_transpose_ft.dut.ram_rd_oaddr;

   wire         m_contract = nvdla_rubik_merge_transpose_ft.dut.m_contract;
   wire         m_split    = nvdla_rubik_merge_transpose_ft.dut.m_split;
   wire         m_byte     = nvdla_rubik_merge_transpose_ft.dut.m_byte_data;

   // the package checker's own state -- kept across the FRA cut
   wire       pkg_pending = nvdla_rubik_merge_transpose_ft.u_checker.pending_q;
   wire [4:0] pkg_index   = nvdla_rubik_merge_transpose_ft.u_checker.expected_index_q;

   // ------------------------------------------------------- fold functions
   // Every one of these is arithmetic this file does and the design does not.
   function automatic [15:0] fold16_512(input [511:0] x);
      integer k;
      begin
         fold16_512 = 16'd0;
         for (k = 0; k < 32; k = k + 1)
            fold16_512 = fold16_512 ^ x[16*k +: 16];
      end
   endfunction

   function automatic [7:0] fold8_512(input [511:0] x);
      integer k;
      begin
         fold8_512 = 8'd0;
         for (k = 0; k < 64; k = k + 1)
            fold8_512 = fold8_512 ^ x[8*k +: 8];
      end
   endfunction

   function automatic [4:0] fold5_160(input [159:0] x);
      integer k;
      begin
         fold5_160 = 5'd0;
         for (k = 0; k < 32; k = k + 1)
            fold5_160 = fold5_160 ^ x[5*k +: 5];
      end
   endfunction

   // =====================================================================
   // ORACLE 1 -- difference counters on the public handshakes and on the
   // two bank-ownership events.
   // =====================================================================
   reg [2:0] wr_inflight;   // write beats accepted, not yet popped into a RAM
   reg [2:0] rd_inflight;   // read beats accepted, not yet popped into a RAM
   reg [1:0] banks_ready;   // banks claimed by a write, not yet released
   reg [4:0] wr_rows;       // rows popped into the current bank
   reg [4:0] rd_cols;       // columns popped out of the current bank
   reg [1:0] out_owed;      // RAM pops not yet delivered on dma_wr_data
   reg [4:0] out_col;       // the column index of the beat now owed

   // =====================================================================
   // ORACLE 2 -- rotation-invariant lane folds across the write pipe, and
   // one byte fold per column accumulated while the batch is written.
   // =====================================================================
   reg [15:0] wr_in_fold;
   reg [15:0] wr_out_fold;
   reg [7:0]  col_fold [0:31];
   reg        fold_ready;   // the 32 rows of this batch have all been popped in

   // =====================================================================
   // ORACLE 3 -- saturating counters.
   // =====================================================================
   reg [9:0] ctr_out, ctr_rdpop, ctr_wrpop, ctr_stall;

   reg post_reset;
   reg out_stall_q;

   wire can_out   = (out_owed != 2'd0) && out_ready;
   wire can_rdpop = rd_vld && (banks_ready != 2'd0) && out_ready;
   wire can_wrpop = wr_vld && (banks_ready != 2'd2);
   wire any_move  = write_fire || read_fire || wr_pop || rd_pop || out_fire;

   integer c;
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         wr_inflight <= 3'd0;
         rd_inflight <= 3'd0;
         banks_ready <= 2'd0;
         wr_rows     <= 5'd0;
         rd_cols     <= 5'd0;
         out_owed    <= 2'd0;
         out_col     <= 5'd0;
         wr_in_fold  <= 16'd0;
         wr_out_fold <= 16'd0;
         fold_ready  <= 1'b0;
         ctr_out     <= 10'd0;
         ctr_rdpop   <= 10'd0;
         ctr_wrpop   <= 10'd0;
         ctr_stall   <= 10'd0;
         post_reset  <= 1'b0;
         out_stall_q <= 1'b0;
         for (c = 0; c < 32; c = c + 1) col_fold[c] <= 8'd0;
      end else begin
         post_reset  <= 1'b1;
         out_stall_q <= out_valid && !out_ready;

         wr_inflight <= wr_inflight + (write_fire ? 3'd1 : 3'd0)
                                    - (wr_pop     ? 3'd1 : 3'd0);
         rd_inflight <= rd_inflight + (read_fire ? 3'd1 : 3'd0)
                                    - (rd_pop    ? 3'd1 : 3'd0);
         banks_ready <= banks_ready + (wr_odone ? 2'd1 : 2'd0)
                                    - (rd_odone ? 2'd1 : 2'd0);

         if (wr_pop) wr_rows <= wr_odone ? 5'd0 : (wr_rows + 5'd1);
         if (rd_pop) rd_cols <= rd_odone ? 5'd0 : (rd_cols + 5'd1);

         out_owed <= out_owed + (rd_pop   ? 2'd1 : 2'd0)
                              - (out_fire ? 2'd1 : 2'd0);
         if (rd_pop) out_col <= rd_cols;

         if (write_fire) wr_in_fold  <= wr_in_fold  ^ fold16_512(write_data);
         if (wr_pop)     wr_out_fold <= wr_out_fold ^ fold16_512(wr_odata);

         if (write_fire) begin
            for (c = 0; c < 32; c = c + 1)
               col_fold[c] <= ((write_index == 5'd0) ? 8'd0 : col_fold[c])
                              ^ write_data[16*c +: 8] ^ write_data[16*c + 8 +: 8];
         end
         if (write_fire && (write_index == 5'd0))       fold_ready <= 1'b0;
         else if (write_fire && (write_index == 5'd31)) fold_ready <= 1'b1;

         ctr_out   <= !(can_out && !out_fire) ? 10'd0
                    : (ctr_out == 10'd1023) ? ctr_out : ctr_out + 10'd1;
         ctr_rdpop <= !(can_rdpop && !rd_pop) ? 10'd0
                    : (ctr_rdpop == 10'd1023) ? ctr_rdpop : ctr_rdpop + 10'd1;
         ctr_wrpop <= !(can_wrpop && !wr_pop) ? 10'd0
                    : (ctr_wrpop == 10'd1023) ? ctr_wrpop : ctr_wrpop + 10'd1;
         ctr_stall <= !((can_out || can_rdpop || can_wrpop) && !any_move) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   wire [1:0] bank_gap = wptr - rptr;

   // =====================================================================
   // 1 -- END-TO-END ORDERING
   // =====================================================================
   T_ORDER_ROWS_ENTER_THE_RAM_IN_INDEX_ORDER: assert property (@(posedge clk)
      disable iff (!reset_n)
      wr_pop |-> (wr_oaddr == wr_rows));

   T_ORDER_COLUMNS_LEAVE_THE_RAM_IN_INDEX_ORDER: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |-> (rd_oaddr == rd_cols));

   T_ORDER_THE_LAST_ROW_OF_A_BANK_CARRIES_ITS_DONE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wr_pop && (wr_rows == 5'd31)) |-> wr_odone);

   T_ORDER_THE_LAST_COLUMN_OF_A_BANK_CARRIES_ITS_DONE: assert property (@(posedge clk)
      disable iff (!reset_n)
      (rd_pop && (rd_cols == 5'd31)) |-> rd_odone);

   // =====================================================================
   // 2 -- DATA INTEGRITY
   // =====================================================================
   T_DATA_OUTPUT_BYTE_FOLD_MATCHES_ITS_COLUMN: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_valid && (out_owed != 2'd0) && fold_ready)
         |-> (fold8_512(out_pd[511:0]) == col_fold[out_col]));

   T_DATA_WRITE_LANE_FOLD_CONSERVED_WHEN_THE_PIPE_IS_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wr_inflight == 3'd0) |-> (wr_in_fold == wr_out_fold));

   T_DATA_RAM_READ_ADDRESSES_FOLD_TO_ZERO: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |-> (fold5_160(ram_rd_ov) == 5'd0));

   T_DATA_OUTPUT_MASK_IS_FULL: assert property (@(posedge clk)
      disable iff (!reset_n)
      out_valid |-> (out_pd[513:512] == 2'b11));

   // =====================================================================
   // 3 -- UNIQUENESS / NO DUPLICATION
   // =====================================================================
   T_UNIQ_AT_MOST_ONE_OUTPUT_BEAT_IS_OWED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_owed <= 2'd1));

   T_UNIQ_NO_OUTPUT_WITHOUT_A_RAM_POP: assert property (@(posedge clk)
      disable iff (!reset_n)
      out_valid |-> (out_owed != 2'd0));

   T_UNIQ_BANKS_NEVER_WRITTEN_AND_READ_TOGETHER: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wr_pop && rd_pop) |-> (wr_osel != rd_osel));

   // =====================================================================
   // 4 -- NO LOSS / CONSERVATION
   // =====================================================================
   T_CONSERV_WRITE_PIPE_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wr_inflight == ({2'd0, p1_skid} + {2'd0, p1_pipe})));

   T_CONSERV_READ_PIPE_OCCUPANCY_ACCOUNTED: assert property (@(posedge clk)
      disable iff (!reset_n)
      (rd_inflight == ({2'd0, p2_skid} + {2'd0, p2_pipe})));

   T_CONSERV_BANK_POINTER_GAP_IS_THE_OWNERSHIP_LEDGER: assert property (@(posedge clk)
      disable iff (!reset_n)
      (bank_gap == banks_ready));

   T_CONSERV_MY_PENDING_MATCHES_THE_PACKAGE_PENDING: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_owed == {1'b0, pkg_pending}));

   T_CONSERV_MY_COLUMN_MATCHES_THE_PACKAGE_COLUMN: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_owed != 2'd0) |-> (out_col == pkg_index));

   // =====================================================================
   // 5 -- MUTUAL EXCLUSION / ONE-HOT
   // =====================================================================
   T_MUTEX_NEVER_WRITING_AND_READING_AT_ONCE: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(wr_vld && rd_vld));

   T_MUTEX_ONE_OWNER_OF_THE_OUTPUT_REGISTER: assert property (@(posedge clk)
      disable iff (!reset_n)
      !(rd_pop && out_valid && !out_ready));

   // =====================================================================
   // 6 -- OCCUPANCY AND BOUNDS
   // =====================================================================
   T_BOUND_BANK_OWNERSHIP_AT_MOST_TWO: assert property (@(posedge clk)
      disable iff (!reset_n)
      (banks_ready <= 2'd2));

   T_BOUND_WRITE_PIPE_AT_MOST_TWO: assert property (@(posedge clk)
      disable iff (!reset_n)
      (wr_inflight <= 3'd2));

   T_BOUND_READ_PIPE_AT_MOST_TWO: assert property (@(posedge clk)
      disable iff (!reset_n)
      (rd_inflight <= 3'd2));

   T_BOUND_ROW_AND_COLUMN_INDEX_IN_RANGE: assert property (@(posedge clk)
      disable iff (!reset_n)
      ((wr_rows <= 5'd31) && (rd_cols <= 5'd31)));

   // =====================================================================
   // 7 -- ALLOCATOR DISCIPLINE (the two-bank ping-pong)
   // =====================================================================
   T_ALLOC_BANK_CLAIMED_ONLY_AFTER_THIRTY_TWO_ROWS: assert property (@(posedge clk)
      disable iff (!reset_n)
      wr_odone |-> (wr_rows == 5'd31));

   T_ALLOC_BANK_RELEASED_ONLY_AFTER_THIRTY_TWO_COLUMNS: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_odone |-> (rd_cols == 5'd31));

   T_ALLOC_NO_ROW_WRITTEN_WHEN_BOTH_BANKS_ARE_OWNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      wr_pop |-> (banks_ready != 2'd2));

   T_ALLOC_NO_COLUMN_READ_WHEN_NO_BANK_IS_OWNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |-> (banks_ready != 2'd0));

   // =====================================================================
   // 8 -- REQUEST / RESPONSE CORRESPONDENCE
   // =====================================================================
   T_REQRSP_EVERY_RAM_POP_IS_ANSWERED_NEXT_CYCLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |=> out_valid);

   T_REQRSP_OUTPUT_CARRIES_THE_POPPED_COLUMN: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_valid && (out_owed != 2'd0)) |-> (rd_oaddr_d == out_col));

   // =====================================================================
   // 9 -- PROTOCOL CONFORMANCE
   // =====================================================================
   T_PROTO_OUTPUT_VALID_HELD: assert property (@(posedge clk)
      disable iff (!reset_n)
      (out_valid && !out_ready) |=> out_valid);

   T_PROTO_OUTPUT_PAYLOAD_STABLE: assert property (@(posedge clk)
      disable iff (!reset_n)
      out_stall_q |-> $stable(out_pd));

   T_PROTO_RAM_POP_ONLY_WITH_A_READY_CONSUMER: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |-> out_ready);

   // =====================================================================
   // 10 -- ARBITRATION FAIRNESS: NOT ADMITTED.
   // One writer, one reader, one output port and no contended resource:
   // there is nothing to arbitrate and no requester that can be bypassed.
   // The bank ping-pong is an allocator, not an arbiter, and is covered
   // under allocator discipline above.
   // =====================================================================

   // =====================================================================
   // 11 -- BOUNDED RESPONSE (bounded-safety form)
   // =====================================================================
   T_BOUNDRSP_OUTPUT_DELIVERS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_out <= N_OUT_WAIT));

   T_BOUNDRSP_READ_POPS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_rdpop <= N_POP_WAIT));

   T_BOUNDRSP_WRITE_POPS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_wrpop <= N_POP_WAIT));

   // =====================================================================
   // 12 -- DEADLOCK FREEDOM (bounded-safety form)
   // =====================================================================
   T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (@(posedge clk)
      disable iff (!reset_n)
      (ctr_stall <= N_STALL));

   // =====================================================================
   // 13 -- RESET / INITIALISATION
   // =====================================================================
   T_RESET_REGISTER_FILE_UNOWNED: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> ((wptr == 2'd0) && (rptr == 2'd0) && rf_empty &&
                       !rf_full && !out_valid));

   T_RESET_PIPES_EMPTY: assert property (@(posedge clk)
      disable iff (!reset_n)
      !post_reset |-> (!p1_skid && !p1_pipe && !p2_skid && !p2_pipe));

   // =====================================================================
   // 14 -- LIFECYCLE / ACCESS CONTROL
   // =====================================================================
   T_LIFECYCLE_MODE_STAYS_MERGE_INT8: assert property (@(posedge clk)
      disable iff (!reset_n)
      post_reset |-> (!m_contract && !m_split && m_byte));

   T_LIFECYCLE_NO_COLUMN_LEAVES_BEFORE_ITS_BANK_IS_COMPLETE: assert property (@(posedge clk)
      disable iff (!reset_n)
      rd_pop |-> (wr_rows == 5'd0));

   // =====================================================================
   // 15 -- COHERENCE: NOT ADMITTED.  One producer, one consumer, no shared
   // permission state and no second agent to conflict with.
   // =====================================================================

   // =====================================================================
   // COVERS -- at least one per category used.
   // =====================================================================
   C_ORDER_LAST_ROW_POPPED: cover property (@(posedge clk)
      disable iff (!reset_n) (wr_pop && (wr_rows == 5'd31)));
   C_ORDER_LAST_COLUMN_POPPED: cover property (@(posedge clk)
      disable iff (!reset_n) (rd_pop && (rd_cols == 5'd31)));

   C_DATA_OUTPUT_CHECKED_AGAINST_ITS_FOLD: cover property (@(posedge clk)
      disable iff (!reset_n) (out_valid && (out_owed != 2'd0) && fold_ready));
   C_DATA_WRITE_FOLD_NONZERO_AND_DRAINED: cover property (@(posedge clk)
      disable iff (!reset_n) ((wr_inflight == 3'd0) && (wr_in_fold != 16'd0)));
   C_DATA_OUTPUT_DELIVERED: cover property (@(posedge clk)
      disable iff (!reset_n) out_fire);

   C_UNIQ_OUTPUT_OWED: cover property (@(posedge clk)
      disable iff (!reset_n) (out_owed == 2'd1));

   C_CONSERV_BOTH_PIPES_FULL: cover property (@(posedge clk)
      disable iff (!reset_n) ((wr_inflight == 3'd2) || (rd_inflight == 3'd2)));
   C_CONSERV_ONE_BANK_OWNED: cover property (@(posedge clk)
      disable iff (!reset_n) (banks_ready == 2'd1));

   C_MUTEX_READ_PHASE_ACTIVE: cover property (@(posedge clk)
      disable iff (!reset_n) rd_vld);
   C_MUTEX_WRITE_PHASE_ACTIVE: cover property (@(posedge clk)
      disable iff (!reset_n) wr_vld);

   C_BOUND_BOTH_BANKS_OWNED: cover property (@(posedge clk)
      disable iff (!reset_n) (banks_ready == 2'd2));
   C_BOUND_HALF_A_BATCH_WRITTEN: cover property (@(posedge clk)
      disable iff (!reset_n) (wr_rows >= 5'd16));

   C_ALLOC_BANK_CLAIMED: cover property (@(posedge clk)
      disable iff (!reset_n) wr_odone);
   C_ALLOC_BANK_RELEASED: cover property (@(posedge clk)
      disable iff (!reset_n) rd_odone);

   C_REQRSP_POP_THEN_OUTPUT: cover property (@(posedge clk)
      disable iff (!reset_n) (rd_pop ##1 out_fire));

   C_PROTO_OUTPUT_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (out_valid && !out_ready));
   C_PROTO_WRITE_BACKPRESSURED: cover property (@(posedge clk)
      disable iff (!reset_n) (wr_vld && !wr_rdy));

   C_BOUNDRSP_READ_POP_WAIT_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_rdpop >= 10'd2));
   C_BOUNDRSP_WRITE_POP_WAIT_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_wrpop >= 10'd2));

   C_DEADLOCK_STALL_TWO: cover property (@(posedge clk)
      disable iff (!reset_n) (ctr_stall >= 10'd2));

   C_RESET_FIRST_CYCLE: cover property (@(posedge clk)
      disable iff (!reset_n) !post_reset);

   C_LIFECYCLE_SECOND_BATCH_READ: cover property (@(posedge clk)
      disable iff (!reset_n) (rd_odone && (wptr != 2'd1)));

endmodule

bind nvdla_rubik_merge_transpose_ft nvdla_rubik_targets u_targets (
   .clk(nvdla_core_clk), .reset_n(nvdla_core_rstn));
