// Component-local formal top for the real NVDLA BDMA load/context/store path.
// A command copies two eight-beat lines through MCIF.  Commands, memory
// backpressure, and response data remain symbolic.

module nvdla_bdma_data_order_ft (
   input wire         nvdla_core_clk,
   input wire         nvdla_core_rstn,
   input wire         csb2ld_vld,
   input wire         bdma2mcif_rd_req_ready,
   input wire         mcif2bdma_rd_rsp_valid,
   input wire [513:0] mcif2bdma_rd_rsp_pd,
   input wire         bdma2mcif_wr_req_ready
);
   wire [31:0] pwrbus_ram_pd = 32'd0;

   // Fixed functional command shape: MCIF-to-MCIF, two eight-beat lines.
   wire         reg2dp_cmd_dst_ram_type = 1'b1;
   wire         reg2dp_cmd_interrupt = 1'b0;
   wire         reg2dp_cmd_interrupt_ptr = 1'b0;
   wire         reg2dp_cmd_src_ram_type = 1'b1;
   wire [31:0]  reg2dp_dst_addr_high_v8 = 32'd0;
   wire [26:0]  reg2dp_dst_addr_low_v32 = 27'h02000;
   wire [26:0]  reg2dp_dst_line_stride = 27'd32;
   wire [26:0]  reg2dp_dst_surf_stride = 27'd64;
   wire [23:0]  reg2dp_line_repeat_number = 24'd1;
   wire [12:0]  reg2dp_line_size = 13'd15;
   wire [31:0]  reg2dp_src_addr_high_v8 = 32'd0;
   wire [26:0]  reg2dp_src_addr_low_v32 = 27'h01000;
   wire [26:0]  reg2dp_src_line_stride = 27'd32;
   wire [26:0]  reg2dp_src_surf_stride = 27'd64;
   wire [23:0]  reg2dp_surf_repeat_number = 24'd0;

   wire         bdma2mcif_rd_req_valid;
   wire [78:0]  bdma2mcif_rd_req_pd;
   wire         bdma2cvif_rd_req_valid;
   wire [78:0]  bdma2cvif_rd_req_pd;
   wire         bdma2cvif_rd_req_ready = 1'b1;

   wire         ld2st_wr_pvld;
   wire         ld2st_wr_prdy;
   wire [160:0] ld2st_wr_pd;
   wire         ld2st_wr_idle;
   wire         ld2st_rd_pvld;
   wire         ld2st_rd_prdy;
   wire [160:0] ld2st_rd_pd;

   wire         cvif2bdma_rd_rsp_valid = 1'b0;
   wire [513:0] cvif2bdma_rd_rsp_pd = 514'd0;
   wire         cvif2bdma_rd_rsp_ready;
   wire         mcif2bdma_rd_rsp_ready;
   wire         bdma2mcif_rd_cdt_lat_fifo_pop;
   wire         bdma2cvif_rd_cdt_lat_fifo_pop;

   wire         bdma2mcif_wr_req_valid;
   wire [514:0] bdma2mcif_wr_req_pd;
   wire         bdma2cvif_wr_req_valid;
   wire [514:0] bdma2cvif_wr_req_pd;
   wire         bdma2cvif_wr_req_ready = 1'b1;
   wire         mcif2bdma_wr_rsp_complete = 1'b0;
   wire         cvif2bdma_wr_rsp_complete = 1'b0;

   wire         csb2ld_rdy;
   wire         ld2csb_grp0_dma_stall_inc;
   wire         ld2csb_grp1_dma_stall_inc;
   wire         ld2csb_idle;
   wire         ld2gate_slcg_en;
   wire         st2ld_load_idle;
   wire         st2csb_grp0_done;
   wire         st2csb_grp1_done;
   wire         st2csb_idle;
   wire         st2gate_slcg_en;
   wire [31:0]  dma_write_stall_count;
   wire         dma_write_stall_count_cen = 1'b0;

   NV_NVDLA_BDMA_load u_load (
      .nvdla_core_clk,
      .nvdla_core_rstn,
      .bdma2cvif_rd_req_ready,
      .bdma2mcif_rd_req_ready,
      .csb2ld_vld,
      .ld2st_wr_idle,
      .ld2st_wr_prdy,
      .reg2dp_cmd_dst_ram_type,
      .reg2dp_cmd_interrupt,
      .reg2dp_cmd_interrupt_ptr,
      .reg2dp_cmd_src_ram_type,
      .reg2dp_dst_addr_high_v8,
      .reg2dp_dst_addr_low_v32,
      .reg2dp_dst_line_stride,
      .reg2dp_dst_surf_stride,
      .reg2dp_line_repeat_number,
      .reg2dp_line_size,
      .reg2dp_src_addr_high_v8,
      .reg2dp_src_addr_low_v32,
      .reg2dp_src_line_stride,
      .reg2dp_src_surf_stride,
      .reg2dp_surf_repeat_number,
      .st2ld_load_idle,
      .bdma2cvif_rd_req_pd,
      .bdma2cvif_rd_req_valid,
      .bdma2mcif_rd_req_pd,
      .bdma2mcif_rd_req_valid,
      .csb2ld_rdy,
      .ld2csb_grp0_dma_stall_inc,
      .ld2csb_grp1_dma_stall_inc,
      .ld2csb_idle,
      .ld2gate_slcg_en,
      .ld2st_wr_pd,
      .ld2st_wr_pvld
   );

   NV_NVDLA_BDMA_cq u_cq (
      .nvdla_core_clk,
      .nvdla_core_rstn,
      .ld2st_wr_prdy,
      .ld2st_wr_idle,
      .ld2st_wr_pvld,
      .ld2st_wr_pd,
      .ld2st_rd_prdy,
      .ld2st_rd_pvld,
      .ld2st_rd_pd,
      .pwrbus_ram_pd
   );

   NV_NVDLA_BDMA_store u_store (
      .nvdla_core_clk,
      .nvdla_core_rstn,
      .bdma2cvif_wr_req_ready,
      .bdma2mcif_wr_req_ready,
      .cvif2bdma_rd_rsp_pd,
      .cvif2bdma_rd_rsp_valid,
      .cvif2bdma_wr_rsp_complete,
      .dma_write_stall_count_cen,
      .ld2st_rd_pd,
      .ld2st_rd_pvld,
      .mcif2bdma_rd_rsp_pd,
      .mcif2bdma_rd_rsp_valid,
      .mcif2bdma_wr_rsp_complete,
      .pwrbus_ram_pd,
      .bdma2cvif_rd_cdt_lat_fifo_pop,
      .bdma2cvif_wr_req_pd,
      .bdma2cvif_wr_req_valid,
      .bdma2mcif_rd_cdt_lat_fifo_pop,
      .bdma2mcif_wr_req_pd,
      .bdma2mcif_wr_req_valid,
      .cvif2bdma_rd_rsp_ready,
      .dma_write_stall_count,
      .ld2st_rd_prdy,
      .mcif2bdma_rd_rsp_ready,
      .st2csb_grp0_done,
      .st2csb_grp1_done,
      .st2csb_idle,
      .st2gate_slcg_en,
      .st2ld_load_idle
   );

   nvdla_bdma_data_order_checker u_checker (
      .clk                         (nvdla_core_clk),
      .reset_n                     (nvdla_core_rstn),
      .cmd_valid                   (csb2ld_vld),
      .cmd_ready                   (csb2ld_rdy),
      .rd_req_valid                (bdma2mcif_rd_req_valid),
      .rd_req_ready                (bdma2mcif_rd_req_ready),
      .rd_req_pd                   (bdma2mcif_rd_req_pd),
      .rd_rsp_valid                (mcif2bdma_rd_rsp_valid),
      .rd_rsp_ready                (mcif2bdma_rd_rsp_ready),
      .rd_rsp_pd                   (mcif2bdma_rd_rsp_pd),
      .wr_req_valid                (bdma2mcif_wr_req_valid),
      .wr_req_ready                (bdma2mcif_wr_req_ready),
      .wr_req_pd                   (bdma2mcif_wr_req_pd)
   );

endmodule
