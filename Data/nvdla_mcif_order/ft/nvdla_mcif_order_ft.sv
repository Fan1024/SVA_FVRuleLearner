// Formal top for four active clients of the real generated NVDLA MCIF read
// path.  Client IDs 0..3 are BDMA, SDP, PDP, and CDP respectively.  The six
// remaining generated clients are tied inactive; their response sinks remain
// ready so they cannot create accidental backpressure.

module nvdla_mcif_order_ft (
   input wire         nvdla_core_clk,
   input wire         nvdla_core_rstn,

   input wire         bdma2mcif_rd_req_valid,
   input wire [78:0]  bdma2mcif_rd_req_pd,
   input wire         sdp2mcif_rd_req_valid,
   input wire [78:0]  sdp2mcif_rd_req_pd,
   input wire         pdp2mcif_rd_req_valid,
   input wire [78:0]  pdp2mcif_rd_req_pd,
   input wire         cdp2mcif_rd_req_valid,
   input wire [78:0]  cdp2mcif_rd_req_pd,

   input wire         mcif2bdma_rd_rsp_ready,
   input wire         mcif2sdp_rd_rsp_ready,
   input wire         mcif2pdp_rd_rsp_ready,
   input wire         mcif2cdp_rd_rsp_ready,

   input wire         mcif2noc_axi_ar_arready,
   input wire         noc2mcif_axi_r_rvalid,
   input wire [7:0]   noc2mcif_axi_r_rid,
   input wire         noc2mcif_axi_r_rlast,
   input wire [511:0] noc2mcif_axi_r_rdata
);
   // Active request ready signals.
   wire bdma2mcif_rd_req_ready;
   wire sdp2mcif_rd_req_ready;
   wire pdp2mcif_rd_req_ready;
   wire cdp2mcif_rd_req_ready;

   // Inactive clients.
   wire         cdma_dat2mcif_rd_req_valid = 1'b0;
   wire [78:0]  cdma_dat2mcif_rd_req_pd = 79'd0;
   wire         cdma_wt2mcif_rd_req_valid = 1'b0;
   wire [78:0]  cdma_wt2mcif_rd_req_pd = 79'd0;
   wire         rbk2mcif_rd_req_valid = 1'b0;
   wire [78:0]  rbk2mcif_rd_req_pd = 79'd0;
   wire         sdp_b2mcif_rd_req_valid = 1'b0;
   wire [78:0]  sdp_b2mcif_rd_req_pd = 79'd0;
   wire         sdp_e2mcif_rd_req_valid = 1'b0;
   wire [78:0]  sdp_e2mcif_rd_req_pd = 79'd0;
   wire         sdp_n2mcif_rd_req_valid = 1'b0;
   wire [78:0]  sdp_n2mcif_rd_req_pd = 79'd0;

   wire cdma_dat2mcif_rd_req_ready;
   wire cdma_wt2mcif_rd_req_ready;
   wire rbk2mcif_rd_req_ready;
   wire sdp_b2mcif_rd_req_ready;
   wire sdp_e2mcif_rd_req_ready;
   wire sdp_n2mcif_rd_req_ready;

   // Client response channels.
   wire         mcif2bdma_rd_rsp_valid;
   wire [513:0] mcif2bdma_rd_rsp_pd;
   wire         mcif2sdp_rd_rsp_valid;
   wire [513:0] mcif2sdp_rd_rsp_pd;
   wire         mcif2pdp_rd_rsp_valid;
   wire [513:0] mcif2pdp_rd_rsp_pd;
   wire         mcif2cdp_rd_rsp_valid;
   wire [513:0] mcif2cdp_rd_rsp_pd;

   wire         mcif2cdma_dat_rd_rsp_valid;
   wire [513:0] mcif2cdma_dat_rd_rsp_pd;
   wire         mcif2cdma_dat_rd_rsp_ready = 1'b1;
   wire         mcif2cdma_wt_rd_rsp_valid;
   wire [513:0] mcif2cdma_wt_rd_rsp_pd;
   wire         mcif2cdma_wt_rd_rsp_ready = 1'b1;
   wire         mcif2rbk_rd_rsp_valid;
   wire [513:0] mcif2rbk_rd_rsp_pd;
   wire         mcif2rbk_rd_rsp_ready = 1'b1;
   wire         mcif2sdp_b_rd_rsp_valid;
   wire [513:0] mcif2sdp_b_rd_rsp_pd;
   wire         mcif2sdp_b_rd_rsp_ready = 1'b1;
   wire         mcif2sdp_e_rd_rsp_valid;
   wire [513:0] mcif2sdp_e_rd_rsp_pd;
   wire         mcif2sdp_e_rd_rsp_ready = 1'b1;
   wire         mcif2sdp_n_rd_rsp_valid;
   wire [513:0] mcif2sdp_n_rd_rsp_pd;
   wire         mcif2sdp_n_rd_rsp_ready = 1'b1;

   // Credits return when the corresponding client accepts one 64-byte
   // response.  Under the frozen full-beat request shape this exactly repays
   // one latency-FIFO slot.
   wire bdma2mcif_rd_cdt_lat_fifo_pop =
      mcif2bdma_rd_rsp_valid && mcif2bdma_rd_rsp_ready;
   wire sdp2mcif_rd_cdt_lat_fifo_pop =
      mcif2sdp_rd_rsp_valid && mcif2sdp_rd_rsp_ready;
   wire pdp2mcif_rd_cdt_lat_fifo_pop =
      mcif2pdp_rd_rsp_valid && mcif2pdp_rd_rsp_ready;
   wire cdp2mcif_rd_cdt_lat_fifo_pop =
      mcif2cdp_rd_rsp_valid && mcif2cdp_rd_rsp_ready;
   wire rbk2mcif_rd_cdt_lat_fifo_pop = 1'b0;
   wire sdp_b2mcif_rd_cdt_lat_fifo_pop = 1'b0;
   wire sdp_e2mcif_rd_cdt_lat_fifo_pop = 1'b0;
   wire sdp_n2mcif_rd_cdt_lat_fifo_pop = 1'b0;

   // Frozen functional configuration.  Equal nonzero active weights retain
   // the generated weighted round-robin behavior; inactive clients have zero
   // weight.  The outstanding window is 16 AXI beats.
   wire [7:0] reg2dp_rd_os_cnt = 8'd15;
   wire [7:0] reg2dp_rd_weight_bdma = 8'd1;
   wire [7:0] reg2dp_rd_weight_sdp = 8'd1;
   wire [7:0] reg2dp_rd_weight_pdp = 8'd1;
   wire [7:0] reg2dp_rd_weight_cdp = 8'd1;
   wire [7:0] reg2dp_rd_weight_rbk = 8'd0;
   wire [7:0] reg2dp_rd_weight_sdp_b = 8'd0;
   wire [7:0] reg2dp_rd_weight_sdp_e = 8'd0;
   wire [7:0] reg2dp_rd_weight_sdp_n = 8'd0;
   wire [7:0] reg2dp_rd_weight_cdma_dat = 8'd0;
   wire [7:0] reg2dp_rd_weight_cdma_wt = 8'd0;
   wire [31:0] pwrbus_ram_pd = 32'd0;

   // Public NOC interface outputs.
   wire         mcif2noc_axi_ar_arvalid;
   wire [7:0]   mcif2noc_axi_ar_arid;
   wire [3:0]   mcif2noc_axi_ar_arlen;
   wire [63:0]  mcif2noc_axi_ar_araddr;
   wire         noc2mcif_axi_r_rready;

   NV_NVDLA_MCIF_read dut (.*);

   wire [3:0] req_valid = {
      cdp2mcif_rd_req_valid,
      pdp2mcif_rd_req_valid,
      sdp2mcif_rd_req_valid,
      bdma2mcif_rd_req_valid
   };
   wire [3:0] req_ready = {
      cdp2mcif_rd_req_ready,
      pdp2mcif_rd_req_ready,
      sdp2mcif_rd_req_ready,
      bdma2mcif_rd_req_ready
   };
   wire [(4*79)-1:0] req_pd_flat = {
      cdp2mcif_rd_req_pd,
      pdp2mcif_rd_req_pd,
      sdp2mcif_rd_req_pd,
      bdma2mcif_rd_req_pd
   };

   wire [3:0] rsp_valid = {
      mcif2cdp_rd_rsp_valid,
      mcif2pdp_rd_rsp_valid,
      mcif2sdp_rd_rsp_valid,
      mcif2bdma_rd_rsp_valid
   };
   wire [3:0] rsp_ready = {
      mcif2cdp_rd_rsp_ready,
      mcif2pdp_rd_rsp_ready,
      mcif2sdp_rd_rsp_ready,
      mcif2bdma_rd_rsp_ready
   };
   wire [(4*514)-1:0] rsp_pd_flat = {
      mcif2cdp_rd_rsp_pd,
      mcif2pdp_rd_rsp_pd,
      mcif2sdp_rd_rsp_pd,
      mcif2bdma_rd_rsp_pd
   };

   // The checker does not inspect the CQ, arbiter, response FIFOs, or their
   // ownership state.  These endpoint signals are the terms needed for
   // a public-interface outstanding conservation equation.
   wire [8:0] dbg_os_cnt = dut.u_ig.u_cvt.os_cnt;
   wire dbg_ar_skid_valid = dut.u_ig.u_cvt.pipe_p1.p1_skid_valid;
   wire dbg_r_pipe_valid = dut.u_eg.pipe_p1.p1_pipe_valid;
   wire dbg_r_skid_valid = dut.u_eg.pipe_p1.p1_skid_valid;
   wire dbg_eg2ig_axi_vld_d = dut.u_ig.u_cvt.eg2ig_axi_vld_d;

   nvdla_mcif_order_checker u_checker (
      .clk                       (nvdla_core_clk),
      .reset_n                   (nvdla_core_rstn),
      .req_valid                 (req_valid),
      .req_ready                 (req_ready),
      .req_pd_flat               (req_pd_flat),
      .ar_valid                  (mcif2noc_axi_ar_arvalid),
      .ar_ready                  (mcif2noc_axi_ar_arready),
      .ar_id                     (mcif2noc_axi_ar_arid),
      .ar_len                    (mcif2noc_axi_ar_arlen),
      .r_valid                   (noc2mcif_axi_r_rvalid),
      .r_ready                   (noc2mcif_axi_r_rready),
      .r_id                      (noc2mcif_axi_r_rid),
      .r_last                    (noc2mcif_axi_r_rlast),
      .r_data                    (noc2mcif_axi_r_rdata),
      .rsp_valid                 (rsp_valid),
      .rsp_ready                 (rsp_ready),
      .rsp_pd_flat               (rsp_pd_flat),
      .dbg_os_cnt                (dbg_os_cnt),
      .dbg_ar_skid_valid         (dbg_ar_skid_valid),
      .dbg_r_pipe_valid          (dbg_r_pipe_valid),
      .dbg_r_skid_valid          (dbg_r_skid_valid),
      .dbg_eg2ig_axi_vld_d       (dbg_eg2ig_axi_vld_d)
   );

endmodule
