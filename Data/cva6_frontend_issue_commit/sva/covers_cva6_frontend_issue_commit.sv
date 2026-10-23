//
// Reachability covers for tasks/cva6_frontend_issue_commit.
//
// NOT targets. At least one per category the target file uses, showing that
// the scenario each target constrains is reachable -- a target whose scenario
// is unreachable is vacuous and the phase-1 screen drops it. `COVER_DEPTH` is
// what reads these.
//
// They are deliberately stated on the same signals the targets are stated on,
// through the same bound checker instance, so a cover that will not hit says
// the target above it is talking about nothing.
//
module cva6_pipe_covers
  import ariane_pkg::*;
  import cva6_pipe_fv_pkg::*;
(
    input logic clk_i,
    input logic rst_ni
);

  `define FTC cva6_frontend_issue_commit_ft
  `define SBC `FTC.issue_stage_i.i_scoreboard
  `define LDUC `FTC.ex_stage_i.lsu_i.i_load_unit
  `define STBC `FTC.ex_stage_i.lsu_i.i_store_unit.store_buffer_i

  logic [cva6_pipe_fv_pkg::Cfg.NR_SB_ENTRIES-1:0] issued;
  for (genvar k = 0; k < cva6_pipe_fv_pkg::Cfg.NR_SB_ENTRIES; k++) begin : gen_issued
    assign issued[k] = `SBC.mem_q[k].issued;
  end

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  // ---- the pipeline runs at all ----------------------------------------
  C_FETCH_RESPONSE:        cover property (`FTC.icache_dreq_cache_if.valid);
  C_IF_ID_HANDOVER:        cover property (`FTC.fetch_valid_if_id[0] & `FTC.fetch_ready_id_if[0]);
  C_ID_ISSUE_HANDOVER:     cover property (`FTC.issue_entry_valid_id_issue[0]
                                           & `FTC.issue_instr_issue_id[0]);
  C_COMMIT:                cover property (`FTC.commit_ack_commit_id[0]);

  // ---- ordering: two instructions retire in one cycle, in order --------
  C_DUAL_COMMIT:           cover property (&`FTC.commit_ack_commit_id);
  C_DUAL_ISSUE:            cover property (&`FTC.issue_instr_issue_id);

  // ---- occupancy: the 8-entry window is actually used ------------------
  C_SB_TWO_IN_FLIGHT:      cover property ($countones(issued) == 2);
  C_SB_FOUR_IN_FLIGHT:     cover property ($countones(issued) == 4);
  C_SB_FULL:               cover property (&issued);
  C_SB_FULL_THEN_DRAINS:   cover property ((&issued) ##[1:20] (issued == '0));

  // ---- out-of-order completion: the point of the scoreboard ------------
  C_LOAD_WRITEBACK:        cover property (`FTC.wt_valid_ex_id[LOAD_WB]);
  C_STORE_WRITEBACK:       cover property (`FTC.wt_valid_ex_id[STORE_WB]);
  C_FLU_AND_LOAD_WB_TOGETHER: cover property (`FTC.wt_valid_ex_id[FLU_WB]
                                              & `FTC.wt_valid_ex_id[LOAD_WB]);
  C_WRITEBACK_OUT_OF_ORDER: cover property (
      `FTC.wt_valid_ex_id[LOAD_WB] && `FTC.wt_valid_ex_id[FLU_WB]
      && (`FTC.trans_id_ex_id[LOAD_WB] < `FTC.trans_id_ex_id[FLU_WB]));

  // ---- data integrity: a value actually reaches the register file ------
  C_GPR_WRITE:             cover property (`FTC.we_gpr_commit_id[0]);
  C_GPR_WRITE_BOTH_PORTS:  cover property (&`FTC.we_gpr_commit_id);
  C_GPR_WRITE_SAME_REG:    cover property ((&`FTC.we_gpr_commit_id)
                                           && `FTC.waddr_commit_id[0] == `FTC.waddr_commit_id[1]);

  // ---- memory: loads and stores reach the cache model ------------------
  C_LOAD_GRANTED:          cover property (`FTC.dcache_req_ports_ex_cache[1].data_req
                                           & `FTC.dcache_req_ports_cache_ex[1].data_gnt);
  C_TWO_LOADS_OUTSTANDING: cover property (&`LDUC.ldbuf_valid_q);
  C_STORE_GRANTED:         cover property (`FTC.dcache_req_ports_ex_cache[2].data_req
                                           & `FTC.dcache_req_ports_cache_ex[2].data_gnt);
  C_STORE_QUEUE_NONEMPTY:  cover property (`STBC.commit_status_cnt_q != '0);
  C_STORE_SPEC_QUEUE_FULL: cover property (`STBC.speculative_status_cnt_q == 3'd4);

  // ---- control flow: the frontend actually redirects --------------------
  C_BRANCH_RESOLVED:       cover property (`FTC.resolved_branch.valid);
  C_MISPREDICT:            cover property (`FTC.resolved_branch.valid
                                           & `FTC.resolved_branch.is_mispredict);
  C_FLUSH:                 cover property (`FTC.flush_ctrl_id);
  C_EXCEPTION_AT_COMMIT:   cover property (`FTC.ex_commit.valid);
  C_ERET:                  cover property (`FTC.eret);
  C_DROPPED_COMMIT:        cover property (`FTC.commit_ack_commit_id[0]
                                           & `FTC.commit_drop_id_commit[0]);

  // ---- the functional units are all reachable ---------------------------
  C_ALU_ISSUE:             cover property (|`FTC.alu_valid_id_ex);
  C_ALU2_ISSUE:            cover property (|`FTC.alu2_valid_id_ex);
  C_MULT_ISSUE:            cover property (|`FTC.mult_valid_id_ex);
  C_CSR_ISSUE:             cover property (|`FTC.csr_valid_id_ex);
  C_BRANCH_ISSUE:          cover property (|`FTC.branch_valid_id_ex);
  C_LSU_ISSUE:             cover property (|`FTC.lsu_valid_id_ex);
  C_CVXIF_ISSUE:           cover property (|`FTC.x_issue_valid_id_ex);

  // ---- bounded response / fairness: the waits are non-trivial ----------
  C_STORE_WAITS_FOR_GRANT: cover property (`FTC.u_targets.store_wait_q == 10'd4);
  C_LOAD_WAITS_FOR_DATA:   cover property (`FTC.u_targets.load_wait_q == 10'd4);
  C_RETIREMENT_STALLS:     cover property (`FTC.u_targets.retire_wait_q == 10'd16);
  C_NO_PROGRESS_FOR_A_WHILE: cover property (`FTC.u_targets.progress_wait_q == 10'd8);

  // ---- lifecycle: the symbolic register is actually written ------------
  C_SYMBOLIC_REG_WRITTEN:  cover property (`FTC.u_targets.rf_seen_q);
  C_SYMBOLIC_ENTRY_RETIRES: cover property (`FTC.u_targets.sym_retire);

endmodule

bind cva6_frontend_issue_commit_ft cva6_pipe_covers u_covers (
    .clk_i (clk_i),
    .rst_ni(rst_ni)
);
