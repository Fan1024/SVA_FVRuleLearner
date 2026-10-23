//
// Phase-1 candidate TARGET assertions for tasks/cva6_frontend_issue_commit.
//
// The subsystem is five CVA6 pipeline stages with real buffering between each
// pair.  An instruction crosses four buffers between the two ends:
//
//   frontend            the INSTRUCTION QUEUE: four 4-deep instruction fifos
//     |                 plus a 2-deep branch-address fifo
//     v   IF/ID handover   fetch_valid_if_id / fetch_ready_id_if
//   id_stage            one registered issue slot per issue port
//     |
//     v   ID/ISSUE handover  issue_entry_valid_id_issue / issue_instr_issue_id
//   issue_stage         the SCOREBOARD: 8 entries, allocated in order at
//     |                 issue_pointer_q, retired in order at commit_pointer_q,
//     |                 COMPLETED OUT OF ORDER by five writeback ports
//     v   FU issue           fu_data_id_ex, *_valid_id_ex
//   ex_stage            2 ALUs, branch unit, CSR buffer, mult/div, and the
//     |                 LSU with its 2-entry LOAD BUFFER and its 4+4-entry
//     |                 STORE BUFFER
//     v   writeback          trans_id_ex_id / wt_valid_ex_id / wbdata_ex_id
//   commit_stage        in-order retirement on 2 ports, and the GPR file
//
// The observation points every assertion below is stated on are the four
// handshakes named above.  Nothing stated between them is a local fact about
// any one block: an inductive invariant for, say,
// T_CONSERV_SB_OCCUPANCY_MATCHES_LEDGER has to span the instruction queue,
// the ID slots, the scoreboard's two pointers, the five writeback ports, the
// speculative-cancel path and the flush controller -- none of which the
// target mentions.
//
// THE ORACLE.  `sb_*` below is an independent ledger of the instructions in
// flight, and the design has no equivalent of it.  It is driven from the
// ID/ISSUE handshake, the commit acknowledge and the flush line ONLY; it
// keeps its own pointers, its own live set, its own occupancy counter and its
// own copy of the decoded pc/rd/fu.  It never reads the scoreboard's memory,
// its pointers or its full flags -- those are what the targets compare it
// against.
//
// Two of the targets are stated about ONE SYMBOLIC scoreboard entry
// (`sym_id_q`) and one symbolic architectural register (`sym_rd_q`).  Those
// are registers whose only driver is themselves: under any reset scheme they
// hold their arbitrary initial value for the whole trace, which is a symbolic
// constant obtained WITHOUT writing an assumption.  This file declares no
// assumption and neither does the diag.
//
// Every counter bound is stated as an inequality that can be argued from the
// RTL and from the two memory models' MAX_WAIT = 8, and the argument is in
// the comment above the target.
//
module cva6_pipe_targets
  import ariane_pkg::*;
  import cva6_pipe_fv_pkg::*;
(
    input logic clk_i,
    input logic rst_ni
);

  `define FT  cva6_frontend_issue_commit_ft
  `define SB  `FT.issue_stage_i.i_scoreboard
  `define IRO `FT.issue_stage_i.i_issue_read_operands
  `define RF  `IRO.gen_asic_regfile.i_ariane_regfile
  `define IQ  `FT.i_frontend.i_instr_queue
  `define LDU `FT.ex_stage_i.lsu_i.i_load_unit
  `define STB `FT.ex_stage_i.lsu_i.i_store_unit.store_buffer_i

  localparam int NSB   = cva6_pipe_fv_pkg::Cfg.NR_SB_ENTRIES;      // 8
  localparam int TIDW  = cva6_pipe_fv_pkg::Cfg.TRANS_ID_BITS;      // 3
  localparam int NISS  = cva6_pipe_fv_pkg::Cfg.NrIssuePorts;       // 2
  localparam int NCOM  = cva6_pipe_fv_pkg::Cfg.NrCommitPorts;      // 2
  localparam int NWB   = cva6_pipe_fv_pkg::Cfg.NrWbPorts;          // 5
  localparam int XLEN  = cva6_pipe_fv_pkg::Cfg.XLEN;               // 32
  localparam int VLEN  = cva6_pipe_fv_pkg::Cfg.VLEN;               // 32
  localparam int NLD   = cva6_pipe_fv_pkg::Cfg.NrLoadBufEntries;   // 2

  // The two memory models refuse for at most 8 consecutive cycles and answer
  // a pending request within 8, so every bound below is derived from 8.
  localparam int MEM_WAIT      = 8;
  localparam int FETCH_BOUND   = 32;
  localparam int LOAD_BOUND    = 32;
  localparam int STORE_BOUND   = 32;
  localparam int RETIRE_BOUND  = 256;
  localparam int PROGRESS_BOUND = 128;

  // ======================================================================
  // the handshakes -- the only design signals the oracle is driven from
  // ======================================================================
  logic [NISS-1:0] alloc;          // an instruction enters the scoreboard
  logic [NCOM-1:0] retire;         // an instruction leaves it
  logic            flush;          // the scoreboard is cleared
  logic            flush_if;       // the ID stage is cleared
  logic [1:0]      n_alloc, n_retire;

  for (genvar i = 0; i < NISS; i++) begin : gen_alloc
    assign alloc[i] = `FT.issue_entry_valid_id_issue[i] & `FT.issue_instr_issue_id[i]
                      & ~`FT.flush_unissued_instr_ctrl_id;
  end
  for (genvar i = 0; i < NCOM; i++) begin : gen_retire
    assign retire[i] = `FT.commit_ack_commit_id[i];
  end
  assign flush    = `FT.flush_ctrl_id;
  assign flush_if = `FT.flush_ctrl_if;
  assign n_alloc  = 2'(alloc[0]) + 2'(alloc[1]);
  assign n_retire = 2'(retire[0]) + 2'(retire[1]);

  // ======================================================================
  // ORACLE 1 -- the instruction ledger
  // ======================================================================
  logic [TIDW-1:0]  sb_iptr_q;      // next id the ledger expects to allocate
  logic [TIDW-1:0]  sb_cptr_q;      // next id the ledger expects to retire
  logic [NSB-1:0]   sb_live_q;      // ids the ledger believes are in flight
  logic [3:0]       sb_cnt_q;       // how many, counted independently
  logic [VLEN-1:0]  sb_pc_q  [NSB]; // the pc the decoder handed over
  logic [4:0]       sb_rd_q  [NSB]; // the rd the decoder handed over
  fu_t              sb_fu_q  [NSB]; // the functional unit it named
  logic [NSB-1:0]   sb_wbseen_q;    // a writeback has been observed for it
  logic [XLEN-1:0]  sb_wbdata_q[NSB];
  logic [1:0]       sb_wbcnt_q[NSB];// how many writebacks it has taken

  logic [TIDW-1:0] alloc_id0, alloc_id1, retire_id0, retire_id1;
  assign alloc_id0  = sb_iptr_q;
  assign alloc_id1  = sb_iptr_q + TIDW'(alloc[0]);
  assign retire_id0 = sb_cptr_q;
  assign retire_id1 = sb_cptr_q + TIDW'(retire[0]);

  logic [NSB-1:0] sb_live_n;
  always_comb begin
    sb_live_n = sb_live_q;
    if (retire[0]) sb_live_n[retire_id0] = 1'b0;
    if (retire[1]) sb_live_n[retire_id1] = 1'b0;
    if (alloc[0])  sb_live_n[alloc_id0]  = 1'b1;
    if (alloc[1])  sb_live_n[alloc_id1]  = 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_iptr_q   <= '0;
      sb_cptr_q   <= '0;
      sb_live_q   <= '0;
      sb_cnt_q    <= '0;
      sb_wbseen_q <= '0;
      for (int k = 0; k < NSB; k++) begin
        sb_pc_q[k]     <= '0;
        sb_rd_q[k]     <= '0;
        sb_fu_q[k]     <= ariane_pkg::NONE;
        sb_wbdata_q[k] <= '0;
        sb_wbcnt_q[k]  <= '0;
      end
    end else begin
      if (flush) begin
        sb_iptr_q   <= '0;
        sb_cptr_q   <= '0;
        sb_live_q   <= '0;
        sb_cnt_q    <= '0;
        sb_wbseen_q <= '0;
      end else begin
        sb_iptr_q <= sb_iptr_q + TIDW'(n_alloc);
        sb_cptr_q <= sb_cptr_q + TIDW'(n_retire);
        sb_live_q <= sb_live_n;
        sb_cnt_q  <= sb_cnt_q + 4'(n_alloc) - 4'(n_retire);
        // a writeback is recorded against the id the functional unit names
        for (int k = 0; k < NWB; k++) begin
          if (`FT.wt_valid_ex_id[k]) begin
            sb_wbseen_q[`FT.trans_id_ex_id[k]] <= 1'b1;
            sb_wbdata_q[`FT.trans_id_ex_id[k]] <= `FT.wbdata_ex_id[k];
            if (sb_wbcnt_q[`FT.trans_id_ex_id[k]] != 2'd3)
              sb_wbcnt_q[`FT.trans_id_ex_id[k]] <= sb_wbcnt_q[`FT.trans_id_ex_id[k]] + 2'd1;
          end
        end
        // an allocation overwrites the ledger's copy of the decoded fields and
        // clears the writeback record for that id
        if (alloc[0]) begin
          sb_pc_q[alloc_id0]     <= `FT.issue_entry_id_issue[0].pc;
          sb_rd_q[alloc_id0]     <= `FT.issue_entry_id_issue[0].rd;
          sb_fu_q[alloc_id0]     <= `FT.issue_entry_id_issue[0].fu;
          sb_wbseen_q[alloc_id0] <= 1'b0;
          sb_wbcnt_q[alloc_id0]  <= 2'd0;
        end
        if (alloc[1]) begin
          sb_pc_q[alloc_id1]     <= `FT.issue_entry_id_issue[1].pc;
          sb_rd_q[alloc_id1]     <= `FT.issue_entry_id_issue[1].rd;
          sb_fu_q[alloc_id1]     <= `FT.issue_entry_id_issue[1].fu;
          sb_wbseen_q[alloc_id1] <= 1'b0;
          sb_wbcnt_q[alloc_id1]  <= 2'd0;
        end
      end
    end
  end

  // the design's own live set, read out for comparison only
  logic [NSB-1:0] dut_issued;
  for (genvar k = 0; k < NSB; k++) begin : gen_dut_issued
    assign dut_issued[k] = `SB.mem_q[k].issued;
  end

  // ======================================================================
  // ORACLE 2 -- one symbolic scoreboard entry, followed end to end
  // ======================================================================
  logic [TIDW-1:0] sym_id_q;
  logic [4:0]      sym_rd_q;
  always_ff @(posedge clk_i) begin
    sym_id_q <= sym_id_q;      // symbolic constants: no other driver
    sym_rd_q <= sym_rd_q;
  end

  logic sym_alloc, sym_retire;
  assign sym_alloc  = (alloc[0]  && alloc_id0  == sym_id_q)
                   || (alloc[1]  && alloc_id1  == sym_id_q);
  assign sym_retire = (retire[0] && retire_id0 == sym_id_q)
                   || (retire[1] && retire_id1 == sym_id_q);

  logic [1:0] sym_retire_cnt_q;    // retirements since the last allocation
  logic [8:0] sym_age_q;           // cycles it has been in flight, saturating
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sym_retire_cnt_q <= '0;
      sym_age_q        <= '0;
    end else if (flush || sym_alloc) begin
      sym_retire_cnt_q <= '0;
      sym_age_q        <= '0;
    end else begin
      if (sym_retire && sym_retire_cnt_q != 2'd3)
        sym_retire_cnt_q <= sym_retire_cnt_q + 2'd1;
      if (sb_live_q[sym_id_q] && sym_age_q != 9'h1ff) sym_age_q <= sym_age_q + 9'd1;
      else if (!sb_live_q[sym_id_q]) sym_age_q <= '0;
    end
  end

  // ======================================================================
  // ORACLE 3 -- the architectural register file, shadowed on one register
  // ======================================================================
  logic [XLEN-1:0] rf_shadow_q;
  logic            rf_seen_q;
  logic [NCOM-1:0] rf_hit;
  for (genvar i = 0; i < NCOM; i++) begin : gen_rf_hit
    assign rf_hit[i] = `FT.we_gpr_commit_id[i] && (`FT.waddr_commit_id[i] == sym_rd_q)
                       && (sym_rd_q != 5'd0);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rf_shadow_q <= '0;
      rf_seen_q   <= 1'b0;
    end else if (rf_hit[1]) begin       // port 1 is written last in the RTL loop
      rf_shadow_q <= `FT.wdata_commit_id[1];
      rf_seen_q   <= 1'b1;
    end else if (rf_hit[0]) begin
      rf_shadow_q <= `FT.wdata_commit_id[0];
      rf_seen_q   <= 1'b1;
    end
  end

  // ======================================================================
  // ORACLE 4 -- the IF/ID handover, counted
  // ======================================================================
  logic [2:0] idq_cnt_q;           // entries handed to ID but not yet to ISSUE
  logic [1:0] n_fetch;
  assign n_fetch = 2'(`FT.fetch_valid_if_id[0] & `FT.fetch_ready_id_if[0])
                 + 2'(`FT.fetch_valid_if_id[1] & `FT.fetch_ready_id_if[1]);
  // the ID stage's own occupancy, read out for comparison only
  logic [1:0] dut_id_occ;
  assign dut_id_occ = 2'(`FT.id_stage_i.issue_q[0].valid) + 2'(`FT.id_stage_i.issue_q[1].valid);

  logic [1:0] n_id_out;
  assign n_id_out = 2'(`FT.issue_entry_valid_id_issue[0] & `FT.issue_instr_issue_id[0])
                  + 2'(`FT.issue_entry_valid_id_issue[1] & `FT.issue_instr_issue_id[1]);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) idq_cnt_q <= '0;
    else if (flush_if) idq_cnt_q <= '0;
    else idq_cnt_q <= idq_cnt_q + 3'(n_fetch) - 3'(n_id_out);
  end

  // ======================================================================
  // ORACLE 5 -- the two memory ports, counted
  // ======================================================================
  logic ld_req, ld_gnt, ld_rvalid, st_req, st_gnt;
  assign ld_req    = `FT.dcache_req_ports_ex_cache[1].data_req;
  assign ld_gnt    = ld_req & `FT.dcache_req_ports_cache_ex[1].data_gnt;
  assign ld_rvalid = `FT.dcache_req_ports_cache_ex[1].data_rvalid;
  assign st_req    = `FT.dcache_req_ports_ex_cache[2].data_req;
  assign st_gnt    = st_req & `FT.dcache_req_ports_cache_ex[2].data_gnt;

  logic [2:0] ld_out_q;            // loads granted but not yet answered
  logic [NLD-1:0] ld_id_live_q;    // which load ids are outstanding
  logic [3:0] st_q_cnt_q;          // stores handed to the LSU but not to memory
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ld_out_q     <= '0;
      ld_id_live_q <= '0;
      st_q_cnt_q   <= '0;
    end else begin
      ld_out_q <= ld_out_q + 3'(ld_gnt) - 3'(ld_rvalid);
      if (ld_rvalid) ld_id_live_q[`FT.dcache_req_ports_cache_ex[1].data_rid] <= 1'b0;
      if (ld_gnt) ld_id_live_q[`FT.dcache_req_ports_ex_cache[1].data_id] <= 1'b1;
      st_q_cnt_q <= st_q_cnt_q + 4'(`FT.lsu_commit_commit_ex) - 4'(st_gnt);
    end
  end

  // ======================================================================
  // ORACLE 6 -- saturating wait counters (the bounded-safety encoding of
  // fairness, bounded response and deadlock freedom)
  // ======================================================================
  logic [9:0] fetch_wait_q;        // fetch asked, not yet answered
  logic [9:0] load_wait_q;         // load granted, not yet answered
  logic [9:0] store_wait_q;        // store asking, not yet granted
  logic [9:0] retire_wait_q;       // scoreboard not empty, nothing retiring
  logic [9:0] progress_wait_q;     // nothing at all moved

  logic ic_req, ic_rsp, any_progress;
  assign ic_req = `FT.icache_dreq_if_cache.req;
  assign ic_rsp = `FT.icache_dreq_cache_if.valid;
  assign any_progress = (|retire) | flush | (|alloc) | (n_fetch != 2'd0) | ic_rsp
                      | ld_gnt | ld_rvalid | st_gnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fetch_wait_q    <= '0;
      load_wait_q     <= '0;
      store_wait_q    <= '0;
      retire_wait_q   <= '0;
      progress_wait_q <= '0;
    end else begin
      if (ic_req && !ic_rsp && !`FT.icache_dreq_cache_if.ready) fetch_wait_q <= fetch_wait_q + 10'd1;
      else fetch_wait_q <= '0;

      if ((ld_out_q != 3'd0) && !ld_rvalid) load_wait_q <= load_wait_q + 10'd1;
      else load_wait_q <= '0;

      if (st_req && !st_gnt) store_wait_q <= store_wait_q + 10'd1;
      else store_wait_q <= '0;

      if ((sb_cnt_q != 4'd0) && !(|retire) && !flush) retire_wait_q <= retire_wait_q + 10'd1;
      else retire_wait_q <= '0;

      if (!any_progress) progress_wait_q <= progress_wait_q + 10'd1;
      else progress_wait_q <= '0;
    end
  end

  // the first cycle in which reset is released, for the reset targets
  logic out_of_reset_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) out_of_reset_q <= 1'b0;
    else out_of_reset_q <= 1'b1;
  end
  logic first_cycle;
  assign first_cycle = rst_ni & ~out_of_reset_q;

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // ======================================================================
  // 1. END-TO-END ORDERING
  // ======================================================================

  // The ledger allocates ids in the order instructions crossed the ID/ISSUE
  // handshake. If the scoreboard's issue pointer is the same value, then the
  // id an instruction carries through EX is its position in program order.
  T_ORDER_SB_ISSUE_POINTER_IS_PROGRAM_ORDER: assert property (
      sb_iptr_q == `SB.issue_pointer_q);

  // ... and its commit pointer is the oldest instruction still in flight.
  T_ORDER_SB_COMMIT_POINTER_IS_OLDEST: assert property (
      sb_cptr_q == `SB.commit_pointer_q[0]);

  // Retirement happens at the ledger's head: commit order IS program order.
  T_ORDER_COMMIT_ID_IS_LEDGER_HEAD: assert property (
      retire[0] |-> `FT.commit_instr_id_commit[0].trans_id == sb_cptr_q);

  // The second commit port retires the instruction immediately after it.
  T_ORDER_COMMIT_PORT1_IS_NEXT_IN_ORDER: assert property (
      retire[1] |-> `FT.commit_instr_id_commit[1].trans_id == sb_cptr_q + TIDW'(1));

  // The pc that retires is the pc the decoder handed over for that position.
  T_ORDER_COMMIT_PC_IN_PROGRAM_ORDER: assert property (
      (retire[0] && sb_live_q[sb_cptr_q]) |->
          `FT.commit_instr_id_commit[0].pc == sb_pc_q[sb_cptr_q]);

  // Both issue ports allocate in order: port 1 never allocates alone. If it
  // did, the scoreboard would write mem_n[issue_pointer+1] while advancing
  // the pointer by one, and the entry order would no longer be program order.
  T_ORDER_ISSUE_ACK_IN_ORDER: assert property (
      `FT.issue_instr_issue_id[1] |-> `FT.issue_instr_issue_id[0]);

  // ======================================================================
  // 2. DATA INTEGRITY
  // ======================================================================

  // The destination register that retires is the one the decoder named. The
  // scoreboard rewrites `rd` for a CVXIF entry (and only for that), which is
  // why the CVXIF case is excluded rather than the assertion weakened.
  T_DATA_COMMIT_RD_IS_DECODED_RD: assert property (
      (retire[0] && sb_live_q[sb_cptr_q] && sb_fu_q[sb_cptr_q] != CVXIF) |->
          `FT.commit_instr_id_commit[0].rd == sb_rd_q[sb_cptr_q]);

  // The functional unit that retires is the one the decoder named.
  T_DATA_COMMIT_FU_IS_DECODED_FU: assert property (
      (retire[0] && sb_live_q[sb_cptr_q]) |->
          `FT.commit_instr_id_commit[0].fu == sb_fu_q[sb_cptr_q]);

  // The value written into the register file is the value a functional unit
  // wrote back for that id. CSR is excluded because commit_stage substitutes
  // the CSR read data for the scoreboard result, which is the one legitimate
  // place where the retired value is not the written-back one.
  T_DATA_COMMIT_WDATA_IS_WRITEBACK_DATA: assert property (
      (retire[0] && `FT.we_gpr_commit_id[0] && sb_wbseen_q[sb_cptr_q]
        && sb_fu_q[sb_cptr_q] != CSR) |->
          `FT.wdata_commit_id[0] == sb_wbdata_q[sb_cptr_q]);

  // The register file holds the last value commit wrote to it. This is the
  // architectural-state statement: it spans decode, the scoreboard, both
  // commit ports and the write-port priority inside the register file.
  T_DATA_REGFILE_HOLDS_LAST_COMMITTED_WRITE: assert property (
      rf_seen_q |-> `RF.mem[sym_rd_q] == rf_shadow_q);

  // The address the register file is written at is the decoded rd.
  T_DATA_REGFILE_WADDR_IS_DECODED_RD: assert property (
      (retire[0] && `FT.we_gpr_commit_id[0] && sb_live_q[sb_cptr_q]
        && sb_fu_q[sb_cptr_q] != CVXIF) |->
          `FT.waddr_commit_id[0] == sb_rd_q[sb_cptr_q]);

  // ======================================================================
  // 3. UNIQUENESS / NO DUPLICATION
  // ======================================================================

  // and the acknowledge that would be the second one never happens.
  T_UNIQ_NO_SECOND_RETIRE_OF_SAME_ENTRY: assert property (
      sym_retire |-> sym_retire_cnt_q == 2'd0);

  // A scoreboard entry is never allocated while the ledger still holds it in
  // flight -- no instruction can overwrite an older one that has not retired.
  T_UNIQ_SB_ENTRY_NOT_ALLOCATED_WHILE_LIVE: assert property (
      alloc[0] |-> !sb_live_q[alloc_id0]);

  // An allocated entry takes at most one writeback. Two would mean a stale
  // result from a flushed memory operation landing on a re-used id.
  T_UNIQ_ONE_WRITEBACK_PER_ENTRY: assert property (
      sb_live_q[sym_id_q] |-> sb_wbcnt_q[sym_id_q] <= 2'd1);

  // A load id is never handed to memory while a load with that id is still
  // outstanding -- the load buffer's free-index picker never picks a live one.
  T_UNIQ_LOAD_ID_NOT_REUSED_WHILE_OUTSTANDING: assert property (
      ld_gnt |-> !ld_id_live_q[`FT.dcache_req_ports_ex_cache[1].data_id]);

  // ======================================================================
  // 4. NO LOSS / CONSERVATION
  // ======================================================================

  // in == out + in flight, for the scoreboard: the ledger's count of
  // instructions admitted and not yet retired equals the number of entries
  // the scoreboard believes are issued.
  T_CONSERV_SB_OCCUPANCY_MATCHES_LEDGER: assert property (
      sb_cnt_q == 4'($countones(dut_issued)));

  // ... and the SET, not just the count.
  T_CONSERV_SB_LIVE_SET_MATCHES_LEDGER: assert property (
      sb_live_q == dut_issued);

  // The ID stage holds exactly what it was handed and has not passed on.
  T_CONSERV_ID_STAGE_OCCUPANCY_MATCHES: assert property (
      idq_cnt_q == 3'(dut_id_occ));

  T_CONSERV_LOAD_ID_SET_MATCHES_BUFFER: assert property (
      ld_id_live_q == `LDU.ldbuf_valid_q);

  // The store buffer's non-speculative queue holds exactly the stores commit
  // has released and memory has not accepted.
  T_CONSERV_STORE_COMMIT_QUEUE_MATCHES: assert property (
      st_q_cnt_q == 4'(`STB.commit_status_cnt_q));

  // ======================================================================
  // 5. MUTUAL EXCLUSION / ONE-HOT
  // ======================================================================

  // No two writeback ports name the same scoreboard entry in one cycle.
  T_MUTEX_WRITEBACK_TRANS_ID_UNIQUE: assert property (
      (`FT.wt_valid_ex_id[FLU_WB] && `FT.wt_valid_ex_id[LOAD_WB]) |->
          `FT.trans_id_ex_id[FLU_WB] != `FT.trans_id_ex_id[LOAD_WB]);

  // The instruction queue's output select stays one-hot: exactly one of the
  // four replicated instruction fifos drives the next instruction.
  T_MUTEX_INSTR_QUEUE_SELECT_ONEHOT: assert property (
      $onehot(`IQ.idx_ds_q));

  // Only one memory operation is in the LSU's address path at a time: the
  // bypass register hands its entry either to the load unit or to the store
  // unit, never to both.
  T_MUTEX_LSU_ONE_CONSUMER: assert property (
      !(`FT.ex_stage_i.lsu_i.ld_valid_i && `FT.ex_stage_i.lsu_i.st_valid_i));

  // ======================================================================
  // 6. OCCUPANCY AND BOUNDS
  // ======================================================================

  T_BOUND_SB_OCCUPANCY_LE_ENTRIES: assert property (sb_cnt_q <= 4'(NSB));

  // The scoreboard refuses to admit an instruction when the ledger says it is
  // full -- the two-slot rule for superscalar issue included.
  T_BOUND_NO_ALLOC_WHEN_LEDGER_FULL: assert property (
      (sb_cnt_q == 4'(NSB)) |-> !alloc[0]);

  T_BOUND_LOADS_OUTSTANDING_LE_LOAD_BUF: assert property (ld_out_q <= 3'(NLD));

  T_BOUND_STORE_COMMIT_QUEUE_LE_DEPTH: assert property (st_q_cnt_q <= 4'd4);

  T_BOUND_STORE_SPEC_QUEUE_LE_DEPTH: assert property (
      `STB.speculative_status_cnt_q <= 3'd4);

  T_BOUND_INSTR_QUEUE_USAGE_LE_DEPTH: assert property (
      `IQ.gen_instr_fifo[0].i_fifo_instr_data.status_cnt_q <= 3'(ariane_pkg::FETCH_FIFO_DEPTH));

  // ======================================================================
  // 7. ALLOCATOR DISCIPLINE
  // ======================================================================

  // Never retire an entry the ledger does not hold in flight.
  T_ALLOC_RETIRE_ONLY_LIVE_ENTRY: assert property (
      retire[0] |-> sb_live_q[retire_id0]);

  // The store buffer never releases a store to memory from an empty queue.
  T_ALLOC_NO_STORE_REQUEST_WHEN_QUEUE_EMPTY: assert property (
      st_req |-> (st_q_cnt_q != 4'd0));

  // ======================================================================
  // 8. REQUEST-RESPONSE CORRESPONDENCE
  // ======================================================================

  // No unsolicited load response: every rvalid names a load that was granted.
  T_REQRSP_LOAD_RESPONSE_WAS_REQUESTED: assert property (
      ld_rvalid |-> ld_id_live_q[`FT.dcache_req_ports_cache_ex[1].data_rid]);

  // No unsolicited fetch response: the icache only answers a request it took.
  T_REQRSP_FETCH_RESPONSE_WAS_REQUESTED: assert property (
      ic_rsp |-> `FT.u_icache.pending_q);

  // A writeback names an entry the ledger holds in flight, unless the
  // pipeline was flushed while the operation was in memory -- which is the
  // one case the scoreboard itself guards against with `mem_q[id].issued`.
  T_REQRSP_WRITEBACK_NAMES_LIVE_ENTRY: assert property (
      (`FT.wt_valid_ex_id[FLU_WB] && !flush) |-> sb_live_q[`FT.trans_id_ex_id[FLU_WB]]);

  // ======================================================================
  // 9. PROTOCOL CONFORMANCE
  // ======================================================================

  // The decoded instruction offered to issue does not change while it is
  // being refused.
  T_PROTO_ISSUE_ENTRY_STABLE_UNTIL_ACK: assert property (
      (`FT.issue_entry_valid_id_issue[0] && !`FT.issue_instr_issue_id[0] && !flush_if)
      |=> $stable(`FT.issue_entry_id_issue[0].pc));

  // The fetch entry offered to decode does not change while it is refused.
  T_PROTO_FETCH_ENTRY_STABLE_UNTIL_READY: assert property (
      (`FT.fetch_valid_if_id[0] && !`FT.fetch_ready_id_if[0] && !flush_if)
      |=> $stable(`FT.fetch_entry_if_id[0].address));

  // A load request is not withdrawn before it is granted, and its id and
  // index do not move underneath the cache.
  T_PROTO_LOAD_REQUEST_ID_STABLE: assert property (
      (ld_req && !ld_gnt && !`FT.dcache_req_ports_ex_cache[1].kill_req)
      |=> $stable(`FT.dcache_req_ports_ex_cache[1].data_id));

  // A store request is not withdrawn before it is granted, and its payload
  // does not move.
  T_PROTO_STORE_REQUEST_HELD: assert property (
      (st_req && !st_gnt) |=> st_req);

  T_PROTO_STORE_PAYLOAD_STABLE: assert property (
      (st_req && !st_gnt) |=> $stable(`FT.dcache_req_ports_ex_cache[2].data_wdata)
                              && $stable(`FT.dcache_req_ports_ex_cache[2].address_index));

  // ======================================================================
  // 10. ARBITRATION FAIRNESS (bounded-safety encoding)
  // ======================================================================

  // The store port shares the memory interface with the load port and is the
  // lower-priority one inside the LSU. With the model granting within 8, a
  // store asking is granted well inside 32 cycles.
  T_FAIR_STORE_PORT_GRANTED_WITHIN_N: assert property (store_wait_q < 10'(STORE_BOUND));

  // The frontend is never left asking for an instruction indefinitely.
  T_FAIR_FETCH_PORT_SERVED_WITHIN_N: assert property (fetch_wait_q < 10'(FETCH_BOUND));

  // ======================================================================
  // 11. BOUNDED RESPONSE (bounded-safety encoding)
  // ======================================================================

  // A granted load is answered inside the model's 8-cycle bound plus slack.
  T_BOUNDRSP_LOAD_ANSWERED_WITHIN_N: assert property (load_wait_q < 10'(LOAD_BOUND));

  // An instruction that entered the scoreboard leaves it -- by retiring or by
  // being flushed -- inside RETIRE_BOUND cycles.
  T_BOUNDRSP_SYMBOLIC_ENTRY_LEAVES_WITHIN_N: assert property (
      sym_age_q < 9'(RETIRE_BOUND));

  // With work in the scoreboard, something retires (or the pipe is flushed)
  // inside RETIRE_BOUND cycles.
  T_BOUNDRSP_RETIREMENT_WITHIN_N: assert property (retire_wait_q < 10'(RETIRE_BOUND));

  // ======================================================================
  // 12. DEADLOCK FREEDOM (bounded-safety encoding)
  // ======================================================================

  // No state in which nothing moves: at most PROGRESS_BOUND consecutive
  // cycles pass with no handshake anywhere in the pipeline.
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N: assert property (
      progress_wait_q < 10'(PROGRESS_BOUND));

  // ======================================================================
  // 13. RESET / INITIALISATION
  // ======================================================================

  T_RESET_SCOREBOARD_EMPTY: assert property (@(posedge clk_i)
      first_cycle |-> dut_issued == '0);

  T_RESET_SB_POINTERS_ZERO: assert property (@(posedge clk_i)
      first_cycle |-> (`SB.issue_pointer_q == '0 && `SB.commit_pointer_q[0] == '0));

  T_RESET_LOAD_BUFFER_EMPTY: assert property (@(posedge clk_i)
      first_cycle |-> `LDU.ldbuf_valid_q == '0);

  // ======================================================================
  // 14. LIFECYCLE / ACCESS CONTROL
  // ======================================================================

  // The architectural register file changes only when commit says so. This is
  // the access-control statement for architectural state: nothing in EX, in
  // the scoreboard or in the frontend may write it.
  T_LIFECYCLE_REGFILE_WRITTEN_ONLY_BY_COMMIT: assert property (
      (`RF.mem[sym_rd_q] != $past(`RF.mem[sym_rd_q])) |-> $past(|rf_hit));

  // A cancelled entry -- one the speculative scoreboard killed behind a
  // mispredicted branch -- is acknowledged but must never reach the register
  // file.
  T_LIFECYCLE_CANCELLED_ENTRY_NEVER_WRITES_GPR: assert property (
      (retire[0] && `FT.commit_drop_id_commit[0]) |-> !`FT.we_gpr_commit_id[0]);

endmodule

bind cva6_frontend_issue_commit_ft cva6_pipe_targets u_targets (
    .clk_i (clk_i),
    .rst_ni(rst_ni)
);
