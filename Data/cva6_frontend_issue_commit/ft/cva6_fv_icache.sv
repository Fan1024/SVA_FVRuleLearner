// ---------------------------------------------------------------------------
// cva6_fv_icache -- TASK-AUTHORED instruction-cache model.
//
// The cut ends at the frontend's icache port, so this stands where
// `cva6_icache` stands in `core/cva6.sv`.  It is a LEGALITY model, not a
// cache: it holds ONE outstanding fetch, answers it with a free 64-bit word
// (so every instruction encoding the decoder can see is reachable), and obeys
// the two rules the frontend depends on:
//
//   * a response carries the vaddr of the request it answers, so the frontend
//     can align and realign it;
//   * `kill_s1` withdraws the request being issued this cycle and `kill_s2`
//     withdraws the one already accepted -- neither is ever answered.
//
// It also drives the address-translation handshake the real icache drives:
// `areq_o.fetch_req` / `fetch_vaddr` out, `areq_i.fetch_paddr` /
// `fetch_exception` back.  With `MmuPresent = 0` that path is a wire through
// `load_store_unit`'s `gen_no_mmu` and `pmp_data_if`, so a PMP denial DOES
// reach the frontend as an instruction access fault, which is the behaviour
// the real icache has.
//
// BOUNDED LATENCY IS A PROPERTY OF THIS MODEL, not an assumption bolted onto
// a target: a fetch source that may refuse for ever makes every bounded
// response and deadlock statement above it false for a reason that is the
// environment's.  `ready` is forced after MAX_WAIT consecutive refusals and a
// pending fetch is answered after MAX_WAIT cycles.  No assumption is declared
// anywhere in this package.
// ---------------------------------------------------------------------------
module cva6_fv_icache #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type icache_areq_t = logic,
    parameter type icache_arsp_t = logic,
    parameter type icache_dreq_t = logic,
    parameter type icache_drsp_t = logic,
    parameter int unsigned MAX_WAIT = 8
) (
    input logic clk_i,
    input logic rst_ni,
    // frontend side
    input  icache_dreq_t dreq_i,
    output icache_drsp_t dreq_o,
    // translation side (to the LSU's MMU / PMP)
    output icache_arsp_t areq_o,
    input  icache_areq_t areq_i,
    // free environment choices, unconstrained inputs of the formal top
    input logic                             fv_ready_i,
    input logic                             fv_resp_go_i,
    input logic [CVA6Cfg.FETCH_WIDTH-1:0]   fv_data_i
);

  logic                    pending_q;
  logic [CVA6Cfg.VLEN-1:0] vaddr_q;
  logic [$clog2(MAX_WAIT+1)-1:0] rdy_wait_q, rsp_wait_q;

  logic ready, accept, kill_pending, respond;

  // refusal is bounded: after MAX_WAIT consecutive cycles of holding `ready`
  // low while the frontend asks, the model must accept.
  assign ready        = ~pending_q & (fv_ready_i | (rdy_wait_q >= MAX_WAIT));
  assign accept       = dreq_i.req & ready & ~dreq_i.kill_s1;
  assign kill_pending = pending_q & (dreq_i.kill_s2 | dreq_i.kill_s1);
  assign respond      = pending_q & ~kill_pending
                        & (fv_resp_go_i | (rsp_wait_q >= MAX_WAIT));

  always_comb begin
    dreq_o       = '0;
    dreq_o.ready = ready;
    dreq_o.valid = respond;
    dreq_o.data  = fv_data_i;
    dreq_o.user  = '0;
    dreq_o.vaddr = vaddr_q;
    dreq_o.ex    = areq_i.fetch_exception;
  end

  // the translation request the real icache raises for the fetch it holds
  always_comb begin
    areq_o             = '0;
    areq_o.fetch_req   = pending_q;
    areq_o.fetch_vaddr = vaddr_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q  <= 1'b0;
      vaddr_q    <= '0;
      rdy_wait_q <= '0;
      rsp_wait_q <= '0;
    end else begin
      if (kill_pending) begin
        pending_q <= 1'b0;
      end else if (respond) begin
        pending_q <= 1'b0;
      end
      if (accept) begin
        pending_q <= 1'b1;
        vaddr_q   <= dreq_i.vaddr;
      end

      if (dreq_i.req && !ready) rdy_wait_q <= rdy_wait_q + 1'b1;
      else rdy_wait_q <= '0;

      if (pending_q && !respond && !kill_pending) rsp_wait_q <= rsp_wait_q + 1'b1;
      else rsp_wait_q <= '0;
    end
  end

endmodule
