// ---------------------------------------------------------------------------
// cva6_frontend_issue_commit_ft -- the formal top.
//
// THE CUT.  Five pipeline stages of CVA6 with the real buffering between them,
// and nothing else:
//
//    frontend            PC gen, BHT, RAS, instr_scan x4, instr_realign,
//      |                 and the INSTRUCTION QUEUE (a 4-wide replicated
//      |                 instruction fifo plus its address fifo)
//      v
//    id_stage            compressed decoder x2 + decoder x2, one registered
//      |                 issue slot per issue port
//      v
//    issue_stage         the SCOREBOARD (8 entries, out of order) and
//      |                 issue_read_operands (the GPR file, the RAW checkers
//      |                 and the forwarding network)
//      v
//    ex_stage            2 ALUs, branch unit, CSR buffer, mult/div, the
//      |                 load-store unit with its LOAD BUFFER (2 entries) and
//      |                 its STORE BUFFER (speculative + commit queues), and
//      v                 cvxif_fu
//    commit_stage        in-order retirement, 2 commit ports
//
// with `controller` (the flush controller) and `csr_regfile` (the trap and
// CSR state) alongside, exactly as `core/cva6.sv` wires them.  Everything
// below is lifted from `core/cva6.sv` lines 349-1408 with the four blocks
// that are NOT in the cut removed -- the cache subsystem, the accelerator
// dispatcher, the performance counters and the RVFI/tracer probes -- and the
// signals they drove supplied by the two memory models in `ft/`.
//
// What is authored here rather than copied:
//   * `u_icache`  the instruction-cache model (ft/cva6_fv_icache.sv)
//   * `u_dcache`  the data-cache model        (ft/cva6_fv_dcache.sv)
//   * the CVXIF coprocessor model: a coprocessor that implements NOTHING.
//     It completes every handshake and accepts no instruction, so every
//     offload is rejected and comes back through `cvxif_fu` as an
//     illegal-instruction exception.  That is a legal coprocessor and it
//     cannot wedge the scoreboard; see PROVENANCE.md for what it costs.
//   * the tie-offs for the accelerator ports (`RVV = 0`, so `acc_dispatcher`
//     is not instantiated upstream either).
//
// Every free choice -- when the icache answers, what it answers with, when
// the dcache grants, which outstanding load it answers, what data it returns,
// and the four interrupt/debug pins -- is an unconstrained INPUT of this
// module.  No assumption is declared anywhere in this package.
// ---------------------------------------------------------------------------
`include "rvfi_types.svh"
`include "cvxif_types.svh"

module cva6_frontend_issue_commit_ft
  import ariane_pkg::*;
  import cva6_pipe_fv_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = cva6_pipe_fv_pkg::Cfg
) (
    input logic clk_i,
    input logic rst_ni,
    // the core's asynchronous pins, left free
    input logic [1:0] irq_i,
    input logic       ipi_i,
    input logic       time_irq_i,
    input logic       debug_req_i,
    // free choices of the instruction-cache model
    input logic                           fv_ic_ready_i,
    input logic                           fv_ic_resp_go_i,
    input logic [CVA6Cfg.FETCH_WIDTH-1:0] fv_ic_data_i,
    // free choices of the data-cache model
    input logic                    fv_dc_ld_gnt_i,
    input logic                    fv_dc_st_gnt_i,
    input logic                    fv_dc_ld_go_i,
    input logic                    fv_dc_ld_sel_i,
    input logic [CVA6Cfg.XLEN-1:0] fv_dc_ld_data_i
);

  // The two accelerator types `core/cva6.sv` carries as parameters. RVV = 0,
  // so nothing reads them; they exist because the declarations below do.
  localparam type acc_mmu_req_t = logic;
  localparam type acc_mmu_resp_t = logic;

  // Reset vector and hart id, constants rather than free inputs: neither is a
  // pipeline behaviour and both would only add symbolic state.
  logic [CVA6Cfg.VLEN-1:0] boot_addr_i;
  logic [CVA6Cfg.XLEN-1:0] hart_id_i;
  assign boot_addr_i = CVA6Cfg.VLEN'(32'h8000_0000);
  assign hart_id_i   = '0;

  // The CVXIF response, driven by the coprocessor model at the bottom.
  cvxif_resp_t cvxif_resp_i;

  // ==== core/cva6.sv 349-692: the interrupt table and every signal that
  // ==== connects two stages, copied unchanged.
  localparam type interrupts_t = struct packed {
    logic [CVA6Cfg.XLEN-1:0] S_SW;
    logic [CVA6Cfg.XLEN-1:0] VS_SW;
    logic [CVA6Cfg.XLEN-1:0] M_SW;
    logic [CVA6Cfg.XLEN-1:0] S_TIMER;
    logic [CVA6Cfg.XLEN-1:0] VS_TIMER;
    logic [CVA6Cfg.XLEN-1:0] M_TIMER;
    logic [CVA6Cfg.XLEN-1:0] S_EXT;
    logic [CVA6Cfg.XLEN-1:0] VS_EXT;
    logic [CVA6Cfg.XLEN-1:0] M_EXT;
    logic [CVA6Cfg.XLEN-1:0] HS_EXT;
  };

  localparam interrupts_t INTERRUPTS = '{
      S_SW: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_S_SOFT),
      VS_SW: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_VS_SOFT),
      M_SW: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_M_SOFT),
      S_TIMER: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_S_TIMER),
      VS_TIMER: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_VS_TIMER),
      M_TIMER: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_M_TIMER),
      S_EXT: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_S_EXT),
      VS_EXT: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_VS_EXT),
      M_EXT: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_M_EXT),
      HS_EXT: (CVA6Cfg.XLEN'(1) << (CVA6Cfg.XLEN - 1)) | CVA6Cfg.XLEN'(riscv::IRQ_HS_EXT)
  };

  // ------------------------------------------
  // Global Signals
  // Signals connecting more than one module
  // ------------------------------------------
  riscv::priv_lvl_t priv_lvl;
  logic v;
  exception_t ex_commit;  // exception from commit stage
  bp_resolve_t resolved_branch;
  logic [CVA6Cfg.VLEN-1:0] pc_commit;
  logic eret;
  logic [CVA6Cfg.NrCommitPorts-1:0] commit_ack;
  logic [CVA6Cfg.NrCommitPorts-1:0] commit_macro_ack;
  logic mbe;  // determines the data endian-ness of the processor

  localparam NumPorts = 4;

  // CVXIF
  cvxif_req_t cvxif_req;
  // CVXIF OUTPUTS
  logic x_compressed_valid;
  x_compressed_req_t x_compressed_req;
  logic x_issue_valid;
  x_issue_req_t x_issue_req;
  logic x_register_valid;
  x_register_t x_register;
  logic x_commit_valid;
  x_commit_t x_commit;
  logic x_result_ready;
  // CVXIF INPUTS
  logic x_compressed_ready;
  x_compressed_resp_t x_compressed_resp;
  logic x_issue_ready;
  x_issue_resp_t x_issue_resp;
  logic x_register_ready;
  logic x_result_valid;
  x_result_t x_result;

  // --------------
  // PCGEN <-> CSR
  // --------------
  logic [CVA6Cfg.VLEN-1:0] trap_vector_base_commit_pcgen;
  logic [CVA6Cfg.VLEN-1:0] epc_commit_pcgen;
  // --------------
  // IF <-> ID
  // --------------
  fetch_entry_t [CVA6Cfg.NrIssuePorts-1:0] fetch_entry_if_id;
  logic [CVA6Cfg.NrIssuePorts-1:0] fetch_valid_if_id;
  logic [CVA6Cfg.NrIssuePorts-1:0] fetch_ready_id_if;

  // --------------
  // ID <-> ISSUE
  // --------------
  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] issue_entry_id_issue, issue_entry_id_issue_prev;
  logic [CVA6Cfg.NrIssuePorts-1:0][31:0] orig_instr_id_issue;
  logic [CVA6Cfg.NrIssuePorts-1:0] issue_entry_valid_id_issue;
  logic [CVA6Cfg.NrIssuePorts-1:0] is_ctrl_fow_id_issue;
  logic [CVA6Cfg.NrIssuePorts-1:0] issue_instr_issue_id;

  // --------------
  // ISSUE <-> EX
  // --------------
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.VLEN-1:0] rs1_forwarding_id_ex;  // unregistered version of fu_data_o.operanda
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.VLEN-1:0] rs2_forwarding_id_ex;  // unregistered version of fu_data_o.operandb
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.XLEN-1:0] rvfi_rs1;
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.XLEN-1:0] rvfi_rs2;

  fu_data_t [CVA6Cfg.NrIssuePorts-1:0] fu_data_id_ex;
  alu_bypass_t alu_bypass_id_ex;
  logic [CVA6Cfg.VLEN-1:0] pc_id_ex;
  logic zcmt_id_ex;
  logic is_compressed_instr_id_ex;
  logic [CVA6Cfg.NrIssuePorts-1:0][31:0] tinst_ex;
  // fixed latency units
  logic flu_ready_ex_id;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] flu_trans_id_ex_id;
  logic flu_valid_ex_id;
  logic [CVA6Cfg.XLEN-1:0] flu_result_ex_id;
  exception_t flu_exception_ex_id;
  // ALU
  logic [CVA6Cfg.NrIssuePorts-1:0] alu_valid_id_ex;
  logic [5:0] orig_instr_aes;
  logic [CVA6Cfg.NrIssuePorts-1:0] aes_valid_id_ex;
  // Branches and Jumps
  logic [CVA6Cfg.NrIssuePorts-1:0] branch_valid_id_ex;

  branchpredict_sbe_t branch_predict_id_ex;
  logic resolve_branch_ex_id;
  // LSU
  logic [CVA6Cfg.NrIssuePorts-1:0] lsu_valid_id_ex;
  logic lsu_ready_ex_id;

  logic [CVA6Cfg.TRANS_ID_BITS-1:0] load_trans_id_ex_id;
  logic [CVA6Cfg.XLEN-1:0] load_result_ex_id;
  logic load_valid_ex_id;
  exception_t load_exception_ex_id;

  logic [CVA6Cfg.XLEN-1:0] store_result_ex_id;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] store_trans_id_ex_id;
  logic store_valid_ex_id;
  exception_t store_exception_ex_id;
  // MULT
  logic [CVA6Cfg.NrIssuePorts-1:0] mult_valid_id_ex;
  // FPU
  logic fpu_ready_ex_id;
  logic [CVA6Cfg.NrIssuePorts-1:0] fpu_valid_id_ex;
  logic [1:0] fpu_fmt_id_ex;
  logic [2:0] fpu_rm_id_ex;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] fpu_trans_id_ex_id;
  logic [CVA6Cfg.XLEN-1:0] fpu_result_ex_id;
  logic fpu_valid_ex_id;
  exception_t fpu_exception_ex_id;
  logic fpu_early_valid_ex_id;
  // ALU2
  logic [CVA6Cfg.NrIssuePorts-1:0] alu2_valid_id_ex;
  // Accelerator
  logic stall_acc_id;
  scoreboard_entry_t issue_instr_id_acc;
  logic issue_instr_hs_id_acc;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] acc_trans_id_ex_id;
  logic [CVA6Cfg.XLEN-1:0] acc_result_ex_id;
  logic acc_valid_ex_id;
  exception_t acc_exception_ex_id;
  logic halt_acc_ctrl;
  logic [4:0] acc_resp_fflags;
  logic acc_resp_fflags_valid;
  logic single_step_acc_commit;
  // CSR
  logic [CVA6Cfg.NrIssuePorts-1:0] csr_valid_id_ex;
  logic csr_hs_ld_st_inst_ex;
  // CVXIF
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] x_trans_id_ex_id;
  logic [CVA6Cfg.XLEN-1:0] x_result_ex_id;
  logic x_valid_ex_id;
  exception_t x_exception_ex_id;
  logic x_we_ex_id;
  logic [4:0] x_rd_ex_id;
  logic [CVA6Cfg.NrIssuePorts-1:0] x_issue_valid_id_ex;
  logic x_issue_ready_ex_id;
  logic [31:0] x_off_instr_id_ex;
  logic x_transaction_rejected;
  // --------------
  // EX <-> COMMIT
  // --------------
  // CSR Commit
  logic csr_commit_commit_ex;
  logic dirty_fp_state;
  logic dirty_v_state;
  // LSU Commit
  logic lsu_commit_commit_ex;
  logic lsu_commit_ready_ex_commit;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] lsu_commit_trans_id;
  logic stall_st_pending_ex;
  logic no_st_pending_ex;
  logic no_st_pending_commit;
  logic shared_tlb_flush_busy_ex;
  logic amo_valid_commit;
  // ACCEL Commit
  logic acc_valid_acc_ex;
  // --------------
  // EX <-> ACC_DISP
  // --------------
  acc_mmu_req_t acc_mmu_req;
  acc_mmu_resp_t acc_mmu_resp;
  // --------------
  // ID <-> COMMIT
  // --------------
  scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_id_commit;
  logic [CVA6Cfg.NrCommitPorts-1:0] commit_drop_id_commit;
  logic [CVA6Cfg.NrCommitPorts-1:0] commit_ack_commit_id;

  // --------------
  // RVFI
  // --------------
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.TRANS_ID_BITS-1:0] rvfi_issue_pointer;
  logic [CVA6Cfg.NrCommitPorts-1:0][CVA6Cfg.TRANS_ID_BITS-1:0] rvfi_commit_pointer;
  // --------------
  // COMMIT <-> ID
  // --------------
  logic [CVA6Cfg.NrCommitPorts-1:0][4:0] waddr_commit_id;
  logic [CVA6Cfg.NrCommitPorts-1:0][CVA6Cfg.XLEN-1:0] wdata_commit_id;
  logic [CVA6Cfg.NrCommitPorts-1:0] we_gpr_commit_id;
  logic [CVA6Cfg.NrCommitPorts-1:0] we_fpr_commit_id;
  // --------------
  // CSR <-> *
  // --------------
  logic [4:0] fflags_csr_commit;
  riscv::xs_t fs;
  riscv::xs_t vfs;
  logic [2:0] frm_csr_id_issue_ex;
  logic [6:0] fprec_csr_ex;
  riscv::xs_t vs;
  logic enable_translation_csr_ex;
  logic enable_g_translation_csr_ex;
  logic en_ld_st_translation_csr_ex;
  logic en_ld_st_g_translation_csr_ex;
  riscv::priv_lvl_t ld_st_priv_lvl_csr_ex;
  logic ld_st_v_csr_ex;
  logic sum_csr_ex;
  logic vs_sum_csr_ex;
  logic mxr_csr_ex;
  logic vmxr_csr_ex;
  logic [CVA6Cfg.PPNW-1:0] satp_ppn_csr_ex;
  logic [CVA6Cfg.ASID_WIDTH-1:0] asid_csr_ex;
  logic [CVA6Cfg.PPNW-1:0] vsatp_ppn_csr_ex;
  logic [CVA6Cfg.ASID_WIDTH-1:0] vs_asid_csr_ex;
  logic [CVA6Cfg.PPNW-1:0] hgatp_ppn_csr_ex;
  logic [CVA6Cfg.VMID_WIDTH-1:0] vmid_csr_ex;
  logic [11:0] csr_addr_ex_csr;
  fu_op csr_op_commit_csr;
  logic [CVA6Cfg.XLEN-1:0] csr_wdata_commit_csr;
  logic [CVA6Cfg.XLEN-1:0] csr_rdata_csr_commit;
  exception_t csr_exception_csr_commit;
  logic tvm_csr_id;
  logic tw_csr_id;
  logic vtw_csr_id;
  logic tsr_csr_id;
  logic hu;
  irq_ctrl_t irq_ctrl_csr_id;
  logic dcache_en_csr_nbdcache;
  logic csr_write_fflags_commit_cs;
  logic icache_en_csr;
  logic acc_cons_en_csr;
  logic debug_mode;
  logic single_step_csr_commit;
  riscv::pmpcfg_t [avoid_neg(CVA6Cfg.NrPMPEntries-1):0] pmpcfg;
  logic [avoid_neg(CVA6Cfg.NrPMPEntries-1):0][CVA6Cfg.PLEN-3:0] pmpaddr;
  logic [31:0] mcountinhibit_csr_perf;
  //jvt
  jvt_t jvt;
  // trigger module
  logic
      sdtrig_commit_std_exception_valid,
      sdtrig_sb_std_exception_valid,
      sdtrig_load_stall,
      sdtrig_load_cancel,
      sdtrig_store_stall;
  logic [CVA6Cfg.XLEN-1:0] sdtrig_decoder_action[CVA6Cfg.NrIssuePorts];
  logic [CVA6Cfg.XLEN-1:0] sdtrig_load_action, sdtrig_store_action, sdtrig_commit_action;
  logic [CVA6Cfg.VLEN-1:0] sdtrig_lsu_inputs_operand_a;
  logic [CVA6Cfg.XLEN-1:0] sdtrig_lsu_inputs_operand_c;
  logic sdtrig_lsu_inputs_we, sdtrig_lsu_inputs_valid;
  logic sdtrig_commit_icount_valid;
  logic [$clog2(CVA6Cfg.NrCommitPorts)-1:0] sdtrig_commit_icount_nr_instr;

  riscv::cbie_t mcbie, scbie, hcbie;
  logic mcbcfe, scbcfe, hcbcfe;
  // ----------------------------
  // Performance Counters <-> *
  // ----------------------------
  logic [11:0] addr_csr_perf;
  logic [CVA6Cfg.XLEN-1:0] data_csr_perf, data_perf_csr;
  logic we_csr_perf;

  logic icache_flush_ctrl_cache;
  logic itlb_miss_ex_perf;
  logic dtlb_miss_ex_perf;
  logic dcache_miss_cache_perf;
  logic icache_miss_cache_perf;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits;
  logic stall_issue;
  // --------------
  // CTRL <-> *
  // --------------
  logic set_pc_ctrl_pcgen;
  logic flush_csr_ctrl;
  logic flush_unissued_instr_ctrl_id;
  logic flush_ctrl_if;
  logic flush_ctrl_id;
  logic flush_ctrl_ex;
  logic flush_ctrl_bp;
  logic flush_tlb_ctrl_ex;
  logic flush_tlb_vvma_ctrl_ex;
  logic flush_tlb_gvma_ctrl_ex;
  logic fence_i_commit_controller;
  logic fence_commit_controller;
  logic sfence_vma_commit_controller;
  logic hfence_vvma_commit_controller;
  logic hfence_gvma_commit_controller;
  logic halt_ctrl;
  logic halt_frontend;
  logic halt_csr_ctrl;
  logic dcache_flush_ctrl_cache;
  logic dcache_flush_ack_cache_ctrl;
  logic set_debug_pc;
  logic flush_commit;
  logic flush_acc;

  icache_areq_t icache_areq_ex_cache;
  icache_arsp_t icache_areq_cache_ex;
  icache_dreq_t icache_dreq_if_cache;
  icache_drsp_t icache_dreq_cache_if;

  amo_req_t amo_req;
  amo_resp_t amo_resp;
  logic sb_full;

  // ----------------
  // DCache <-> *
  // ----------------
  dcache_req_i_t [2:0] dcache_req_ports_ex_cache;
  dcache_req_o_t [2:0] dcache_req_ports_cache_ex;
  dcache_req_i_t dcache_req_ports_id_cache;
  dcache_req_o_t dcache_req_ports_cache_id;
  dcache_req_i_t [1:0] dcache_req_ports_acc_cache;
  dcache_req_o_t [1:0] dcache_req_ports_cache_acc;
  logic dcache_commit_wbuffer_empty;
  logic dcache_commit_wbuffer_not_ni;

  //RVFI
  lsu_ctrl_t rvfi_lsu_ctrl;
  logic [CVA6Cfg.PLEN-1:0] rvfi_mem_paddr;
  logic [CVA6Cfg.NrIssuePorts-1:0] rvfi_is_compressed;
  rvfi_probes_csr_t rvfi_csr;

  // Accelerator port
  logic [63:0] inval_addr;
  logic inval_valid;
  logic inval_ready;

  // ==== core/cva6.sv 697-726
  frontend #(
      .CVA6Cfg(CVA6Cfg),
      .bp_resolve_t(bp_resolve_t),
      .fetch_entry_t(fetch_entry_t),
      .icache_dreq_t(icache_dreq_t),
      .icache_drsp_t(icache_drsp_t)
  ) i_frontend (
      .clk_i,
      .rst_ni,
      .boot_addr_i        (boot_addr_i[CVA6Cfg.VLEN-1:0]),
      .flush_bp_i         ((CVA6Cfg.RVU || CVA6Cfg.RVS) ? flush_ctrl_bp : 1'b0),
      // below line is not entirely correct
      .flush_i            (flush_ctrl_if),
      .halt_i             (halt_ctrl),
      .halt_frontend_i    (halt_frontend),
      .set_pc_commit_i    (set_pc_ctrl_pcgen),
      .pc_commit_i        (pc_commit),
      .ex_valid_i         (ex_commit.valid),
      .resolved_branch_i  (resolved_branch),
      .eret_i             (eret),
      .epc_i              (epc_commit_pcgen),
      .trap_vector_base_i (trap_vector_base_commit_pcgen),
      .set_debug_pc_i     (set_debug_pc),
      .debug_mode_i       (debug_mode),
      .icache_dreq_o      (icache_dreq_if_cache),
      .icache_dreq_i      (icache_dreq_cache_if),
      .fetch_entry_o      (fetch_entry_if_id),
      .fetch_entry_valid_o(fetch_valid_if_id),
      .fetch_entry_ready_i(fetch_ready_id_if)
  );

  // ==== core/cva6.sv 731-867
  id_stage #(
      .CVA6Cfg(CVA6Cfg),
      .branchpredict_sbe_t(branchpredict_sbe_t),
      .dcache_req_i_t(dcache_req_i_t),
      .dcache_req_o_t(dcache_req_o_t),
      .exception_t(exception_t),
      .fetch_entry_t(fetch_entry_t),
      .jvt_t(jvt_t),
      .irq_ctrl_t(irq_ctrl_t),
      .scoreboard_entry_t(scoreboard_entry_t),
      .interrupts_t(interrupts_t),
      .INTERRUPTS(INTERRUPTS),
      .x_compressed_req_t(x_compressed_req_t),
      .x_compressed_resp_t(x_compressed_resp_t)
  ) id_stage_i (
      .clk_i,
      .rst_ni,
      .flush_i(flush_ctrl_if),
      .debug_req_i,

      .fetch_entry_i      (fetch_entry_if_id),
      .fetch_entry_valid_i(fetch_valid_if_id),
      .fetch_entry_ready_o(fetch_ready_id_if),

      .issue_entry_o      (issue_entry_id_issue),
      .issue_entry_o_prev (issue_entry_id_issue_prev),
      .orig_instr_o       (orig_instr_id_issue),
      .issue_entry_valid_o(issue_entry_valid_id_issue),
      .is_ctrl_flow_o     (is_ctrl_fow_id_issue),
      .issue_instr_ack_i  (issue_instr_issue_id),

      .rvfi_is_compressed_o(rvfi_is_compressed),

      .priv_lvl_i             (priv_lvl),
      .v_i                    (v),
      .fs_i                   (fs),
      .vfs_i                  (vfs),
      .frm_i                  (frm_csr_id_issue_ex),
      .vs_i                   (vs),
      .irq_i                  (irq_i),
      .irq_ctrl_i             (irq_ctrl_csr_id),
      .debug_mode_i           (debug_mode),
      .tvm_i                  (tvm_csr_id),
      .tw_i                   (tw_csr_id),
      .vtw_i                  (vtw_csr_id),
      .tsr_i                  (tsr_csr_id),
      .hu_i                   (hu),
      .mcbie_i                (mcbie),
      .scbie_i                (scbie),
      .hcbie_i                (hcbie),
      .mcbcfe_i               (mcbcfe),
      .scbcfe_i               (scbcfe),
      .hcbcfe_i               (hcbcfe),
      .hart_id_i              (hart_id_i),
      .compressed_ready_i     (x_compressed_ready),
      .compressed_resp_i      (x_compressed_resp),
      .compressed_valid_o     (x_compressed_valid),
      .compressed_req_o       (x_compressed_req),
      .jvt_i                  (jvt),
      // DCACHE interfaces
      .dcache_req_ports_i     (dcache_req_ports_cache_id),
      .dcache_req_ports_o     (dcache_req_ports_id_cache),
      //Trigger Module command signal
      .sdtrig_decoder_action_i(sdtrig_decoder_action)
  );

  logic [CVA6Cfg.NrWbPorts-1:0][CVA6Cfg.TRANS_ID_BITS-1:0] trans_id_ex_id;
  logic [CVA6Cfg.NrWbPorts-1:0][CVA6Cfg.XLEN-1:0] wbdata_ex_id;
  exception_t [CVA6Cfg.NrWbPorts-1:0] ex_ex_ex_id;  // exception from execute, ex_stage to id_stage
  logic [CVA6Cfg.NrWbPorts-1:0] wt_valid_ex_id;

  assign trans_id_ex_id[FLU_WB] = flu_trans_id_ex_id;
  assign wbdata_ex_id[FLU_WB]   = flu_result_ex_id;
  assign ex_ex_ex_id[FLU_WB]    = flu_exception_ex_id;
  assign wt_valid_ex_id[FLU_WB] = flu_valid_ex_id;

  assign trans_id_ex_id[STORE_WB] = store_trans_id_ex_id;
  assign wbdata_ex_id[STORE_WB]   = store_result_ex_id;
  assign ex_ex_ex_id[STORE_WB]    = store_exception_ex_id;
  assign wt_valid_ex_id[STORE_WB] = store_valid_ex_id;

  assign trans_id_ex_id[LOAD_WB] = load_trans_id_ex_id;
  assign wbdata_ex_id[LOAD_WB]   = load_result_ex_id;
  assign ex_ex_ex_id[LOAD_WB]    = load_exception_ex_id;
  assign wt_valid_ex_id[LOAD_WB] = load_valid_ex_id;

  assign trans_id_ex_id[FPU_WB] = fpu_trans_id_ex_id;
  assign wbdata_ex_id[FPU_WB]   = fpu_result_ex_id;
  assign ex_ex_ex_id[FPU_WB]    = fpu_exception_ex_id;
  assign wt_valid_ex_id[FPU_WB] = fpu_valid_ex_id;

  if (CVA6Cfg.CvxifEn) begin
    always_comb begin : gen_cvxif_input_assignment
      x_compressed_ready = cvxif_resp_i.compressed_ready;
      x_compressed_resp  = cvxif_resp_i.compressed_resp;
      x_issue_ready      = cvxif_resp_i.issue_ready;
      x_issue_resp       = cvxif_resp_i.issue_resp;
      x_register_ready   = cvxif_resp_i.register_ready;
      x_result_valid     = cvxif_resp_i.result_valid;
      x_result           = cvxif_resp_i.result;
    end

    always_comb begin : gen_cvxif_output_assignment
      cvxif_req.compressed_valid = x_compressed_valid;
      cvxif_req.compressed_req   = x_compressed_req;
      cvxif_req.issue_valid      = x_issue_valid;
      cvxif_req.issue_req        = x_issue_req;
      cvxif_req.register_valid   = x_register_valid;
      cvxif_req.register         = x_register;
      cvxif_req.commit_valid     = x_commit_valid;
      cvxif_req.commit           = x_commit;
      cvxif_req.result_ready     = x_result_ready;
    end
    assign trans_id_ex_id[X_WB] = x_trans_id_ex_id;
    assign wbdata_ex_id[X_WB]   = x_result_ex_id;
    assign ex_ex_ex_id[X_WB]    = x_exception_ex_id;
    assign wt_valid_ex_id[X_WB] = x_valid_ex_id;
  end else if (CVA6Cfg.EnableAccelerator) begin
    assign cvxif_req = '0;
    assign trans_id_ex_id[ACC_WB] = acc_trans_id_ex_id;
    assign wbdata_ex_id[ACC_WB]   = acc_result_ex_id;
    assign ex_ex_ex_id[ACC_WB]    = acc_exception_ex_id;
    assign wt_valid_ex_id[ACC_WB] = acc_valid_ex_id;
  end else begin
    assign cvxif_req = '0;
    assign x_compressed_ready = '0;
    assign x_compressed_resp = '0;
    assign x_issue_ready = '0;
    assign x_issue_resp = '0;
    assign x_register_ready = '0;
    assign x_result_valid = '0;
    assign x_result = '0;
  end

  if (CVA6Cfg.CvxifEn && CVA6Cfg.EnableAccelerator) begin : gen_err_xif_and_acc
    $error("X-interface and accelerator port cannot be enabled at the same time.");
  end

  // ==== core/cva6.sv 872-973
  issue_stage #(
      .CVA6Cfg(CVA6Cfg),
      .bp_resolve_t(bp_resolve_t),
      .branchpredict_sbe_t(branchpredict_sbe_t),
      .exception_t(exception_t),
      .fu_data_t(fu_data_t),
      .scoreboard_entry_t(scoreboard_entry_t),
      .writeback_t(writeback_t),
      .x_issue_req_t(x_issue_req_t),
      .x_issue_resp_t(x_issue_resp_t),
      .x_register_t(x_register_t),
      .x_commit_t(x_commit_t)
  ) issue_stage_i (
      .clk_i,
      .rst_ni,
      .sb_full_o               (sb_full),
      .flush_unissued_instr_i  (flush_unissued_instr_ctrl_id),
      .flush_i                 (flush_ctrl_id),
      .stall_i                 (stall_acc_id),
      // ID Stage
      .decoded_instr_i         (issue_entry_id_issue),
      .decoded_instr_i_prev    (issue_entry_id_issue_prev),
      .orig_instr_i            (orig_instr_id_issue),
      .decoded_instr_valid_i   (issue_entry_valid_id_issue),
      .is_ctrl_flow_i          (is_ctrl_fow_id_issue),
      .decoded_instr_ack_o     (issue_instr_issue_id),
      // Functional Units
      .rs1_forwarding_o        (rs1_forwarding_id_ex),
      .rs2_forwarding_o        (rs2_forwarding_id_ex),
      .fu_data_o               (fu_data_id_ex),
      .alu_bypass_o            (alu_bypass_id_ex),
      .pc_o                    (pc_id_ex),
      .is_zcmt_o               (zcmt_id_ex),
      .is_compressed_instr_o   (is_compressed_instr_id_ex),
      .tinst_o                 (tinst_ex),
      // fixed latency unit ready
      .flu_ready_i             (flu_ready_ex_id),
      // ALU
      .alu_valid_o             (alu_valid_id_ex),
      .aes_valid_o             (aes_valid_id_ex),
      // Branches and Jumps
      .branch_valid_o          (branch_valid_id_ex),            // branch is valid
      .branch_predict_o        (branch_predict_id_ex),          // branch predict to ex
      .resolve_branch_i        (resolve_branch_ex_id),          // in order to resolve the branch
      // LSU
      .lsu_ready_i             (lsu_ready_ex_id),
      .lsu_valid_o             (lsu_valid_id_ex),
      // Multiplier
      .mult_valid_o            (mult_valid_id_ex),
      // FPU
      .fpu_ready_i             (fpu_ready_ex_id),
      .fpu_valid_o             (fpu_valid_id_ex),
      .fpu_fmt_o               (fpu_fmt_id_ex),
      .fpu_rm_o                (fpu_rm_id_ex),
      .fpu_early_valid_i       (fpu_early_valid_ex_id),
      // ALU2
      .alu2_valid_o            (alu2_valid_id_ex),
      // CSR
      .csr_valid_o             (csr_valid_id_ex),
      // CVXIF
      .xfu_valid_o             (x_issue_valid_id_ex),
      .xfu_ready_i             (x_issue_ready_ex_id),
      .x_off_instr_o           (x_off_instr_id_ex),
      .hart_id_i               (hart_id_i),
      .x_issue_ready_i         (x_issue_ready),
      .x_issue_resp_i          (x_issue_resp),
      .x_issue_valid_o         (x_issue_valid),
      .x_issue_req_o           (x_issue_req),
      .x_register_ready_i      (x_register_ready),
      .x_register_valid_o      (x_register_valid),
      .x_register_o            (x_register),
      .x_commit_valid_o        (x_commit_valid),
      .x_commit_o              (x_commit),
      .x_transaction_rejected_o(x_transaction_rejected),
      // Accelerator
      .issue_instr_o           (issue_instr_id_acc),
      .issue_instr_hs_o        (issue_instr_hs_id_acc),
      // Commit
      .trans_id_i              (trans_id_ex_id),
      .resolved_branch_i       (resolved_branch),
      .wbdata_i                (wbdata_ex_id),
      .ex_ex_i                 (ex_ex_ex_id),
      .wt_valid_i              (wt_valid_ex_id),
      .x_we_i                  (x_we_ex_id),
      .x_rd_i                  (x_rd_ex_id),

      .waddr_i              (waddr_commit_id),
      .wdata_i              (wdata_commit_id),
      .we_gpr_i             (we_gpr_commit_id),
      .we_fpr_i             (we_fpr_commit_id),
      .commit_instr_o       (commit_instr_id_commit),
      .commit_drop_o        (commit_drop_id_commit),
      .commit_ack_i         (commit_ack_commit_id),
      // Performance Counters
      .stall_issue_o        (stall_issue),
      //RVFI
      .rvfi_issue_pointer_o (rvfi_issue_pointer),
      .rvfi_commit_pointer_o(rvfi_commit_pointer),
      .rvfi_rs1_o           (rvfi_rs1),
      .rvfi_rs2_o           (rvfi_rs2),
      .orig_instr_aes_bits  (orig_instr_aes)
  );

  // ==== core/cva6.sv 978-1135
  ex_stage #(
      .CVA6Cfg   (CVA6Cfg),
      .bp_resolve_t(bp_resolve_t),
      .branchpredict_sbe_t(branchpredict_sbe_t),
      .dcache_req_i_t(dcache_req_i_t),
      .dcache_req_o_t(dcache_req_o_t),
      .exception_t(exception_t),
      .fu_data_t(fu_data_t),
      .icache_areq_t(icache_areq_t),
      .icache_arsp_t(icache_arsp_t),
      .icache_dreq_t(icache_dreq_t),
      .icache_drsp_t(icache_drsp_t),
      .lsu_ctrl_t(lsu_ctrl_t),
      .x_result_t(x_result_t),
      .acc_mmu_req_t(acc_mmu_req_t),
      .acc_mmu_resp_t(acc_mmu_resp_t),
      .cbo_t(cbo_t)
  ) ex_stage_i (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .debug_mode_i(debug_mode),
      .flush_i(flush_ctrl_ex),
      .rs1_forwarding_i(rs1_forwarding_id_ex),
      .rs2_forwarding_i(rs2_forwarding_id_ex),
      .fu_data_i(fu_data_id_ex),
      .alu_bypass_i(alu_bypass_id_ex),
      .pc_i(pc_id_ex),
      .is_zcmt_i(zcmt_id_ex),
      .is_compressed_instr_i(is_compressed_instr_id_ex),
      .tinst_i(tinst_ex),
      // fixed latency units
      .flu_result_o(flu_result_ex_id),
      .flu_trans_id_o(flu_trans_id_ex_id),
      .flu_valid_o(flu_valid_ex_id),
      .flu_exception_o(flu_exception_ex_id),
      .flu_ready_o(flu_ready_ex_id),
      // ALU
      .alu_valid_i(alu_valid_id_ex),
      .orig_instr_aes_i(orig_instr_aes),
      .aes_valid_i(aes_valid_id_ex),
      // Branches and Jumps
      .branch_valid_i(branch_valid_id_ex),
      .branch_predict_i(branch_predict_id_ex),  // branch predict to ex
      .resolved_branch_o(resolved_branch),
      .resolve_branch_o(resolve_branch_ex_id),
      // CSR
      .csr_valid_i(csr_valid_id_ex),
      .csr_addr_o(csr_addr_ex_csr),
      .csr_commit_i(csr_commit_commit_ex),  // from commit
      .csr_hs_ld_st_inst_o(csr_hs_ld_st_inst_ex),  // signals a Hypervisor Load/Store Instruction
      // MULT
      .mult_valid_i(mult_valid_id_ex),
      // LSU
      .lsu_ready_o(lsu_ready_ex_id),
      .lsu_valid_i(lsu_valid_id_ex),

      .load_result_o   (load_result_ex_id),
      .load_trans_id_o (load_trans_id_ex_id),
      .load_valid_o    (load_valid_ex_id),
      .load_exception_o(load_exception_ex_id),

      .store_result_o   (store_result_ex_id),
      .store_trans_id_o (store_trans_id_ex_id),
      .store_valid_o    (store_valid_ex_id),
      .store_exception_o(store_exception_ex_id),

      .lsu_commit_i                 (lsu_commit_commit_ex),           // from commit
      .lsu_commit_ready_o           (lsu_commit_ready_ex_commit),     // to commit
      .commit_tran_id_i             (lsu_commit_trans_id),            // from commit
      .stall_st_pending_i           (stall_st_pending_ex),
      .shared_tlb_flush_busy_o      (shared_tlb_flush_busy_ex),
      .no_st_pending_o              (no_st_pending_ex),
      // FPU
      .fpu_ready_o                  (fpu_ready_ex_id),
      .fpu_valid_i                  (fpu_valid_id_ex),
      .fpu_fmt_i                    (fpu_fmt_id_ex),
      .fpu_rm_i                     (fpu_rm_id_ex),
      .fpu_frm_i                    (frm_csr_id_issue_ex),
      .fpu_prec_i                   (fprec_csr_ex),
      .fpu_trans_id_o               (fpu_trans_id_ex_id),
      .fpu_result_o                 (fpu_result_ex_id),
      .fpu_valid_o                  (fpu_valid_ex_id),
      .fpu_exception_o              (fpu_exception_ex_id),
      .fpu_early_valid_o            (fpu_early_valid_ex_id),
      // ALU2
      .alu2_valid_i                 (alu2_valid_id_ex),
      .amo_valid_commit_i           (amo_valid_commit),
      .amo_req_o                    (amo_req),
      .amo_resp_i                   (amo_resp),
      // CoreV-X-Interface
      .x_valid_i                    (x_issue_valid_id_ex),
      .x_ready_o                    (x_issue_ready_ex_id),
      .x_off_instr_i                (x_off_instr_id_ex),
      .x_transaction_rejected_i     (x_transaction_rejected),
      .x_trans_id_o                 (x_trans_id_ex_id),
      .x_exception_o                (x_exception_ex_id),
      .x_result_o                   (x_result_ex_id),
      .x_valid_o                    (x_valid_ex_id),
      .x_we_o                       (x_we_ex_id),
      .x_rd_o                       (x_rd_ex_id),
      .x_result_valid_i             (x_result_valid),
      .x_result_i                   (x_result),
      .x_result_ready_o             (x_result_ready),
      // Accelerator
      .acc_valid_i                  (acc_valid_acc_ex),
      // Accelerator MMU access
      .acc_mmu_req_i                (acc_mmu_req),
      .acc_mmu_resp_o               (acc_mmu_resp),
      // Performance counters
      .itlb_miss_o                  (itlb_miss_ex_perf),
      .dtlb_miss_o                  (dtlb_miss_ex_perf),
      // Memory Management
      .enable_translation_i         (enable_translation_csr_ex),      // from CSR
      .enable_g_translation_i       (enable_g_translation_csr_ex),    // from CSR
      .en_ld_st_translation_i       (en_ld_st_translation_csr_ex),
      .en_ld_st_g_translation_i     (en_ld_st_g_translation_csr_ex),
      .flush_tlb_i                  (flush_tlb_ctrl_ex),
      .flush_tlb_vvma_i             (flush_tlb_vvma_ctrl_ex),
      .flush_tlb_gvma_i             (flush_tlb_gvma_ctrl_ex),
      .priv_lvl_i                   (priv_lvl),                       // from CSR
      .mbe_i                        (mbe),                            // from CSR
      .v_i                          (v),                              // from CSR
      .ld_st_priv_lvl_i             (ld_st_priv_lvl_csr_ex),          // from CSR
      .ld_st_v_i                    (ld_st_v_csr_ex),                 // from CSR
      .sum_i                        (sum_csr_ex),                     // from CSR
      .vs_sum_i                     (vs_sum_csr_ex),                  // from CSR
      .mxr_i                        (mxr_csr_ex),                     // from CSR
      .vmxr_i                       (vmxr_csr_ex),                    // from CSR
      .satp_ppn_i                   (satp_ppn_csr_ex),                // from CSR
      .asid_i                       (asid_csr_ex),                    // from CSR
      .vsatp_ppn_i                  (vsatp_ppn_csr_ex),               // from CSR
      .vs_asid_i                    (vs_asid_csr_ex),                 // from CSR
      .hgatp_ppn_i                  (hgatp_ppn_csr_ex),               // from CSR
      .vmid_i                       (vmid_csr_ex),                    // from CSR
      .icache_areq_i                (icache_areq_cache_ex),
      .icache_areq_o                (icache_areq_ex_cache),
      // DCACHE interfaces
      .dcache_req_ports_i           (dcache_req_ports_cache_ex),
      .dcache_req_ports_o           (dcache_req_ports_ex_cache),
      .dcache_wbuffer_empty_i       (dcache_commit_wbuffer_empty),
      .dcache_wbuffer_not_ni_i      (dcache_commit_wbuffer_not_ni),
      // PMP
      .pmpcfg_i                     (pmpcfg),
      .pmpaddr_i                    (pmpaddr),
      //RVFI
      .rvfi_lsu_ctrl_o              (rvfi_lsu_ctrl),
      .rvfi_mem_paddr_o             (rvfi_mem_paddr),
      //Trigger module command signals
      .sdtrig_load_stall_i          (sdtrig_load_stall),
      .sdtrig_load_cancel_i         (sdtrig_load_cancel),
      .sdtrig_load_action_i         (sdtrig_load_action),
      .sdtrig_store_stall_i         (sdtrig_store_stall),
      .sdtrig_store_action_i        (sdtrig_store_action),
      .sdtrig_lsu_inputs_operand_a_o(sdtrig_lsu_inputs_operand_a),
      .sdtrig_lsu_inputs_operand_c_o(sdtrig_lsu_inputs_operand_c),
      .sdtrig_lsu_inputs_we_o       (sdtrig_lsu_inputs_we),
      .sdtrig_lsu_inputs_valid_o    (sdtrig_lsu_inputs_valid)
  );

  // ==== core/cva6.sv 1141-1191
  // we have to make sure that the whole write buffer path is empty before
  // used e.g. for fence instructions.
  assign no_st_pending_commit = no_st_pending_ex & dcache_commit_wbuffer_empty;

  commit_stage #(
      .CVA6Cfg(CVA6Cfg),
      .exception_t(exception_t),
      .scoreboard_entry_t(scoreboard_entry_t)
  ) commit_stage_i (
      .clk_i,
      .rst_ni,
      .halt_i                             (halt_ctrl),
      .flush_dcache_i                     (dcache_flush_ctrl_cache),
      .exception_o                        (ex_commit),
      .dirty_fp_state_o                   (dirty_fp_state),
      .single_step_i                      (single_step_csr_commit || single_step_acc_commit),
      .commit_instr_i                     (commit_instr_id_commit),
      .commit_drop_i                      (commit_drop_id_commit),
      .commit_ack_o                       (commit_ack_commit_id),
      .commit_macro_ack_o                 (commit_macro_ack),
      .waddr_o                            (waddr_commit_id),
      .wdata_o                            (wdata_commit_id),
      .we_gpr_o                           (we_gpr_commit_id),
      .we_fpr_o                           (we_fpr_commit_id),
      .amo_resp_i                         (amo_resp),
      .pc_o                               (pc_commit),
      .csr_op_o                           (csr_op_commit_csr),
      .csr_wdata_o                        (csr_wdata_commit_csr),
      .csr_rdata_i                        (csr_rdata_csr_commit),
      .csr_write_fflags_o                 (csr_write_fflags_commit_cs),
      .csr_exception_i                    (csr_exception_csr_commit),
      .commit_lsu_o                       (lsu_commit_commit_ex),
      .commit_lsu_ready_i                 (lsu_commit_ready_ex_commit),
      .commit_tran_id_o                   (lsu_commit_trans_id),
      .amo_valid_commit_o                 (amo_valid_commit),
      .no_st_pending_i                    (no_st_pending_commit),
      .shared_tlb_flush_busy_i            (shared_tlb_flush_busy_ex),
      .commit_csr_o                       (csr_commit_commit_ex),
      .fence_i_o                          (fence_i_commit_controller),
      .fence_o                            (fence_commit_controller),
      .flush_commit_o                     (flush_commit),
      .sfence_vma_o                       (sfence_vma_commit_controller),
      .hfence_vvma_o                      (hfence_vvma_commit_controller),
      .hfence_gvma_o                      (hfence_gvma_commit_controller),
      .sdtrig_commit_std_exception_valid_i(sdtrig_commit_std_exception_valid),
      .sdtrig_commit_icount_valid_i       (sdtrig_commit_icount_valid),
      .sdtrig_commit_action_i             (sdtrig_commit_action),
      .sdtrig_commit_icount_nr_instr_i    (sdtrig_commit_icount_nr_instr)
  );

  assign commit_ack = commit_macro_ack & ~commit_drop_id_commit;

  // ==== core/cva6.sv 1197-1317
  //Trigger Module assignments
  logic [CVA6Cfg.NrIssuePorts-1:0][CVA6Cfg.VLEN-1:0] fetch_sdtrig_pc;
  logic [CVA6Cfg.NrIssuePorts-1:0][31:0] fetch_sdtrig_instr;
  for (genvar i = 0; i < CVA6Cfg.NrIssuePorts; ++i) begin
    assign fetch_sdtrig_pc[i] = CVA6Cfg.SdtrigMcontrol6ExecAddr ? fetch_entry_if_id[i].address : '0;
    assign fetch_sdtrig_instr[i] = CVA6Cfg.SdtrigMcontrol6ExecData ? fetch_entry_if_id[i].instruction : '0;
  end

  csr_regfile #(
      .CVA6Cfg           (CVA6Cfg),
      .exception_t       (exception_t),
      .jvt_t             (jvt_t),
      .irq_ctrl_t        (irq_ctrl_t),
      .scoreboard_entry_t(scoreboard_entry_t),
      .rvfi_probes_csr_t (rvfi_probes_csr_t),
      .MHPMCounterNum    (MHPMCounterNum)
  ) csr_regfile_i (
      .clk_i,
      .rst_ni,
      .time_irq_i,
      .flush_o                            (flush_csr_ctrl),
      .halt_csr_o                         (halt_csr_ctrl),
      .commit_instr_i                     (commit_instr_id_commit[0]),
      .commit_ack_i                       (commit_ack),
      .boot_addr_i                        (boot_addr_i[CVA6Cfg.VLEN-1:0]),
      .hart_id_i                          (hart_id_i[CVA6Cfg.XLEN-1:0]),
      .ex_i                               (ex_commit),
      .csr_op_i                           (csr_op_commit_csr),
      .csr_addr_i                         (csr_addr_ex_csr),
      .csr_wdata_i                        (csr_wdata_commit_csr),
      .csr_rdata_o                        (csr_rdata_csr_commit),
      .dirty_fp_state_i                   (dirty_fp_state),
      .csr_write_fflags_i                 (csr_write_fflags_commit_cs),
      .dirty_v_state_i                    (dirty_v_state),
      .pc_i                               (pc_commit),
      .csr_exception_o                    (csr_exception_csr_commit),
      .epc_o                              (epc_commit_pcgen),
      .eret_o                             (eret),
      .trap_vector_base_o                 (trap_vector_base_commit_pcgen),
      .priv_lvl_o                         (priv_lvl),
      .mbe_o                              (mbe),
      .v_o                                (v),
      .acc_fflags_ex_i                    (acc_resp_fflags),
      .acc_fflags_ex_valid_i              (acc_resp_fflags_valid),
      .fs_o                               (fs),
      .vfs_o                              (vfs),
      .fflags_o                           (fflags_csr_commit),
      .frm_o                              (frm_csr_id_issue_ex),
      .fprec_o                            (fprec_csr_ex),
      .vs_o                               (vs),
      .irq_ctrl_o                         (irq_ctrl_csr_id),
      .en_translation_o                   (enable_translation_csr_ex),
      .en_g_translation_o                 (enable_g_translation_csr_ex),
      .en_ld_st_translation_o             (en_ld_st_translation_csr_ex),
      .en_ld_st_g_translation_o           (en_ld_st_g_translation_csr_ex),
      .ld_st_priv_lvl_o                   (ld_st_priv_lvl_csr_ex),
      .ld_st_v_o                          (ld_st_v_csr_ex),
      .csr_hs_ld_st_inst_i                (csr_hs_ld_st_inst_ex),
      .sum_o                              (sum_csr_ex),
      .vs_sum_o                           (vs_sum_csr_ex),
      .mxr_o                              (mxr_csr_ex),
      .vmxr_o                             (vmxr_csr_ex),
      .satp_ppn_o                         (satp_ppn_csr_ex),
      .asid_o                             (asid_csr_ex),
      .vsatp_ppn_o                        (vsatp_ppn_csr_ex),
      .vs_asid_o                          (vs_asid_csr_ex),
      .hgatp_ppn_o                        (hgatp_ppn_csr_ex),
      .vmid_o                             (vmid_csr_ex),
      .irq_i,
      .ipi_i,
      .debug_req_i,
      .set_debug_pc_o                     (set_debug_pc),
      .tvm_o                              (tvm_csr_id),
      .tw_o                               (tw_csr_id),
      .vtw_o                              (vtw_csr_id),
      .tsr_o                              (tsr_csr_id),
      .hu_o                               (hu),
      .debug_mode_o                       (debug_mode),
      .single_step_o                      (single_step_csr_commit),
      .icache_en_o                        (icache_en_csr),
      .dcache_en_o                        (dcache_en_csr_nbdcache),
      .acc_cons_en_o                      (acc_cons_en_csr),
      .perf_addr_o                        (addr_csr_perf),
      .perf_data_o                        (data_csr_perf),
      .perf_data_i                        (data_perf_csr),
      .perf_we_o                          (we_csr_perf),
      .pmpcfg_o                           (pmpcfg),
      .pmpaddr_o                          (pmpaddr),
      .mcountinhibit_o                    (mcountinhibit_csr_perf),
      .mcbie_o                            (mcbie),
      .scbie_o                            (scbie),
      .hcbie_o                            (hcbie),
      .mcbcfe_o                           (mcbcfe),
      .scbcfe_o                           (scbcfe),
      .hcbcfe_o                           (hcbcfe),
      .jvt_o                              (jvt),
      //RVFI
      .rvfi_csr_o                         (rvfi_csr),
      // Trigger Signals
      .sdtrig_commit_std_exception_valid_o(sdtrig_commit_std_exception_valid),
      //Decoder/FE <-> Trigger Module
      .fetch_sdtrig_pc_i                  (fetch_sdtrig_pc),
      .fetch_sdtrig_instr_i               (fetch_sdtrig_instr),
      .sdtrig_decoder_action_o            (sdtrig_decoder_action),
      //Load/Store Unit <-> Trigger Module
      .sdtrig_lsu_inputs_vaddr_i          (sdtrig_lsu_inputs_operand_a),
      .sdtrig_lsu_inputs_data_i           (sdtrig_lsu_inputs_operand_c),
      .sdtrig_lsu_inputs_fu_i             (sdtrig_lsu_inputs_we),
      .sdtrig_lsu_inputs_valid_i          (sdtrig_lsu_inputs_valid),
      .sdtrig_load_data_i                 (load_result_ex_id),
      .sdtrig_load_valid_i                (load_valid_ex_id),
      .sdtrig_load_stall_o                (sdtrig_load_stall),
      .sdtrig_load_cancel_o               (sdtrig_load_cancel),
      .sdtrig_load_action_o               (sdtrig_load_action),
      .sdtrig_store_stall_o               (sdtrig_store_stall),
      .sdtrig_store_action_o              (sdtrig_store_action),
      //Commit <- Trigger module
      .sdtrig_commit_icount_valid_o       (sdtrig_commit_icount_valid),
      .sdtrig_commit_action_o             (sdtrig_commit_action),
      .sdtrig_commit_icount_nr_instr_o    (sdtrig_commit_icount_nr_instr)
  );

  // ==== core/cva6.sv 1369-1408
  // ------------
  controller #(
      .CVA6Cfg(CVA6Cfg),
      .bp_resolve_t(bp_resolve_t)
  ) controller_i (
      .clk_i,
      .rst_ni,
      // virtualization mode
      .v_i                   (v),
      // flush ports
      .set_pc_commit_o       (set_pc_ctrl_pcgen),
      .flush_if_o            (flush_ctrl_if),
      .flush_unissued_instr_o(flush_unissued_instr_ctrl_id),
      .flush_id_o            (flush_ctrl_id),
      .flush_ex_o            (flush_ctrl_ex),
      .flush_bp_o            (flush_ctrl_bp),
      .flush_icache_o        (icache_flush_ctrl_cache),
      .flush_dcache_o        (dcache_flush_ctrl_cache),
      .flush_dcache_ack_i    (dcache_flush_ack_cache_ctrl),
      .flush_tlb_o           (flush_tlb_ctrl_ex),
      .flush_tlb_vvma_o      (flush_tlb_vvma_ctrl_ex),
      .flush_tlb_gvma_o      (flush_tlb_gvma_ctrl_ex),
      .halt_csr_i            (halt_csr_ctrl),
      .halt_acc_i            (halt_acc_ctrl),
      .halt_frontend_o       (halt_frontend),
      .halt_o                (halt_ctrl),
      // control ports
      .eret_i                (eret),
      .ex_valid_i            (ex_commit.valid),
      .set_debug_pc_i        (set_debug_pc),
      .resolved_branch_i     (resolved_branch),
      .flush_csr_i           (flush_csr_ctrl),
      .fence_i_i             (fence_i_commit_controller),
      .fence_i               (fence_commit_controller),
      .sfence_vma_i          (sfence_vma_commit_controller),
      .hfence_vvma_i         (hfence_vvma_commit_controller),
      .hfence_gvma_i         (hfence_gvma_commit_controller),
      .flush_commit_i        (flush_commit),
      .flush_acc_i           (flush_acc)
  );
  // =========================================================================
  // The environment.  Everything from here down is task-authored.
  // =========================================================================

  // ---- the instruction cache --------------------------------------------
  cva6_fv_icache #(
      .CVA6Cfg      (CVA6Cfg),
      .icache_areq_t(icache_areq_t),
      .icache_arsp_t(icache_arsp_t),
      .icache_dreq_t(icache_dreq_t),
      .icache_drsp_t(icache_drsp_t)
  ) u_icache (
      .clk_i,
      .rst_ni,
      .dreq_i      (icache_dreq_if_cache),
      .dreq_o      (icache_dreq_cache_if),
      .areq_o      (icache_areq_cache_ex),
      .areq_i      (icache_areq_ex_cache),
      .fv_ready_i  (fv_ic_ready_i),
      .fv_resp_go_i(fv_ic_resp_go_i),
      .fv_data_i   (fv_ic_data_i)
  );

  // ---- the data cache ----------------------------------------------------
  // The port map `core/cva6.sv` builds at this configuration: port 0 is the
  // PTW's and `gen_no_mmu` ties it off, port 2 is the accelerator's and
  // RVV = 0 leaves it dead, so the model sees the load port and the store
  // port and nothing else.
  dcache_req_o_t dc_ld_rsp, dc_st_rsp;

  always_comb begin
    dcache_req_ports_cache_ex    = '0;
    dcache_req_ports_cache_ex[1] = dc_ld_rsp;
    dcache_req_ports_cache_ex[2] = dc_st_rsp;
  end
  assign dcache_req_ports_cache_id  = '0;   // ZCMT port, RVZCMT = 0
  assign dcache_req_ports_cache_acc = '0;   // accelerator ports, RVV = 0

  cva6_fv_dcache #(
      .CVA6Cfg       (CVA6Cfg),
      .dcache_req_i_t(dcache_req_i_t),
      .dcache_req_o_t(dcache_req_o_t)
  ) u_dcache (
      .clk_i,
      .rst_ni,
      .ld_req_i        (dcache_req_ports_ex_cache[1]),
      .ld_rsp_o        (dc_ld_rsp),
      .st_req_i        (dcache_req_ports_ex_cache[2]),
      .st_rsp_o        (dc_st_rsp),
      .wbuffer_empty_o (dcache_commit_wbuffer_empty),
      .wbuffer_not_ni_o(dcache_commit_wbuffer_not_ni),
      .flush_i         (dcache_flush_ctrl_cache),
      .flush_ack_o     (dcache_flush_ack_cache_ctrl),
      .fv_ld_gnt_i     (fv_dc_ld_gnt_i),
      .fv_st_gnt_i     (fv_dc_st_gnt_i),
      .fv_ld_go_i      (fv_dc_ld_go_i),
      .fv_ld_sel_i     (fv_dc_ld_sel_i),
      .fv_ld_data_i    (fv_dc_ld_data_i)
  );

  // ---- the coprocessor that implements nothing ---------------------------
  // Every handshake completes, no instruction is accepted. `cvxif_fu` turns a
  // rejected offload into an illegal-instruction exception and writes it back
  // on the X port, so no scoreboard entry can be stranded by this model.
  always_comb begin
    cvxif_resp_i                  = '0;
    cvxif_resp_i.compressed_ready = 1'b1;
    cvxif_resp_i.issue_ready      = 1'b1;
    cvxif_resp_i.register_ready   = 1'b1;
  end

  // ---- the blocks that are not in the cut --------------------------------
  assign stall_acc_id           = 1'b0;
  assign halt_acc_ctrl          = 1'b0;
  assign flush_acc              = 1'b0;
  assign dirty_v_state          = 1'b0;
  assign single_step_acc_commit = 1'b0;
  assign acc_valid_acc_ex       = 1'b0;
  assign acc_resp_fflags        = '0;
  assign acc_resp_fflags_valid  = 1'b0;
  assign acc_mmu_req            = '0;
  assign amo_resp               = '0;      // RVA = 0, no atomics are issued
  assign data_perf_csr          = '0;      // PerfCounterEn = 0
  assign inval_valid            = 1'b0;
  assign inval_addr             = '0;

endmodule
