module nvdla_rubik_merge_transpose_checker (
   input  logic         nvdla_core_clk,
   input  logic         nvdla_core_rstn,
   input  logic         write_fire,
   input  logic [4:0]   write_index,
   input  logic [511:0] write_data,
   input  logic         read_pop,
   input  logic [4:0]   read_index,
   input  logic         dma_wr_data_vld,
   input  logic         dma_wr_data_rdy,
   input  logic [513:0] dma_wr_data_pd
);
   logic [511:0] batch [0:31];
   logic [511:0] expected_q;
   logic [4:0]   expected_index_q;
   logic         pending_q;
   logic [1:0]   completed_batches_q;

   function automatic [511:0] transpose_column(input logic [4:0] column);
      integer beat;
      begin
         transpose_column = '0;
         for (beat = 0; beat < 32; beat = beat + 1) begin
            transpose_column[8*beat +: 8] =
               batch[beat] >> (16*column);
            transpose_column[8*(beat+32) +: 8] =
               batch[beat] >> (16*column + 8);
         end
      end
   endfunction

   always_ff @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
      if (!nvdla_core_rstn) begin
         expected_q          <= '0;
         expected_index_q    <= '0;
         pending_q           <= 1'b0;
         completed_batches_q <= '0;
      end else begin
         if (write_fire)
            batch[write_index] <= write_data;

         if (read_pop) begin
            expected_q       <= transpose_column(read_index);
            expected_index_q <= read_index;
            pending_q        <= 1'b1;
         end else if (dma_wr_data_vld && dma_wr_data_rdy) begin
            pending_q <= 1'b0;
         end

         if (dma_wr_data_vld && dma_wr_data_rdy &&
             pending_q && expected_index_q == 5'd31 &&
             completed_batches_q != 2'd3)
            completed_batches_q <= completed_batches_q + 1'b1;
      end
   end

   T_RUBIK_MERGE_TRANSPOSE: assert property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      (dma_wr_data_vld == pending_q) &&
      (!pending_q ||
       (dma_wr_data_pd[513:512] == 2'b11 &&
        dma_wr_data_pd[511:0] == expected_q))
   );

   // The consumer reserves its ready slot when the synchronous RAM read
   // launches; it may apply backpressure between reads, but cannot withdraw
   // that reservation before the corresponding output cycle.
   A_READY_RESERVATION: assume property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      read_pop |=> dma_wr_data_rdy
   );

   C_WRITE_BATCH: cover property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      write_fire && write_index == 5'd31
   );
   C_FIRST_READ: cover property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      read_pop && read_index == 5'd0
   );
   C_LAST_READ: cover property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      read_pop && read_index == 5'd31
   );
   C_RESERVED_OUTPUT: cover property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      read_pop ##1 (dma_wr_data_vld && dma_wr_data_rdy)
   );
   C_TWO_BATCHES: cover property (
      @(posedge nvdla_core_clk) disable iff (!nvdla_core_rstn)
      completed_batches_q >= 2
   );
endmodule
