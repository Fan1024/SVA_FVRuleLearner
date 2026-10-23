module nvdla_rubik_merge_transpose_ft (
   input logic         nvdla_core_clk,
   input logic         nvdla_core_rstn,
   input logic         dma_wr_data_rdy,
   input logic [511:0] source_data
);
   localparam logic [1:0] PH_WARMUP = 2'd0;
   localparam logic [1:0] PH_WRITE  = 2'd1;
   localparam logic [1:0] PH_READ   = 2'd2;
   localparam logic [1:0] PH_DRAIN  = 2'd3;

   logic [1:0]   phase_q;
   logic [1:0]   warmup_q;
   logic [4:0]   write_index_q;
   logic [4:0]   read_index_q;
   logic [511:0] write_data_q;

   wire          rf_wr_vld  = phase_q == PH_WRITE;
   wire          rf_wr_done = rf_wr_vld && write_index_q == 5'd31;
   wire [4:0]    rf_wr_addr = write_index_q;
   wire [511:0]  rf_wr_data = write_data_q;
   wire          rf_wr_rdy;
   wire          write_fire = rf_wr_vld && rf_wr_rdy;

   wire          rf_rd_vld  = phase_q == PH_READ;
   wire          rf_rd_done = rf_rd_vld && read_index_q == 5'd31;
   wire [4:0]    rf_rd_addr = read_index_q;
   wire [11:0]   rf_rd_mask = 12'h820;
   wire          rf_rd_rdy;
   wire          read_fire = rf_rd_vld && rf_rd_rdy;

   wire          dma_wr_data_vld;
   wire [513:0]  dma_wr_data_pd;

   always_ff @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
      if (!nvdla_core_rstn) begin
         phase_q       <= PH_WARMUP;
         warmup_q      <= '0;
         write_index_q <= '0;
         read_index_q  <= '0;
         write_data_q  <= '0;
      end else begin
         case (phase_q)
            PH_WARMUP: begin
               if (warmup_q == 2'd2) begin
                  phase_q       <= PH_WRITE;
                  warmup_q      <= '0;
                  write_index_q <= '0;
                  write_data_q  <= source_data;
               end else begin
                  warmup_q <= warmup_q + 1'b1;
               end
            end

            PH_WRITE: begin
               if (write_fire) begin
                  if (write_index_q == 5'd31) begin
                     phase_q      <= PH_READ;
                     read_index_q <= '0;
                  end else begin
                     write_index_q <= write_index_q + 1'b1;
                     write_data_q  <= source_data;
                  end
               end
            end

            PH_READ: begin
               if (read_fire) begin
                  if (read_index_q == 5'd31)
                     phase_q <= PH_DRAIN;
                  else
                     read_index_q <= read_index_q + 1'b1;
               end
            end

            default: begin
               if (dma_wr_data_vld && dma_wr_data_rdy) begin
                  phase_q  <= PH_WARMUP;
                  warmup_q <= '0;
               end
            end
         endcase
      end
   end

   NV_NVDLA_RUBIK_rf_core dut (
      .nvdla_core_clk      (nvdla_core_clk),
      .nvdla_core_rstn     (nvdla_core_rstn),
      .dma_wr_data_rdy     (dma_wr_data_rdy),
      .pwrbus_ram_pd       (32'd0),
      .reg2dp_in_precision (2'd0),
      .reg2dp_rubik_mode   (2'd2),
      .rf_rd_addr          (rf_rd_addr),
      .rf_rd_done          (rf_rd_done),
      .rf_rd_mask          (rf_rd_mask),
      .rf_rd_vld           (rf_rd_vld),
      .rf_wr_addr          (rf_wr_addr),
      .rf_wr_data          (rf_wr_data),
      .rf_wr_done          (rf_wr_done),
      .rf_wr_vld           (rf_wr_vld),
      .dma_wr_data_pd      (dma_wr_data_pd),
      .dma_wr_data_vld     (dma_wr_data_vld),
      .rf_rd_rdy           (rf_rd_rdy),
      .rf_wr_rdy           (rf_wr_rdy)
   );

   nvdla_rubik_merge_transpose_checker u_checker (
      .nvdla_core_clk  (nvdla_core_clk),
      .nvdla_core_rstn (nvdla_core_rstn),
      .write_fire      (write_fire),
      .write_index     (write_index_q),
      .write_data      (write_data_q),
      .read_pop        (dut.rf_rd_pop),
      .read_index      (dut.rf_rd_oaddr),
      .dma_wr_data_vld (dma_wr_data_vld),
      .dma_wr_data_rdy (dma_wr_data_rdy),
      .dma_wr_data_pd  (dma_wr_data_pd)
   );

endmodule
