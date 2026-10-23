// ---------------------------------------------------------------------------
// cva6_pipe_fv_pkg -- TASK-AUTHORED.
//
// `core/cva6.sv` declares the pipeline's interface record types as
// `localparam type` entries in its OWN parameter list and hands them to every
// stage.  This package is not part of the cut (the cut starts at `frontend`
// and ends at `commit_stage`), so the types have to be restated somewhere the
// formal top can see them.  Every typedef below is field for field the one in
// `core/cva6.sv`, lines 36-230, at the configuration fixed here.
//
// The configuration is upstream `cv32a65x_config_pkg::cva6_cfg`, UNCHANGED --
// no field is overridden.  What that buys, read out of build_config_pkg:
//
//   XLEN 32, VLEN 32, PLEN 34            RV32
//   SuperscalarEn 1 -> NrIssuePorts 2, NrCommitPorts 2, NrALUs 2,
//                      SpeculativeSb 1, NrRgprPorts 4,
//                      FETCH_WIDTH 64, INSTR_PER_FETCH 4
//   NR_SB_ENTRIES 8, TRANS_ID_BITS 3     8-entry out-of-order scoreboard
//   NrWbPorts 5 (CvxifEn=1)              FLU / STORE / LOAD / FPU(unused) / X
//   NrLoadBufEntries 2, DcacheIdWidth 1  two outstanding loads
//   MaxOutstandingStores 7
//   MmuPresent 0, RVF/RVD 0, RVA 0, ZKN 0, RVZCMT 0, RVZCMP 0, RVV 0,
//   RVS 0, RVU 0, DebugEn 0, Sdtrig 0, PerfCounterEn 0
//   RVC 1, RVB 1, RVZCB 1                compressed + bitmanip decode
//   BHTEntries 32, BHTHist 3, RASDepth 2, BTBEntries 0
//
// The scoreboard depth and the issue/commit width are the two numbers this
// package exists for: 8 entries, 2 issue ports and 2 commit ports is a real
// out-of-order window with in-order retirement, and every ordering target
// here is stated across it.  See PROVENANCE.md for the vacuity argument.
// ---------------------------------------------------------------------------
`include "rvfi_types.svh"
`include "cvxif_types.svh"

package cva6_pipe_fv_pkg;

  import ariane_pkg::*;

  localparam config_pkg::cva6_cfg_t Cfg = build_config_pkg::build_config(
      cva6_config_pkg::cva6_cfg
  );

  // ---- IF/ID ------------------------------------------------------------
  typedef struct packed {
    cf_t               cf;               // type of control flow prediction
    logic [Cfg.VLEN-1:0] predict_address;
  } branchpredict_sbe_t;

  typedef struct packed {
    logic [Cfg.XLEN-1:0]  cause;
    logic [Cfg.XLEN-1:0]  tval;
    logic [Cfg.GPLEN-1:0] tval2;
    logic [31:0]          tinst;
    logic                 gva;
    logic                 valid;
    logic                 timing;
  } exception_t;

  typedef struct packed {
    logic                fetch_valid;
    logic [Cfg.PLEN-1:0] fetch_paddr;
    exception_t          fetch_exception;
  } icache_areq_t;

  typedef struct packed {
    logic                fetch_req;
    logic [Cfg.VLEN-1:0] fetch_vaddr;
  } icache_arsp_t;

  typedef struct packed {
    logic                req;
    logic                kill_s1;
    logic                kill_s2;
    logic                spec;
    logic [Cfg.VLEN-1:0] vaddr;
  } icache_dreq_t;

  typedef struct packed {
    logic                            ready;
    logic                            valid;
    logic [Cfg.FETCH_WIDTH-1:0]      data;
    logic [Cfg.FETCH_USER_WIDTH-1:0] user;
    logic [Cfg.VLEN-1:0]             vaddr;
    exception_t                      ex;
  } icache_drsp_t;

  typedef struct packed {
    logic [Cfg.VLEN-1:0] address;
    logic [31:0]         instruction;
    branchpredict_sbe_t  branch_predict;
    exception_t          ex;
  } fetch_entry_t;

  typedef struct packed {
    logic [Cfg.XLEN-7:0] base;
    logic [5:0]          mode;
  } jvt_t;

  // ---- ID/EX/WB ---------------------------------------------------------
  typedef struct packed {
    logic [Cfg.VLEN-1:0]           pc;
    logic [Cfg.TRANS_ID_BITS-1:0]  trans_id;
    fu_t                           fu;
    fu_op                          op;
    logic [REG_ADDR_SIZE-1:0]      rs1;
    logic [REG_ADDR_SIZE-1:0]      rs2;
    logic [REG_ADDR_SIZE-1:0]      rd;
    logic [Cfg.XLEN-1:0]           result;
    logic                          valid;
    logic                          use_imm;
    logic                          use_zimm;
    logic                          use_pc;
    exception_t                    ex;
    branchpredict_sbe_t            bp;
    logic                          is_compressed;
    logic                          is_macro_instr;
    logic                          is_last_macro_instr;
    logic                          is_double_rd_macro_instr;
    logic                          vfp;
    logic                          is_zcmt;
  } scoreboard_entry_t;

  typedef struct packed {
    logic                         valid;
    logic [Cfg.XLEN-1:0]          data;
    logic                         ex_valid;
    logic [Cfg.TRANS_ID_BITS-1:0] trans_id;
  } writeback_t;

  typedef struct packed {
    logic                valid;
    logic [Cfg.VLEN-1:0] pc;
    logic [Cfg.VLEN-1:0] target_address;
    logic                is_mispredict;
    logic                is_taken;
    cf_t                 cf_type;
  } bp_resolve_t;

  typedef struct packed {
    logic [Cfg.XLEN-1:0] mie;
    logic [Cfg.XLEN-1:0] mip;
    logic [Cfg.XLEN-1:0] mideleg;
    logic [Cfg.XLEN-1:0] hideleg;
    logic                sie;
    logic                global_enable;
  } irq_ctrl_t;

  typedef struct packed {
    logic                         valid;
    logic [Cfg.VLEN-1:0]          vaddr;
    logic [31:0]                  tinst;
    logic                         hs_ld_st_inst;
    logic                         hlvx_inst;
    logic                         overflow;
    logic                         g_overflow;
    logic [Cfg.XLEN-1:0]          data;
    logic [(Cfg.XLEN/8)-1:0]      be;
    fu_t                          fu;
    fu_op                         operation;
    logic [Cfg.TRANS_ID_BITS-1:0] trans_id;
    logic                         is_speculative_load;
    logic                         is_speculative_load_miss;
  } lsu_ctrl_t;

  typedef logic [7:0] cbo_t;

  typedef struct packed {
    fu_t                          fu;
    fu_op                         operation;
    logic [Cfg.XLEN-1:0]          operand_a;
    logic [Cfg.XLEN-1:0]          operand_b;
    logic [Cfg.XLEN-1:0]          imm;
    logic [Cfg.TRANS_ID_BITS-1:0] trans_id;
  } fu_data_t;

  // ---- D$ request records ------------------------------------------------
  typedef struct packed {
    logic [Cfg.DCACHE_INDEX_WIDTH-1:0] address_index;
    logic [Cfg.DCACHE_TAG_WIDTH-1:0]   address_tag;
    logic [Cfg.XLEN-1:0]               data_wdata;
    logic [Cfg.DCACHE_USER_WIDTH-1:0]  data_wuser;
    logic                              data_req;
    logic                              data_we;
    logic [(Cfg.XLEN/8)-1:0]           data_be;
    logic [1:0]                        data_size;
    logic [Cfg.DcacheIdWidth-1:0]      data_id;
    logic                              kill_req;
    logic                              tag_valid;
    cbo_t                              cbo_op;
  } dcache_req_i_t;

  typedef struct packed {
    logic                             data_gnt;
    logic                             data_rvalid;
    logic [Cfg.DcacheIdWidth-1:0]     data_rid;
    logic [Cfg.XLEN-1:0]              data_rdata;
    logic [Cfg.DCACHE_USER_WIDTH-1:0] data_ruser;
  } dcache_req_o_t;

  // ---- RVFI probe records (csr_regfile takes rvfi_probes_csr_t) ----------
  typedef `RVFI_PROBES_INSTR_T(Cfg) rvfi_probes_instr_t;
  typedef `RVFI_PROBES_CSR_T(Cfg) rvfi_probes_csr_t;

  // ---- CVXIF -------------------------------------------------------------
  typedef `READREGFLAGS_T(Cfg) readregflags_t;
  typedef `WRITEREGFLAGS_T(Cfg) writeregflags_t;
  typedef `ID_T(Cfg) id_t;
  typedef `HARTID_T(Cfg) hartid_t;
  typedef `X_COMPRESSED_REQ_T(Cfg, hartid_t) x_compressed_req_t;
  typedef `X_COMPRESSED_RESP_T(Cfg) x_compressed_resp_t;
  typedef `X_ISSUE_REQ_T(Cfg, hartid_t, id_t) x_issue_req_t;
  typedef `X_ISSUE_RESP_T(Cfg, writeregflags_t, readregflags_t) x_issue_resp_t;
  typedef `X_REGISTER_T(Cfg, hartid_t, id_t, readregflags_t) x_register_t;
  typedef `X_COMMIT_T(Cfg, hartid_t, id_t) x_commit_t;
  typedef `X_RESULT_T(Cfg, hartid_t, id_t, writeregflags_t) x_result_t;
  typedef `CVXIF_REQ_T(Cfg, x_compressed_req_t, x_issue_req_t, x_register_t, x_commit_t)
      cvxif_req_t;
  typedef `CVXIF_RESP_T(Cfg, x_compressed_resp_t, x_issue_resp_t, x_result_t) cvxif_resp_t;

endpackage
