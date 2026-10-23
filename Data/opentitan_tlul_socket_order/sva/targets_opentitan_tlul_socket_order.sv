// ===========================================================================
// Candidate target assertions for the OpenTitan TL-UL 1:N socket block.
//
//     one host -> tlul_socket_1n (N=4, six depth-4 FIFOs, every one of them in
//     pass-through mode) -> four in-order responders
//
// Bound into `testbench`, so every reference below is an absolute hierarchical
// name from the formal top. Nothing here is an assumption, and every property
// here is a concurrent `assert property` -- the package's own target
// (T_TLUL_SOCKET_RESPONSE_ORDER) is a labelled IMMEDIATE assertion inside
// `ft/tb.sv` and is deliberately left in that form.
//
// THE ORACLES ARE INDEPENDENT of the design's bookkeeping AND of the formal
// top's own reference queue (`ref_source` / `ref_data` / `ref_*_pointer`).
// Four of them:
//
//   A  a 32-entry TRANSACTION RING written once per accepted host request,
//      carrying the source, the device the host asked for, and this file's own
//      arithmetic for the word the addressed responder owes
//      (data ^ address ^ device).  Three read pointers walk that one ring:
//        f_ptr  the request handed to a responder,
//        g_ptr  the word a responder handed back,
//        r_ptr  the response delivered to the host.
//      Order is therefore this file's claim that the single host stream stays
//      one FIFO stream at three separate boundaries, not a restatement of any
//      pointer inside the socket.
//
//   B  SEGMENT COUNTERS n_wf / n_fg / n_gr for the three ring segments, and
//      n_all for the whole ring, each an up/down counter of boundary events.
//      They are what the conservation and occupancy targets compare against
//      the socket's own `num_req_outstanding` and its FIFOs' `depth_o`.
//
//   C  a PER-DEVICE OUTSTANDING counter, incremented when a responder accepts
//      a request and decremented when it answers.  The socket must stall a
//      request aimed at a new device until every earlier response has come
//      back, so at most one of the four may be non-zero: that is the
//      mutual-exclusion family below, and it is not read out of
//      `dev_select_outstanding` or `hold_all_requests`.
//
//   D  SATURATING WAIT counters.  That is how a bounded-response or a
//      deadlock-freedom obligation is written as a safety property; there is
//      no `s_eventually` in this file and there must not be, because the reset
//      cut makes liveness vacuous.  `response_ready` is a free input of this
//      package and no assumption may be added, so every wait counter here is
//      cleared whenever `response_ready` is low: the bound asserted is a bound
//      on progress WHILE THE HOST IS TAKING RESPONSES, which is the strongest
//      form this environment admits.
//
// Every FIFO in this package is in pass-through mode, so a request can cross
// from the host boundary to a responder in one cycle and a word can cross from
// a responder to the host in one cycle. The `*_live` wires below are what makes
// the ring comparisons correct in that case, and getting it wrong is the
// mistake this file is most exposed to.
//
// Encodings transcribed rather than imported, so a comparison here is a
// statement about the wire: tlul_pkg::AccessAckData == 3'h1, and the host
// always issues a_size == 2 (TL_SZW is 2 bits wide).
// ===========================================================================

`default_nettype none

module tlul_socket_targets (input wire clk, input wire rst);

  localparam int unsigned RD = 32;   // ring depth; larger than any reachable
                                     // number of outstanding host requests

  // ------------------------------------------------------------ host boundary
  wire        h_av    = testbench.host_to_socket.a_valid;
  wire        h_ar    = testbench.socket_to_host.a_ready;
  wire [7:0]  h_asrc  = testbench.host_to_socket.a_source;
  wire [31:0] h_aaddr = testbench.host_to_socket.a_address;
  wire [31:0] h_adata = testbench.host_to_socket.a_data;
  wire [1:0]  h_adev  = testbench.request_device;

  wire        h_dv    = testbench.socket_to_host.d_valid;
  wire        h_dr    = testbench.host_to_socket.d_ready;
  wire [7:0]  h_dsrc  = testbench.socket_to_host.d_source;
  wire [31:0] h_ddata = testbench.socket_to_host.d_data;
  wire [1:0]  h_dsize = testbench.socket_to_host.d_size;
  wire [2:0]  h_dop   = testbench.socket_to_host.d_opcode;
  wire        h_derr  = testbench.socket_to_host.d_error;

  wire        h_rdy_in = testbench.response_ready;

  // ---------------------------------------------------------- device boundary
  wire [3:0]   d_av, d_ar, d_dv, d_dr;
  wire [7:0]   d_asrc  [0:3];
  wire [31:0]  d_aaddr [0:3];
  wire [31:0]  d_adata [0:3];
  wire [7:0]   d_dsrc  [0:3];
  wire [31:0]  d_ddata [0:3];
  wire [2:0]   d_cnt   [0:3];   // the responder's own occupancy
  wire [2:0]   dq_req  [0:3];   // device request FIFO depth
  wire [2:0]   dq_rsp  [0:3];   // device response FIFO depth

  genvar gi;
  generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : g_dev
      assign d_av[gi]    = testbench.socket_to_device[gi].a_valid;
      assign d_ar[gi]    = testbench.device_to_socket[gi].a_ready;
      assign d_dv[gi]    = testbench.device_to_socket[gi].d_valid;
      assign d_dr[gi]    = testbench.socket_to_device[gi].d_ready;
      assign d_asrc[gi]  = testbench.socket_to_device[gi].a_source;
      assign d_aaddr[gi] = testbench.socket_to_device[gi].a_address;
      assign d_adata[gi] = testbench.socket_to_device[gi].a_data;
      assign d_dsrc[gi]  = testbench.device_to_socket[gi].d_source;
      assign d_ddata[gi] = testbench.device_to_socket[gi].d_data;
      assign d_cnt[gi]   = testbench.G_DEVICE[gi].responder.count;
      assign dq_req[gi]  =
        testbench.dut.gen_dfifo[gi].fifo_d.reqfifo.gen_normal_fifo.u_fifo_cnt.depth_o;
      assign dq_rsp[gi]  =
        testbench.dut.gen_dfifo[gi].fifo_d.rspfifo.gen_normal_fifo.u_fifo_cnt.depth_o;
    end
  endgenerate

  // ------------------------------------------------------- socket's own state
  wire [8:0] nout   = testbench.dut.num_req_outstanding;
  wire [1:0] dsel_o = testbench.dut.dev_select_outstanding;
  wire       hold   = testbench.dut.hold_all_requests;
  wire [2:0] hq     =
    testbench.dut.fifo_h.reqfifo.gen_normal_fifo.u_fifo_cnt.depth_o;
  wire [2:0] hp     =
    testbench.dut.fifo_h.rspfifo.gen_normal_fifo.u_fifo_cnt.depth_o;

  // ------------------------------------------------------------------- events
  wire       ev_hpush = h_av && h_ar;
  wire       ev_hpop  = h_dv && h_dr;
  wire [3:0] ev_dpush = d_av & d_ar;
  wire [3:0] ev_dpop  = d_dv & d_dr;
  wire       ev_dpush_any = |ev_dpush;
  wire       ev_dpop_any  = |ev_dpop;

  // the device a forwarded request went to / a returned word came from. Only
  // meaningful when the matching event fires, and the uniqueness family below
  // is what says this priority encoder cannot be hiding a second event.
  wire [1:0] fdev = ev_dpush[1] ? 2'd1 : ev_dpush[2] ? 2'd2 :
                    ev_dpush[3] ? 2'd3 : 2'd0;
  wire [1:0] gdev = ev_dpop[1]  ? 2'd1 : ev_dpop[2]  ? 2'd2 :
                    ev_dpop[3]  ? 2'd3 : 2'd0;

  // ================================================================ ORACLE A
  // one ring, written at the host, read at three boundaries downstream.
  // ========================================================================
  reg [7:0]  q_src [0:RD-1];
  reg [31:0] q_dat [0:RD-1];
  reg [1:0]  q_dev [0:RD-1];
  reg [4:0]  w_ptr, f_ptr, g_ptr, r_ptr;

  // ================================================================ ORACLE B
  reg [5:0] n_all;   // accepted at the host, not yet answered to the host
  reg [5:0] n_wf;    // accepted at the host, not yet handed to a responder
  reg [5:0] n_fg;    // handed to a responder, not yet answered by it
  reg [5:0] n_gr;    // answered by a responder, not yet given to the host

  // ================================================================ ORACLE C
  reg [3:0] dcnt [0:3];

  // ================================================================ ORACLE D
  reg [6:0] w_hreq;    // host request stalled while the host takes responses
  reg [6:0] w_hrsp;    // work outstanding and no response, host taking them
  reg [6:0] w_prog;    // no boundary event at all, host taking responses
  reg [6:0] w_dev;     // a responder owes a word and nothing comes back
  reg [6:0] w_hold;    // the device-switch stall is asserted

  reg rst_q;
  wire first = rst_q && !rst;

  // A request accepted at the host and handed to a responder in the SAME cycle
  // has not been written into the ring yet, so the entry the forward pointer
  // names is the live host request.
  wire        f_live = (n_wf == 6'd0) && ev_hpush;
  wire [7:0]  f_src  = f_live ? h_asrc : q_src[f_ptr];
  wire [31:0] f_dat  = f_live ? (h_adata ^ h_aaddr ^ {30'd0, h_adev})
                              : q_dat[f_ptr];
  wire [1:0]  f_dev  = f_live ? h_adev : q_dev[f_ptr];

  integer k;

  always @(posedge clk) begin
    rst_q <= rst;
    if (rst) begin
      w_ptr <= 5'd0; f_ptr <= 5'd0; g_ptr <= 5'd0; r_ptr <= 5'd0;
      n_all <= 6'd0; n_wf <= 6'd0; n_fg <= 6'd0; n_gr <= 6'd0;
      w_hreq <= 7'd0; w_hrsp <= 7'd0; w_prog <= 7'd0;
      w_dev <= 7'd0; w_hold <= 7'd0;
      for (k = 0; k < 4; k = k + 1) dcnt[k] <= 4'd0;
    end else begin
      if (ev_hpush) begin
        q_src[w_ptr] <= h_asrc;
        q_dat[w_ptr] <= h_adata ^ h_aaddr ^ {30'd0, h_adev};
        q_dev[w_ptr] <= h_adev;
        w_ptr <= w_ptr + 5'd1;
      end
      if (ev_dpush_any) f_ptr <= f_ptr + 5'd1;
      if (ev_dpop_any)  g_ptr <= g_ptr + 5'd1;
      if (ev_hpop)      r_ptr <= r_ptr + 5'd1;

      case ({ev_hpush, ev_hpop})
        2'b10: n_all <= n_all + 6'd1;
        2'b01: n_all <= n_all - 6'd1;
        default: n_all <= n_all;
      endcase
      case ({ev_hpush, ev_dpush_any})
        2'b10: n_wf <= n_wf + 6'd1;
        2'b01: n_wf <= n_wf - 6'd1;
        default: n_wf <= n_wf;
      endcase
      case ({ev_dpush_any, ev_dpop_any})
        2'b10: n_fg <= n_fg + 6'd1;
        2'b01: n_fg <= n_fg - 6'd1;
        default: n_fg <= n_fg;
      endcase
      case ({ev_dpop_any, ev_hpop})
        2'b10: n_gr <= n_gr + 6'd1;
        2'b01: n_gr <= n_gr - 6'd1;
        default: n_gr <= n_gr;
      endcase

      for (k = 0; k < 4; k = k + 1) begin
        case ({ev_dpush[k], ev_dpop[k]})
          2'b10: dcnt[k] <= dcnt[k] + 4'd1;
          2'b01: dcnt[k] <= dcnt[k] - 4'd1;
          default: dcnt[k] <= dcnt[k];
        endcase
      end

      // saturating waits. Cleared whenever the host stops taking responses,
      // because `response_ready` is free and an unconditional bound would be
      // false rather than hard.
      if (!h_rdy_in || !h_av || h_ar) w_hreq <= 7'd0;
      else if (w_hreq != 7'h7f)       w_hreq <= w_hreq + 7'd1;

      if (!h_rdy_in || n_all == 6'd0 || ev_hpop) w_hrsp <= 7'd0;
      else if (w_hrsp != 7'h7f)                  w_hrsp <= w_hrsp + 7'd1;

      if (!h_rdy_in || (n_all == 6'd0 && !h_av) || ev_hpush || ev_hpop ||
          ev_dpush_any || ev_dpop_any)  w_prog <= 7'd0;
      else if (w_prog != 7'h7f)         w_prog <= w_prog + 7'd1;

      if (!h_rdy_in || n_fg == 6'd0 || ev_dpop_any) w_dev <= 7'd0;
      else if (w_dev != 7'h7f)                      w_dev <= w_dev + 7'd1;

      if (!h_rdy_in || !hold)     w_hold <= 7'd0;
      else if (w_hold != 7'h7f)   w_hold <= w_hold + 7'd1;
    end
  end

  // =======================================================================
  // 1 -- END-TO-END ORDERING
  // =======================================================================
  // The response the host is offered is the head of the ring: the oldest
  // request it accepted and has not yet been answered for.
  T_ORDER_HOST_RESPONSE_SOURCE_IS_RING_HEAD: assert property (@(posedge clk) disable iff (rst) (h_dv && n_all != 6'd0) |-> (h_dsrc == q_src[r_ptr]));

  // The request a responder accepts is the ring entry at the forward pointer,
  // and it went to the device the host named for that entry.
  T_ORDER_DEVICE_REQUEST_IS_RING_ENTRY: assert property (@(posedge clk) disable iff (rst) ev_dpush_any |-> (d_asrc[fdev] == f_src && fdev == f_dev));

  // The word a responder hands back is the ring entry at the answer pointer.
  T_ORDER_DEVICE_RESPONSE_IS_RING_ENTRY: assert property (@(posedge clk) disable iff (rst) ev_dpop_any |-> (n_fg != 6'd0 && d_dsrc[gdev] == q_src[g_ptr] && gdev == q_dev[g_ptr]));

  // The host is never shown a response for an entry no responder has produced.
  T_ORDER_HOST_RESPONSE_IS_ALREADY_ANSWERED: assert property (@(posedge clk) disable iff (rst) h_dv |-> (n_gr != 6'd0 || ev_dpop_any));

  // Nothing may be handed to a responder before the host let go of it, and
  // nothing may be answered before it was handed over.
  T_ORDER_POINTERS_DO_NOT_OVERTAKE: assert property (@(posedge clk) disable iff (rst) ((ev_dpush_any |-> (n_wf != 6'd0 || ev_hpush)) and (ev_dpop_any |-> n_fg != 6'd0) and (ev_hpop |-> (n_gr != 6'd0 || ev_dpop_any))));

  // =======================================================================
  // 2 -- DATA INTEGRITY
  // =======================================================================
  T_DATA_HOST_RESPONSE_WORD_IS_RING_HEAD: assert property (@(posedge clk) disable iff (rst) (h_dv && n_all != 6'd0) |-> (h_ddata == q_dat[r_ptr]));

  // What the socket puts on the selected device's A channel reproduces the
  // word this file computed for that entry at the host boundary.
  T_DATA_DEVICE_REQUEST_PAYLOAD_IS_RING_ENTRY: assert property (@(posedge clk) disable iff (rst) ev_dpush_any |-> ((d_adata[fdev] ^ d_aaddr[fdev] ^ {30'd0, fdev}) == f_dat));

  T_DATA_DEVICE_RESPONSE_WORD_IS_RING_ENTRY: assert property (@(posedge clk) disable iff (rst) ev_dpop_any |-> (n_fg != 6'd0 && d_ddata[gdev] == q_dat[g_ptr]));

  // AccessAckData, no error, and the size the host asked for.
  T_DATA_HOST_RESPONSE_IS_ACCESS_ACK_DATA: assert property (@(posedge clk) disable iff (rst) h_dv |-> (h_dop == 3'h1 && !h_derr && h_dsize == 2'd2));

  // =======================================================================
  // 3 -- UNIQUENESS / NO DUPLICATION
  // =======================================================================
  T_UNIQ_AT_MOST_ONE_DEVICE_REQUEST_VALID: assert property (@(posedge clk) disable iff (rst) $onehot0(d_av));

  T_UNIQ_AT_MOST_ONE_DEVICE_RESPONSE_VALID: assert property (@(posedge clk) disable iff (rst) $onehot0(d_dv));

  T_UNIQ_AT_MOST_ONE_DEVICE_HANDSHAKE: assert property (@(posedge clk) disable iff (rst) ($onehot0(ev_dpush) && $onehot0(ev_dpop)));

  // =======================================================================
  // 4 -- NO LOSS / CONSERVATION
  // =======================================================================
  // The three segments of the ring account for the whole of it.
  T_LOSS_RING_SEGMENTS_ACCOUNT_FOR_RING: assert property (@(posedge clk) disable iff (rst) (n_all == n_wf + n_fg + n_gr));

  // Every request the host got rid of is in the host request FIFO, past the
  // socket's steering point, or in the host response FIFO.
  T_LOSS_HOST_ACCOUNTING: assert property (@(posedge clk) disable iff (rst) (10'(n_all) == 10'(hq) + 10'(nout) + 10'(hp)));

  // What the responders hold is what this file handed them.
  T_LOSS_RESPONDER_OCCUPANCY_IS_SEGMENT: assert property (@(posedge clk) disable iff (rst) (10'(n_fg) == 10'(d_cnt[0]) + 10'(d_cnt[1]) + 10'(d_cnt[2]) + 10'(d_cnt[3])));

  // and the per-device counters account for the same segment.
  T_LOSS_DEVICE_COUNTERS_ACCOUNT_FOR_SEGMENT: assert property (@(posedge clk) disable iff (rst) (10'(n_fg) == 10'(dcnt[0]) + 10'(dcnt[1]) + 10'(dcnt[2]) + 10'(dcnt[3])));

  // two rings built at the same boundary out of different code agree.
  T_LOSS_RING_COUNT_MATCHES_REFERENCE_QUEUE: assert property (@(posedge clk) disable iff (rst) (10'(n_all) == 10'(testbench.ref_count)));

  // =======================================================================
  // 5 -- MUTUAL EXCLUSION / ONE-HOT
  // =======================================================================
  // The socket must hold a request aimed at a new device until every earlier
  // response has returned, so only one responder may be busy at a time.
  T_MUTEX_ONE_DEVICE_OUTSTANDING: assert property (@(posedge clk) disable iff (rst) $onehot0({dcnt[0] != 4'd0, dcnt[1] != 4'd0, dcnt[2] != 4'd0, dcnt[3] != 4'd0}));

  // and only one device request FIFO may hold anything.
  T_MUTEX_ONE_DEVICE_REQUEST_FIFO_BUSY: assert property (@(posedge clk) disable iff (rst) $onehot0({dq_req[0] != 3'd0, dq_req[1] != 3'd0, dq_req[2] != 3'd0, dq_req[3] != 3'd0}));

  // and only one device response FIFO.
  T_MUTEX_ONE_DEVICE_RESPONSE_FIFO_BUSY: assert property (@(posedge clk) disable iff (rst) $onehot0({dq_rsp[0] != 3'd0, dq_rsp[1] != 3'd0, dq_rsp[2] != 3'd0, dq_rsp[3] != 3'd0}));

  // if the steered device owes nothing then nobody owes anything.
  T_MUTEX_BUSY_DEVICE_IS_THE_STEERED_ONE: assert property (@(posedge clk) disable iff (rst) (dcnt[dsel_o] == 4'd0) |-> (dcnt[0] == 4'd0 && dcnt[1] == 4'd0 && dcnt[2] == 4'd0 && dcnt[3] == 4'd0));

  // a request only ever reaches the device the steering register names.
  T_MUTEX_FORWARDED_DEVICE_IS_STEERED: assert property (@(posedge clk) disable iff (rst) ev_dpush_any |-> (fdev == dsel_o));

  // =======================================================================
  // 6 -- OCCUPANCY AND BOUNDS
  // =======================================================================
  T_BOUND_RING_OCCUPANCY: assert property (@(posedge clk) disable iff (rst) (n_all <= 6'd24));

  T_BOUND_SEGMENT_AT_RESPONDERS: assert property (@(posedge clk) disable iff (rst) (n_fg <= 6'd4));

  T_BOUND_SEGMENT_ANSWERED_NOT_DELIVERED: assert property (@(posedge clk) disable iff (rst) (n_gr <= 6'd8));

  T_BOUND_SEGMENT_NOT_YET_FORWARDED: assert property (@(posedge clk) disable iff (rst) (n_wf <= 6'd12));

  T_BOUND_SOCKET_OUTSTANDING: assert property (@(posedge clk) disable iff (rst) (nout <= 9'd12));

  T_BOUND_RESPONDER_OCCUPANCY: assert property (@(posedge clk) disable iff (rst) (d_cnt[0] <= 3'd4 && d_cnt[1] <= 3'd4 && d_cnt[2] <= 3'd4 && d_cnt[3] <= 3'd4));

  T_BOUND_HOST_FIFO_DEPTHS: assert property (@(posedge clk) disable iff (rst) (hq <= 3'd4 && hp <= 3'd4));

  T_BOUND_DEVICE_FIFO_DEPTHS: assert property (@(posedge clk) disable iff (rst) (dq_req[0] <= 3'd4 && dq_req[1] <= 3'd4 && dq_req[2] <= 3'd4 && dq_req[3] <= 3'd4 && dq_rsp[0] <= 3'd4 && dq_rsp[1] <= 3'd4 && dq_rsp[2] <= 3'd4 && dq_rsp[3] <= 3'd4));

  // =======================================================================
  // 8 -- REQUEST-RESPONSE CORRESPONDENCE
  // =======================================================================
  T_REQRSP_NO_UNSOLICITED_HOST_RESPONSE: assert property (@(posedge clk) disable iff (rst) h_dv |-> (n_all != 6'd0));

  T_REQRSP_NO_UNSOLICITED_DEVICE_RESPONSE: assert property (@(posedge clk) disable iff (rst) (|d_dv) |-> (n_fg != 6'd0));

  T_REQRSP_DEVICE_ANSWERS_ONLY_WHAT_IT_OWES: assert property (@(posedge clk) disable iff (rst) ev_dpop_any |-> (dcnt[gdev] != 4'd0));

  T_REQRSP_RESPONSE_ONLY_AFTER_FORWARD: assert property (@(posedge clk) disable iff (rst) h_dv |-> ((n_fg + n_gr) != 6'd0));

  // =======================================================================
  // 9 -- PROTOCOL CONFORMANCE
  // =======================================================================
  T_PROTO_HOST_DVALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (h_dv && !h_dr) |=> h_dv);

  T_PROTO_HOST_RESPONSE_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (h_dv && !h_dr) |=> ($stable(h_dsrc) && $stable(h_ddata) && $stable(h_dop) && $stable(h_derr)));

  T_PROTO_DEVICE_AVALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (((d_av[0] && !d_ar[0]) |=> d_av[0]) and ((d_av[1] && !d_ar[1]) |=> d_av[1]) and ((d_av[2] && !d_ar[2]) |=> d_av[2]) and ((d_av[3] && !d_ar[3]) |=> d_av[3])));

  T_PROTO_DEVICE_REQUEST_STABLE_WHILE_STALLED: assert property (@(posedge clk) disable iff (rst) (((d_av[0] && !d_ar[0]) |=> ($stable(d_asrc[0]) && $stable(d_aaddr[0]) && $stable(d_adata[0]))) and ((d_av[1] && !d_ar[1]) |=> ($stable(d_asrc[1]) && $stable(d_aaddr[1]) && $stable(d_adata[1]))) and ((d_av[2] && !d_ar[2]) |=> ($stable(d_asrc[2]) && $stable(d_aaddr[2]) && $stable(d_adata[2]))) and ((d_av[3] && !d_ar[3]) |=> ($stable(d_asrc[3]) && $stable(d_aaddr[3]) && $stable(d_adata[3])))));

  T_PROTO_DEVICE_DVALID_HELD_UNTIL_READY: assert property (@(posedge clk) disable iff (rst) (((d_dv[0] && !d_dr[0]) |=> d_dv[0]) and ((d_dv[1] && !d_dr[1]) |=> d_dv[1]) and ((d_dv[2] && !d_dr[2]) |=> d_dv[2]) and ((d_dv[3] && !d_dr[3]) |=> d_dv[3])));

  // the socket never pushes a fifth request into a four-deep responder.
  T_PROTO_RESPONDER_NEVER_OVERFILLED: assert property (@(posedge clk) disable iff (rst) ((ev_dpush[0] |-> dcnt[0] <= 4'd3) and (ev_dpush[1] |-> dcnt[1] <= 4'd3) and (ev_dpush[2] |-> dcnt[2] <= 4'd3) and (ev_dpush[3] |-> dcnt[3] <= 4'd3)));

  // =======================================================================
  // 11 -- BOUNDED RESPONSE (saturating counters, gated on the host taking
  //       responses, because `response_ready` is a free input)
  // =======================================================================
  T_BOUNDRSP_HOST_REQUEST_ACCEPTED: assert property (@(posedge clk) disable iff (rst) (w_hreq <= 7'd40));

  T_BOUNDRSP_HOST_RESPONSE_DELIVERED: assert property (@(posedge clk) disable iff (rst) (w_hrsp <= 7'd40));

  T_BOUNDRSP_RESPONDER_ANSWERS: assert property (@(posedge clk) disable iff (rst) (w_dev <= 7'd24));

  // =======================================================================
  // 12 -- DEADLOCK FREEDOM (global progress counters, same gating)
  // =======================================================================
  T_DEADLOCK_PIPELINE_MAKES_PROGRESS: assert property (@(posedge clk) disable iff (rst) (w_prog <= 7'd40));

  T_DEADLOCK_DEVICE_SWITCH_STALL_RELEASES: assert property (@(posedge clk) disable iff (rst) (w_hold <= 7'd40));

  // =======================================================================
  // 13 -- RESET / INITIALISATION
  // =======================================================================
  T_RESET_SOCKET_IDLE: assert property (@(posedge clk) first |-> (nout == 9'd0 && !hold && hq == 3'd0 && hp == 3'd0));

  T_RESET_DEVICE_FIFOS_EMPTY: assert property (@(posedge clk) first |-> (dq_req[0] == 3'd0 && dq_req[1] == 3'd0 && dq_req[2] == 3'd0 && dq_req[3] == 3'd0 && dq_rsp[0] == 3'd0 && dq_rsp[1] == 3'd0 && dq_rsp[2] == 3'd0 && dq_rsp[3] == 3'd0));

  T_RESET_RESPONDERS_EMPTY: assert property (@(posedge clk) first |-> (d_cnt[0] == 3'd0 && d_cnt[1] == 3'd0 && d_cnt[2] == 3'd0 && d_cnt[3] == 3'd0 && !(|d_dv)));

  T_RESET_NO_RESPONSE_OFFERED: assert property (@(posedge clk) first |-> (!h_dv && testbench.ref_count == 7'd0));

  // =======================================================================
  // covers -- one per category used, so the screen can see the scenario each
  // family constrains is reachable
  // =======================================================================
  C_ORDER_RESPONSE_DELIVERED: cover property (@(posedge clk) disable iff (rst) (ev_hpop && n_all >= 6'd2));

  C_ORDER_DEVICE_SWITCH: cover property (@(posedge clk) disable iff (rst) (ev_dpush_any && fdev != 2'd0 && n_all >= 6'd2));

  C_DATA_WORD_MATCHED_AT_HOST: cover property (@(posedge clk) disable iff (rst) (ev_hpop && h_ddata != 32'd0));

  C_UNIQ_TWO_DEVICES_USED_IN_TURN: cover property (@(posedge clk) disable iff (rst) (ev_dpop_any && gdev == 2'd1) ##[1:20] (ev_dpop_any && gdev == 2'd2));

  C_LOSS_ALL_THREE_SEGMENTS_OCCUPIED: cover property (@(posedge clk) disable iff (rst) (n_wf != 6'd0 && n_fg != 6'd0 && n_gr != 6'd0));

  C_MUTEX_HOLD_WITH_BACKLOG: cover property (@(posedge clk) disable iff (rst) (hold && nout >= 9'd2));

  C_BOUND_RESPONDER_FULL: cover property (@(posedge clk) disable iff (rst) (d_cnt[0] == 3'd4 || d_cnt[1] == 3'd4 || d_cnt[2] == 3'd4 || d_cnt[3] == 3'd4));

  C_BOUND_RING_BACKLOG: cover property (@(posedge clk) disable iff (rst) (n_all >= 6'd8));

  C_REQRSP_MANY_SOURCES_OUTSTANDING: cover property (@(posedge clk) disable iff (rst) (n_all >= 6'd4 && h_dv));

  C_PROTO_HOST_RESPONSE_STALLED: cover property (@(posedge clk) disable iff (rst) (h_dv && !h_dr));

  C_PROTO_DEVICE_REQUEST_STALLED: cover property (@(posedge clk) disable iff (rst) (|(d_av & ~d_ar)));

  C_BOUNDRSP_REQUEST_WAITED: cover property (@(posedge clk) disable iff (rst) (w_hreq >= 7'd6));

  C_BOUNDRSP_RESPONSE_WAITED: cover property (@(posedge clk) disable iff (rst) (w_hrsp >= 7'd6));

  C_DEADLOCK_HOLD_HELD: cover property (@(posedge clk) disable iff (rst) (w_hold >= 7'd4));

  C_DEADLOCK_PROGRESS_GAP: cover property (@(posedge clk) disable iff (rst) (w_prog >= 7'd4));

  C_RESET_FIRST_CYCLE: cover property (@(posedge clk) first);

endmodule

bind testbench tlul_socket_targets u_tlul_socket_targets (.clk(clock), .rst(reset));

`default_nettype wire
