`timescale 1ns/1ps
`default_nettype none

module nvdla_rubik_targets (input wire clk, input wire reset_n,
    input logic wr_vld,
    input logic wr_rdy,
    input logic write_fire,
    input logic [4:0] write_index,
    input logic [511:0] write_data,
    input logic rd_vld,
    input logic rd_rdy,
    input logic read_fire,
    input logic [4:0] read_index,
    input logic out_valid,
    input logic out_ready,
    input logic [513:0] out_pd,
    input logic p1_skid,
    input logic p1_pipe,
    input logic p2_skid,
    input logic p2_pipe,
    input logic [1:0] wptr,
    input logic [1:0] rptr,
    input logic rf_full,
    input logic rf_empty,
    input logic wr_pop,
    input logic wr_odone,
    input logic [4:0] wr_oaddr,
    input logic [511:0] wr_odata,
    input logic wr_osel,
    input logic rd_pop,
    input logic rd_odone,
    input logic [4:0] rd_oaddr,
    input logic [4:0] rd_oaddr_d,
    input logic rd_osel,
    input logic [159:0] ram_rd_ov,
    input logic m_contract,
    input logic m_split,
    input logic m_byte,
    input logic pkg_pending,
    input logic [4:0] pkg_index
);

   localparam [9:0] N_OUT_WAIT  = 10'd8;
   localparam [9:0] N_POP_WAIT  = 10'd16;
   localparam [9:0] N_STALL     = 10'd32;

   wire         out_fire   = out_valid && out_ready;

   function automatic [15:0] fold16_512(input [511:0] x);
      integer k;
      begin
         fold16_512 = 16'd0;
         for (k = 0; k < 32; k = k + 1)
            fold16_512 = fold16_512 ^ x[16*k +: 16];
      end
   endfunction

   function automatic [7:0] fold8_512(input [511:0] x);
      integer k;
      begin
         fold8_512 = 8'd0;
         for (k = 0; k < 64; k = k + 1)
            fold8_512 = fold8_512 ^ x[8*k +: 8];
      end
   endfunction

   function automatic [4:0] fold5_160(input [159:0] x);
      integer k;
      begin
         fold5_160 = 5'd0;
         for (k = 0; k < 32; k = k + 1)
            fold5_160 = fold5_160 ^ x[5*k +: 5];
      end
   endfunction

   reg [2:0] wr_inflight;
   reg [2:0] rd_inflight;
   reg [1:0] banks_ready;
   reg [4:0] wr_rows;
   reg [4:0] rd_cols;
   reg [1:0] out_owed;
   reg [4:0] out_col;

   reg [15:0] wr_in_fold;
   reg [15:0] wr_out_fold;
   reg [7:0]  col_fold [0:31];
   reg        fold_ready;

   reg [9:0] ctr_out, ctr_rdpop, ctr_wrpop, ctr_stall;

   reg post_reset;
   reg out_stall_q;

   wire can_out   = (out_owed != 2'd0) && out_ready;
   wire can_rdpop = rd_vld && (banks_ready != 2'd0) && out_ready;
   wire can_wrpop = wr_vld && (banks_ready != 2'd2);
   wire any_move  = write_fire || read_fire || wr_pop || rd_pop || out_fire;

   integer c;
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         wr_inflight <= 3'd0;
         rd_inflight <= 3'd0;
         banks_ready <= 2'd0;
         wr_rows     <= 5'd0;
         rd_cols     <= 5'd0;
         out_owed    <= 2'd0;
         out_col     <= 5'd0;
         wr_in_fold  <= 16'd0;
         wr_out_fold <= 16'd0;
         fold_ready  <= 1'b0;
         ctr_out     <= 10'd0;
         ctr_rdpop   <= 10'd0;
         ctr_wrpop   <= 10'd0;
         ctr_stall   <= 10'd0;
         post_reset  <= 1'b0;
         out_stall_q <= 1'b0;
         for (c = 0; c < 32; c = c + 1) col_fold[c] <= 8'd0;
      end else begin
         post_reset  <= 1'b1;
         out_stall_q <= out_valid && !out_ready;

         wr_inflight <= wr_inflight + (write_fire ? 3'd1 : 3'd0)
                                    - (wr_pop     ? 3'd1 : 3'd0);
         rd_inflight <= rd_inflight + (read_fire ? 3'd1 : 3'd0)
                                    - (rd_pop    ? 3'd1 : 3'd0);
         banks_ready <= banks_ready + (wr_odone ? 2'd1 : 2'd0)
                                    - (rd_odone ? 2'd1 : 2'd0);

         if (wr_pop) wr_rows <= wr_odone ? 5'd0 : (wr_rows + 5'd1);
         if (rd_pop) rd_cols <= rd_odone ? 5'd0 : (rd_cols + 5'd1);

         out_owed <= out_owed + (rd_pop   ? 2'd1 : 2'd0)
                              - (out_fire ? 2'd1 : 2'd0);
         if (rd_pop) out_col <= rd_cols;

         if (write_fire) wr_in_fold  <= wr_in_fold  ^ fold16_512(write_data);
         if (wr_pop)     wr_out_fold <= wr_out_fold ^ fold16_512(wr_odata);

         if (write_fire) begin
            for (c = 0; c < 32; c = c + 1)
               col_fold[c] <= ((write_index == 5'd0) ? 8'd0 : col_fold[c])
                              ^ write_data[16*c +: 8] ^ write_data[16*c + 8 +: 8];
         end
         if (write_fire && (write_index == 5'd0))       fold_ready <= 1'b0;
         else if (write_fire && (write_index == 5'd31)) fold_ready <= 1'b1;

         ctr_out   <= !(can_out && !out_fire) ? 10'd0
                    : (ctr_out == 10'd1023) ? ctr_out : ctr_out + 10'd1;
         ctr_rdpop <= !(can_rdpop && !rd_pop) ? 10'd0
                    : (ctr_rdpop == 10'd1023) ? ctr_rdpop : ctr_rdpop + 10'd1;
         ctr_wrpop <= !(can_wrpop && !wr_pop) ? 10'd0
                    : (ctr_wrpop == 10'd1023) ? ctr_wrpop : ctr_wrpop + 10'd1;
         ctr_stall <= !((can_out || can_rdpop || can_wrpop) && !any_move) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   wire [1:0] bank_gap = wptr - rptr;

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
