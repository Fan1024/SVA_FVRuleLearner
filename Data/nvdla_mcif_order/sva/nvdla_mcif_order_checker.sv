// Independent interface-level checker for four active NVDLA MCIF read clients.
//
// The checker observes issued AXI reads, accepted AXI read data, and the four
// client response channels.  It does not inspect the MCIF context queue,
// response FIFOs, arbiter state, or ownership pointers.  Three debug signals
// expose only the endpoint pipeline occupancy needed to state end-to-end
// outstanding conservation.

module nvdla_mcif_order_checker #(
   parameter integer NCLIENT    = 4,
   parameter integer REF_DEPTH = 64,
   parameter integer REF_PTR_W = $clog2(REF_DEPTH),
   parameter integer REF_CNT_W = $clog2(REF_DEPTH + 1)
) (
   input wire                       clk,
   input wire                       reset_n,

   input wire [NCLIENT-1:0]         req_valid,
   input wire [NCLIENT-1:0]         req_ready,
   input wire [(NCLIENT*79)-1:0]    req_pd_flat,

   input wire                       ar_valid,
   input wire                       ar_ready,
   input wire [7:0]                 ar_id,
   input wire [3:0]                 ar_len,

   input wire                       r_valid,
   input wire                       r_ready,
   input wire [7:0]                 r_id,
   input wire                       r_last,
   input wire [511:0]               r_data,

   input wire [NCLIENT-1:0]         rsp_valid,
   input wire [NCLIENT-1:0]         rsp_ready,
   input wire [(NCLIENT*514)-1:0]   rsp_pd_flat,

   input wire [8:0]                 dbg_os_cnt,
   input wire                       dbg_ar_skid_valid,
   input wire                       dbg_r_pipe_valid,
   input wire                       dbg_r_skid_valid,
   input wire                       dbg_eg2ig_axi_vld_d
);
   localparam integer EXT_CNT_W = 9;

   wire ar_fire = ar_valid && ar_ready;
   wire r_fire  = r_valid && r_ready;
   wire [NCLIENT-1:0] rsp_fire = rsp_valid & rsp_ready;

   // Environment-side outstanding ledger.  It constrains the AXI return
   // channel to legal, single-beat responses for already-issued active IDs.
   reg [5:0] axi_pending [0:NCLIENT-1];
   reg [EXT_CNT_W-1:0] ext_outstanding;

   integer p;
   always @(posedge clk) begin
      if (!reset_n) begin
         ext_outstanding <= {EXT_CNT_W{1'b0}};
         for (p = 0; p < NCLIENT; p = p + 1)
            axi_pending[p] <= 6'd0;
      end else begin
         case ({ar_fire, r_fire})
            2'b10: ext_outstanding <= ext_outstanding + 1'b1;
            2'b01: ext_outstanding <= ext_outstanding - 1'b1;
            default: begin end
         endcase

         for (p = 0; p < NCLIENT; p = p + 1) begin
            case ({(ar_fire && (ar_id == p)),
                   (r_fire && (r_id == p))})
               2'b10: axi_pending[p] <= axi_pending[p] + 1'b1;
               2'b01: axi_pending[p] <= axi_pending[p] - 1'b1;
               default: begin end
            endcase
         end
      end
   end

   // Legal NVDLA request subset: a 256-byte-aligned command of eight 32-byte
   // atoms.  The real BPT and SPT logic expand each command into four
   // single-beat, full-mask AXI requests.  Valid and payload follow the
   // standard sticky-ready/valid contract.
   generate
      genvar a;
      for (a = 0; a < NCLIENT; a = a + 1) begin : G_REQ_ENV
         A_REQ_SHAPE: assume property (@(posedge clk) disable iff (!reset_n)
            req_valid[a] |->
               ((req_pd_flat[(a*79) +: 64] & 64'hff) == 64'h0) &&
               (req_pd_flat[(a*79)+64 +: 15] == 15'd7));

         A_REQ_STICKY: assume property (@(posedge clk) disable iff (!reset_n)
            req_valid[a] && !req_ready[a] |=>
               req_valid[a] &&
               $stable(req_pd_flat[(a*79) +: 79]));
      end
   endgenerate

   A_R_ACTIVE_ID: assume property (@(posedge clk) disable iff (!reset_n)
      r_valid |-> ((r_id[7:4] == 4'd0) && (r_id[3:0] < NCLIENT)));

   A_R_HAS_REQUEST: assume property (@(posedge clk) disable iff (!reset_n)
      r_valid |-> (axi_pending[r_id[1:0]] != 0));

   A_R_SINGLE_BEAT: assume property (@(posedge clk) disable iff (!reset_n)
      r_valid |-> r_last);

   A_R_STICKY: assume property (@(posedge clk) disable iff (!reset_n)
      r_valid && !r_ready |=>
         r_valid && $stable(r_id) && $stable(r_last) && $stable(r_data));

   // Independent per-client data FIFOs.  Each accepted AXI response is
   // recorded by its public AXI ID; each public client response must consume
   // the oldest recorded beat for that client.
   reg [511:0] ref_mem [0:(NCLIENT*REF_DEPTH)-1];
   reg [REF_PTR_W-1:0] ref_wr_ptr [0:NCLIENT-1];
   reg [REF_PTR_W-1:0] ref_rd_ptr [0:NCLIENT-1];
   reg [REF_CNT_W-1:0] ref_count  [0:NCLIENT-1];

   integer c;
   always @(posedge clk) begin
      if (!reset_n) begin
         for (c = 0; c < NCLIENT; c = c + 1) begin
            ref_wr_ptr[c] <= {REF_PTR_W{1'b0}};
            ref_rd_ptr[c] <= {REF_PTR_W{1'b0}};
            ref_count[c]  <= {REF_CNT_W{1'b0}};
         end
      end else begin
         for (c = 0; c < NCLIENT; c = c + 1) begin
            if (r_fire && (r_id == c)) begin
               ref_mem[(c * REF_DEPTH) + ref_wr_ptr[c]] <= r_data;
               if (ref_wr_ptr[c] == (REF_DEPTH - 1))
                  ref_wr_ptr[c] <= {REF_PTR_W{1'b0}};
               else
                  ref_wr_ptr[c] <= ref_wr_ptr[c] + 1'b1;
            end

            if (rsp_fire[c]) begin
               if (ref_rd_ptr[c] == (REF_DEPTH - 1))
                  ref_rd_ptr[c] <= {REF_PTR_W{1'b0}};
               else
                  ref_rd_ptr[c] <= ref_rd_ptr[c] + 1'b1;
            end

            case ({(r_fire && (r_id == c)), rsp_fire[c]})
               2'b10: ref_count[c] <= ref_count[c] + 1'b1;
               2'b01: ref_count[c] <= ref_count[c] - 1'b1;
               default: begin end
            endcase
         end
      end
   end

   wire [NCLIENT-1:0] response_owner_ok;
   wire [NCLIENT-1:0] response_order_ok;
   wire [NCLIENT-1:0] response_mask_ok;

   generate
      genvar t;
      for (t = 0; t < NCLIENT; t = t + 1) begin : G_TARGET
         wire [513:0] rsp_pd = rsp_pd_flat[(t*514) +: 514];
         wire [511:0] expected_data =
            ref_mem[(t * REF_DEPTH) + ref_rd_ptr[t]];

         assign response_owner_ok[t] =
            !rsp_valid[t] || (ref_count[t] != 0);
         assign response_order_ok[t] =
            !rsp_valid[t] || (rsp_pd[511:0] == expected_data);
         assign response_mask_ok[t] =
            !rsp_valid[t] || (rsp_pd[513:512] == 2'b11);
      end
   endgenerate

   // os_cnt counts commands accepted into the AXI output pipe and does not
   // retire a response until one cycle after the response input pipe drains.
   // Therefore the public outstanding count is augmented by exactly those
   // five endpoint stages.  The response pipe occupancy is its two physical
   // valid flops; its muxed output-valid is not an independent entry.
   wire [9:0] outstanding_image =
      {1'b0, ext_outstanding} +
      {{9{1'b0}}, ar_valid} +
      {{9{1'b0}}, dbg_ar_skid_valid} +
      {{9{1'b0}}, dbg_r_pipe_valid} +
      {{9{1'b0}}, dbg_r_skid_valid} +
      {{9{1'b0}}, dbg_eg2ig_axi_vld_d};

   wire issue_shape_ok =
      !ar_valid ||
      ((ar_id[7:4] == 4'd0) && (ar_id[3:0] < NCLIENT) &&
       (ar_len == 4'd0));
   wire ownership_ok = &response_owner_ok;
   wire beat_order_ok = &(response_order_ok & response_mask_ok);
   wire conservation_ok = ({1'b0, dbg_os_cnt} == outstanding_image);

   // Composite target with four same-type logical clauses:
   // issued-ID/beat shape, response ownership, per-client beat order, and
   // outstanding conservation.
   T_MCIF_ORDER: assert property (@(posedge clk) disable iff (!reset_n)
      issue_shape_ok && ownership_ok && beat_order_ok && conservation_ok);

   // Admission covers: all four clients participate, responses interleave,
   // queues build depth, and client backpressure is exercised.
   reg [NCLIENT-1:0] seen_req;
   reg [NCLIENT-1:0] seen_ar;
   reg [NCLIENT-1:0] seen_r;
   reg [NCLIENT-1:0] seen_rsp;
   integer s;
   always @(posedge clk) begin
      if (!reset_n) begin
         seen_req <= {NCLIENT{1'b0}};
         seen_ar  <= {NCLIENT{1'b0}};
         seen_r   <= {NCLIENT{1'b0}};
         seen_rsp <= {NCLIENT{1'b0}};
      end else begin
         seen_req <= seen_req | (req_valid & req_ready);
         seen_rsp <= seen_rsp | rsp_fire;
         for (s = 0; s < NCLIENT; s = s + 1) begin
            if (ar_fire && (ar_id == s))
               seen_ar[s] <= 1'b1;
            if (r_fire && (r_id == s))
               seen_r[s] <= 1'b1;
         end
      end
   end

   C_ALL_CLIENT_REQUESTS: cover property (@(posedge clk) disable iff (!reset_n)
      &seen_req);
   C_ALL_CLIENT_ISSUES: cover property (@(posedge clk) disable iff (!reset_n)
      &seen_ar);
   C_ALL_CLIENT_RETURNS: cover property (@(posedge clk) disable iff (!reset_n)
      &seen_r);
   C_ALL_CLIENT_RESPONSES: cover property (@(posedge clk) disable iff (!reset_n)
      &seen_rsp);
   C_MULTI_CLIENT_BACKLOG: cover property (@(posedge clk) disable iff (!reset_n)
      (ref_count[0] >= 2) && (ref_count[1] >= 2) &&
      (ref_count[2] != 0) && (ref_count[3] != 0));
   C_INTERLEAVED_RETURN: cover property (@(posedge clk) disable iff (!reset_n)
      r_fire ##1 r_fire && (r_id != $past(r_id)));
   C_RESPONSE_BACKPRESSURE: cover property (
      @(posedge clk) disable iff (!reset_n)
      |(rsp_valid & ~rsp_ready));

endmodule
