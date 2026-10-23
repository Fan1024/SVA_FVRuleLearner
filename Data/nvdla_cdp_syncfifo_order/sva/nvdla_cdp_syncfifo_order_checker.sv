// Independent transaction-order model for the three stateful streams in the
// real CDP synchronization FIFO.  The CVT input creates paired data and info
// transactions that may drain independently; the SUM stream is separate.

module nvdla_cdp_syncfifo_order_checker (
   input wire         clk,
   input wire         reset_n,
   input wire         cvt_valid,
   input wire         cvt_ready,
   input wire [86:0]  cvt_pd,
   input wire         sum_valid,
   input wire         sum_ready,
   input wire [167:0] sum_pd,
   input wire         mul_valid,
   input wire         mul_ready,
   input wire [71:0]  mul_pd,
   input wire         ocvt_valid,
   input wire         ocvt_ready,
   input wire [14:0]  ocvt_pd,
   input wire         itp_valid,
   input wire         itp_ready,
   input wire [167:0] itp_pd
);
   wire cvt_fire = cvt_valid && cvt_ready;
   wire sum_fire = sum_valid && sum_ready;
   wire mul_fire = mul_valid && mul_ready;
   wire ocvt_fire = ocvt_valid && ocvt_ready;
   wire itp_fire = itp_valid && itp_ready;

   // The reference capacities exceed the corresponding real FIFO plus its
   // input elastic stage, so the reference model never constrains traffic.
   reg [71:0] data_ref [0:127];
   reg [14:0] info_ref [0:127];
   reg [167:0] sum_ref [0:63];

   reg [6:0] cvt_wptr;
   reg [6:0] data_rptr;
   reg [6:0] info_rptr;
   reg [7:0] data_count;
   reg [7:0] info_count;

   reg [5:0] sum_wptr;
   reg [5:0] sum_rptr;
   reg [6:0] sum_count;

   reg [7:0] cvt_accepts;
   reg [7:0] sum_accepts;
   reg [7:0] mul_outputs;
   reg [7:0] ocvt_outputs;
   reg [7:0] itp_outputs;
   reg mul_stall_seen;
   reg ocvt_stall_seen;
   reg itp_stall_seen;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         cvt_wptr <= 7'd0;
         data_rptr <= 7'd0;
         info_rptr <= 7'd0;
         data_count <= 8'd0;
         info_count <= 8'd0;
         sum_wptr <= 6'd0;
         sum_rptr <= 6'd0;
         sum_count <= 7'd0;
         cvt_accepts <= 8'd0;
         sum_accepts <= 8'd0;
         mul_outputs <= 8'd0;
         ocvt_outputs <= 8'd0;
         itp_outputs <= 8'd0;
         mul_stall_seen <= 1'b0;
         ocvt_stall_seen <= 1'b0;
         itp_stall_seen <= 1'b0;
      end else begin
         if (cvt_fire) begin
            data_ref[cvt_wptr] <= cvt_pd[71:0];
            info_ref[cvt_wptr] <= cvt_pd[86:72];
            cvt_wptr <= cvt_wptr + 7'd1;
            if (cvt_accepts != 8'hff)
               cvt_accepts <= cvt_accepts + 8'd1;
         end

         case ({cvt_fire, mul_fire})
            2'b10: data_count <= data_count + 8'd1;
            2'b01: data_count <= data_count - 8'd1;
            default: data_count <= data_count;
         endcase
         if (mul_fire) begin
            data_rptr <= data_rptr + 7'd1;
            if (mul_outputs != 8'hff)
               mul_outputs <= mul_outputs + 8'd1;
         end

         case ({cvt_fire, ocvt_fire})
            2'b10: info_count <= info_count + 8'd1;
            2'b01: info_count <= info_count - 8'd1;
            default: info_count <= info_count;
         endcase
         if (ocvt_fire) begin
            info_rptr <= info_rptr + 7'd1;
            if (ocvt_outputs != 8'hff)
               ocvt_outputs <= ocvt_outputs + 8'd1;
         end

         if (sum_fire) begin
            sum_ref[sum_wptr] <= sum_pd;
            sum_wptr <= sum_wptr + 6'd1;
            if (sum_accepts != 8'hff)
               sum_accepts <= sum_accepts + 8'd1;
         end
         case ({sum_fire, itp_fire})
            2'b10: sum_count <= sum_count + 7'd1;
            2'b01: sum_count <= sum_count - 7'd1;
            default: sum_count <= sum_count;
         endcase
         if (itp_fire) begin
            sum_rptr <= sum_rptr + 6'd1;
            if (itp_outputs != 8'hff)
               itp_outputs <= itp_outputs + 8'd1;
         end

         if (mul_valid && !mul_ready)
            mul_stall_seen <= 1'b1;
         if (ocvt_valid && !ocvt_ready)
            ocvt_stall_seen <= 1'b1;
         if (itp_valid && !itp_ready)
            itp_stall_seen <= 1'b1;
      end
   end

   T_SYNCFIFO_DATA_ORDER: assert property (@(posedge clk)
      disable iff (!reset_n)
      (!mul_valid ||
         (data_count != 0 && mul_pd == data_ref[data_rptr])) &&
      (!ocvt_valid ||
         (info_count != 0 && ocvt_pd == info_ref[info_rptr])) &&
      (!itp_valid ||
         (sum_count != 0 && itp_pd == sum_ref[sum_rptr])));

   C_CVT_FILL_64: cover property (@(posedge clk) disable iff (!reset_n)
      data_count >= 64 && info_count >= 64);
   C_SUM_FILL_48: cover property (@(posedge clk) disable iff (!reset_n)
      sum_count >= 48);
   C_CVT_FULL_WRAP: cover property (@(posedge clk) disable iff (!reset_n)
      cvt_accepts >= 112 && mul_outputs >= 96 && ocvt_outputs >= 96);
   C_SUM_FULL_WRAP: cover property (@(posedge clk) disable iff (!reset_n)
      sum_accepts >= 80 && itp_outputs >= 64);
   C_DATA_INFO_SKEW: cover property (@(posedge clk) disable iff (!reset_n)
      data_count >= 32 && info_count <= 4);
   C_INFO_DATA_SKEW: cover property (@(posedge clk) disable iff (!reset_n)
      info_count >= 32 && data_count <= 4);
   C_ALL_OUTPUTS_AFTER_STALL: cover property (@(posedge clk)
      disable iff (!reset_n)
      mul_stall_seen && ocvt_stall_seen && itp_stall_seen &&
      mul_outputs >= 8 && ocvt_outputs >= 8 && itp_outputs >= 8);
endmodule
