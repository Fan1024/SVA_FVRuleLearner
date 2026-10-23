// ---------------------------------------------------------------------------
// cva6_fv_dcache -- TASK-AUTHORED data-cache model.
//
// Stands where the cache subsystem stands in `core/cva6.sv`, on the two
// dcache ports this configuration actually drives:
//
//   port 1  the load unit          request / grant / rvalid, tagged by data_id
//   port 3  the store buffer       request / grant, no response
//
// (port 0 is the PTW's and `load_store_unit`'s `gen_no_mmu` ties it off with
// `MmuPresent = 0`; port 2 is the accelerator's and `RVV = 0` leaves it dead.)
//
// The one rule this model MUST keep, read out of `load_unit.sv`: an entry of
// the load buffer is allocated by `data_req & data_gnt` and freed ONLY by an
// `data_rvalid` carrying its `data_rid` -- `kill_req` does not free it, it
// only marks it flushed.  So every granted load is answered exactly once,
// even a killed one.  A model that dropped killed loads would wedge the LSU
// after two kills for a reason that is the environment's.
//
// Responses may come back in EITHER order (`fv_ld_sel_i` picks), which is what
// a real write-through cache does when one load hits and the other misses.
// Read data is a free input, so nothing about a loaded value is predictable
// from its address.  Grants and responses are bounded: after MAX_WAIT
// consecutive refusals the model must grant, and a load outstanding for
// MAX_WAIT cycles must be answered.
// ---------------------------------------------------------------------------
module cva6_fv_dcache #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type dcache_req_i_t = logic,
    parameter type dcache_req_o_t = logic,
    parameter int unsigned MAX_WAIT = 8
) (
    input logic clk_i,
    input logic rst_ni,
    // load port
    input  dcache_req_i_t ld_req_i,
    output dcache_req_o_t ld_rsp_o,
    // store port
    input  dcache_req_i_t st_req_i,
    output dcache_req_o_t st_rsp_o,
    // cache-level handshakes the commit path and the controller wait on
    output logic wbuffer_empty_o,
    output logic wbuffer_not_ni_o,
    input  logic flush_i,
    output logic flush_ack_o,
    // free environment choices, unconstrained inputs of the formal top
    input logic                      fv_ld_gnt_i,
    input logic                      fv_st_gnt_i,
    input logic                      fv_ld_go_i,
    input logic                      fv_ld_sel_i,
    input logic [CVA6Cfg.XLEN-1:0]   fv_ld_data_i
);

  localparam int unsigned NLD = CVA6Cfg.NrLoadBufEntries;
  localparam int unsigned IDW = CVA6Cfg.DcacheIdWidth;

  logic [NLD-1:0] pend_q;
  logic [$clog2(MAX_WAIT+1)-1:0] ld_gnt_wait_q, st_gnt_wait_q, ld_rsp_wait_q;

  logic ld_gnt, st_gnt, ld_rvalid;
  logic [IDW-1:0] ld_rid;
  logic sel_ok;

  // ---- grants ------------------------------------------------------------
  assign ld_gnt = ld_req_i.data_req & (fv_ld_gnt_i | (ld_gnt_wait_q >= MAX_WAIT));
  assign st_gnt = st_req_i.data_req & (fv_st_gnt_i | (st_gnt_wait_q >= MAX_WAIT));

  // ---- which outstanding load to answer -----------------------------------
  // free choice when that slot is outstanding, otherwise the lowest one.
  assign sel_ok = pend_q[fv_ld_sel_i];

  always_comb begin
    ld_rid = '0;
    if (sel_ok) begin
      ld_rid = IDW'(fv_ld_sel_i);
    end else begin
      for (int unsigned k = NLD; k > 0; k--) begin
        if (pend_q[k-1]) ld_rid = IDW'(k - 1);
      end
    end
  end

  assign ld_rvalid = (|pend_q) & (fv_ld_go_i | (ld_rsp_wait_q >= MAX_WAIT));

  always_comb begin
    ld_rsp_o             = '0;
    ld_rsp_o.data_gnt    = ld_gnt;
    ld_rsp_o.data_rvalid = ld_rvalid;
    ld_rsp_o.data_rid    = ld_rid;
    ld_rsp_o.data_rdata  = fv_ld_data_i;
    ld_rsp_o.data_ruser  = '0;

    st_rsp_o             = '0;
    st_rsp_o.data_gnt    = st_gnt;
  end

  // no write buffer in the model: a store is retired the cycle it is granted,
  // so the fence path never waits on one.
  assign wbuffer_empty_o  = 1'b1;
  assign wbuffer_not_ni_o = 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pend_q        <= '0;
      ld_gnt_wait_q <= '0;
      st_gnt_wait_q <= '0;
      ld_rsp_wait_q <= '0;
      flush_ack_o   <= 1'b0;
    end else begin
      if (ld_rvalid) pend_q[ld_rid] <= 1'b0;
      if (ld_gnt) pend_q[ld_req_i.data_id[$clog2(NLD)-1:0]] <= 1'b1;

      if (ld_req_i.data_req && !ld_gnt) ld_gnt_wait_q <= ld_gnt_wait_q + 1'b1;
      else ld_gnt_wait_q <= '0;
      if (st_req_i.data_req && !st_gnt) st_gnt_wait_q <= st_gnt_wait_q + 1'b1;
      else st_gnt_wait_q <= '0;
      if ((|pend_q) && !ld_rvalid) ld_rsp_wait_q <= ld_rsp_wait_q + 1'b1;
      else ld_rsp_wait_q <= '0;

      flush_ack_o <= flush_i;
    end
  end

endmodule
