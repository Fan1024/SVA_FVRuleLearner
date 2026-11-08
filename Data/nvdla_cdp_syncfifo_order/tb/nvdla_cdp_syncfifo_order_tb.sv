`timescale 1ns/1ps
`default_nettype none

module nvdla_cdp_targets (input wire clk, input wire reset_n,
    input logic cvt_valid,
    input logic cvt_ready,
    input logic [86:0] cvt_pd,
    input logic sum_valid,
    input logic sum_ready,
    input logic [167:0] sum_pd,
    input logic mul_valid,
    input logic mul_ready,
    input logic [71:0] mul_pd,
    input logic ocvt_valid,
    input logic ocvt_ready,
    input logic [14:0] ocvt_pd,
    input logic itp_valid,
    input logic itp_ready,
    input logic [167:0] itp_pd,
    input logic p1_valid,
    input logic p2_valid,
    input logic [6:0] d_wr_count,
    input logic [6:0] d_rd_count,
    input logic [6:0] d_wr_adr,
    input logic [6:0] d_rd_adr,
    input logic d_push,
    input logic d_pop,
    input logic [6:0] i_wr_count,
    input logic [6:0] i_rd_count,
    input logic [6:0] i_wr_adr,
    input logic [6:0] i_rd_adr,
    input logic i_push,
    input logic i_pop,
    input logic [5:0] s_wr_count,
    input logic [5:0] s_rd_count,
    input logic [5:0] s_wr_adr,
    input logic [5:0] s_rd_adr,
    input logic s_push,
    input logic s_pop,
    input logic s_rd_push,
    input logic d_rd_push,
    input logic i_rd_push,
    input logic [7:0] pkg_data_count,
    input logic [7:0] pkg_info_count,
    input logic [6:0] pkg_sum_count
);

   localparam [7:0] N_CVT_PATH = 8'd82;
   localparam [7:0] N_SUM_PATH = 8'd61;
   localparam [9:0] N_DELIVER  = 10'd32;
   localparam [9:0] N_STALL    = 10'd64;

   wire cvt_fire  = cvt_valid  && cvt_ready;
   wire sum_fire  = sum_valid  && sum_ready;
   wire mul_fire  = mul_valid  && mul_ready;
   wire ocvt_fire = ocvt_valid && ocvt_ready;
   wire itp_fire  = itp_valid  && itp_ready;

   reg [7:0] data_held;
   reg [7:0] info_held;
   reg [7:0] sum_held;

   reg [71:0]  cvt_data_xor, mul_xor;
   reg [14:0]  cvt_info_xor, ocvt_xor;
   reg [167:0] sum_in_xor,   itp_xor;

   reg [9:0] ctr_mul, ctr_ocvt, ctr_itp, ctr_stall;

   reg post_reset;
   reg mul_stall_q, ocvt_stall_q, itp_stall_q;

   wire can_mul  = mul_ready  && (data_held != 8'd0);
   wire can_ocvt = ocvt_ready && (info_held != 8'd0);
   wire can_itp  = itp_ready  && (sum_held  != 8'd0);
   wire any_out  = mul_fire || ocvt_fire || itp_fire;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         data_held    <= 8'd0;
         info_held    <= 8'd0;
         sum_held     <= 8'd0;
         cvt_data_xor <= 72'd0;
         mul_xor      <= 72'd0;
         cvt_info_xor <= 15'd0;
         ocvt_xor     <= 15'd0;
         sum_in_xor   <= 168'd0;
         itp_xor      <= 168'd0;
         ctr_mul      <= 10'd0;
         ctr_ocvt     <= 10'd0;
         ctr_itp      <= 10'd0;
         ctr_stall    <= 10'd0;
         post_reset   <= 1'b0;
         mul_stall_q  <= 1'b0;
         ocvt_stall_q <= 1'b0;
         itp_stall_q  <= 1'b0;
      end else begin
         post_reset   <= 1'b1;
         mul_stall_q  <= mul_valid  && !mul_ready;
         ocvt_stall_q <= ocvt_valid && !ocvt_ready;
         itp_stall_q  <= itp_valid  && !itp_ready;

         data_held <= data_held + (cvt_fire ? 8'd1 : 8'd0)
                                - (mul_fire ? 8'd1 : 8'd0);
         info_held <= info_held + (cvt_fire  ? 8'd1 : 8'd0)
                                - (ocvt_fire ? 8'd1 : 8'd0);
         sum_held  <= sum_held  + (sum_fire ? 8'd1 : 8'd0)
                                - (itp_fire ? 8'd1 : 8'd0);

         if (cvt_fire)  cvt_data_xor <= cvt_data_xor ^ cvt_pd[71:0];
         if (cvt_fire)  cvt_info_xor <= cvt_info_xor ^ cvt_pd[86:72];
         if (sum_fire)  sum_in_xor   <= sum_in_xor   ^ sum_pd;
         if (mul_fire)  mul_xor      <= mul_xor      ^ mul_pd;
         if (ocvt_fire) ocvt_xor     <= ocvt_xor     ^ ocvt_pd;
         if (itp_fire)  itp_xor      <= itp_xor      ^ itp_pd;

         ctr_mul   <= !(can_mul  && !mul_fire)  ? 10'd0
                    : (ctr_mul  == 10'd1023) ? ctr_mul  : ctr_mul  + 10'd1;
         ctr_ocvt  <= !(can_ocvt && !ocvt_fire) ? 10'd0
                    : (ctr_ocvt == 10'd1023) ? ctr_ocvt : ctr_ocvt + 10'd1;
         ctr_itp   <= !(can_itp  && !itp_fire)  ? 10'd0
                    : (ctr_itp  == 10'd1023) ? ctr_itp  : ctr_itp  + 10'd1;
         ctr_stall <= !((can_mul || can_ocvt || can_itp) && !any_out) ? 10'd0
                    : (ctr_stall == 10'd1023) ? ctr_stall : ctr_stall + 10'd1;
      end
   end

   wire [7:0] d_gap = (d_wr_adr >= d_rd_adr) ? ({1'b0, d_wr_adr} - {1'b0, d_rd_adr})
                                             : ({1'b0, d_wr_adr} + 8'd80 - {1'b0, d_rd_adr});
   wire [7:0] i_gap = (i_wr_adr >= i_rd_adr) ? ({1'b0, i_wr_adr} - {1'b0, i_rd_adr})
                                             : ({1'b0, i_wr_adr} + 8'd80 - {1'b0, i_rd_adr});
   wire [7:0] s_gap = (s_wr_adr >= s_rd_adr) ? ({2'd0, s_wr_adr} - {2'd0, s_rd_adr})
                                             : ({2'd0, s_wr_adr} + 8'd60 - {2'd0, s_rd_adr});

   wire [7:0] d_stages = {7'd0, p1_valid} + {1'b0, d_rd_count} + {7'd0, mul_valid};
   wire [7:0] i_stages = {7'd0, p2_valid} + {1'b0, i_rd_count} + {7'd0, ocvt_valid};
   wire [7:0] s_stages = {2'd0, s_rd_count} + {7'd0, itp_valid};

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
