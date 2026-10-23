// Independent end-to-end data-order checker.  Accepted MCIF read responses
// are the reference stream; accepted MCIF write-data packets must consume that
// stream in the same order across the real BDMA response, latency-FIFO,
// command-context, and write pipelines.

module nvdla_bdma_data_order_checker (
   input wire         clk,
   input wire         reset_n,
   input wire         cmd_valid,
   input wire         cmd_ready,
   input wire         rd_req_valid,
   input wire         rd_req_ready,
   input wire [78:0]  rd_req_pd,
   input wire         rd_rsp_valid,
   input wire         rd_rsp_ready,
   input wire [513:0] rd_rsp_pd,
   input wire         wr_req_valid,
   input wire         wr_req_ready,
   input wire [514:0] wr_req_pd
);
   localparam integer REF_DEPTH = 64;

   wire cmd_fire = cmd_valid && cmd_ready;
   wire rd_req_fire = rd_req_valid && rd_req_ready;
   wire rd_rsp_fire = rd_rsp_valid && rd_rsp_ready;
   wire wr_data_fire =
      wr_req_valid && wr_req_ready && wr_req_pd[514];

   reg [6:0] outstanding_beats;
   reg [6:0] ref_count;
   reg [5:0] ref_wr_ptr;
   reg [5:0] ref_rd_ptr;
   reg [511:0] ref_mem [0:REF_DEPTH-1];
   reg [2:0] commands_seen;

   // The fixed command issues one eight-beat request per line.  Memory may
   // backpressure arbitrarily, but it may not return an unissued beat or grow
   // the independent reference queue past its declared concurrency window.
   A_CMD_HOLD: assume property (@(posedge clk) disable iff (!reset_n)
      cmd_valid && !cmd_ready |=> cmd_valid);
   A_RSP_HOLD: assume property (@(posedge clk) disable iff (!reset_n)
      rd_rsp_valid && !rd_rsp_ready |=>
         rd_rsp_valid && $stable(rd_rsp_pd));
   A_RSP_HAS_REQUEST: assume property (@(posedge clk) disable iff (!reset_n)
      rd_rsp_valid |-> outstanding_beats != 0);
   A_READ_WINDOW: assume property (@(posedge clk) disable iff (!reset_n)
      rd_req_valid && outstanding_beats > 7'd56 |-> !rd_req_ready);
   A_REFERENCE_WINDOW: assume property (@(posedge clk) disable iff (!reset_n)
      ref_count == REF_DEPTH && !wr_data_fire |-> !rd_rsp_valid);

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         outstanding_beats <= 7'd0;
         ref_count <= 7'd0;
         ref_wr_ptr <= 6'd0;
         ref_rd_ptr <= 6'd0;
         commands_seen <= 3'd0;
      end else begin
         case ({rd_req_fire, rd_rsp_fire})
            2'b10: outstanding_beats <= outstanding_beats + 7'd8;
            2'b01: outstanding_beats <= outstanding_beats - 7'd1;
            2'b11: outstanding_beats <= outstanding_beats + 7'd7;
            default: outstanding_beats <= outstanding_beats;
         endcase

         case ({rd_rsp_fire, wr_data_fire})
            2'b10: ref_count <= ref_count + 7'd1;
            2'b01: ref_count <= ref_count - 7'd1;
            default: ref_count <= ref_count;
         endcase
         if (rd_rsp_fire) begin
            ref_mem[ref_wr_ptr] <= rd_rsp_pd[511:0];
            ref_wr_ptr <= ref_wr_ptr + 6'd1;
         end
         if (wr_data_fire) begin
            ref_rd_ptr <= ref_rd_ptr + 6'd1;
         end
         if (cmd_fire && commands_seen != 3'd7) begin
            commands_seen <= commands_seen + 3'd1;
         end
      end
   end

   T_DATA_ORDER: assert property (@(posedge clk) disable iff (!reset_n)
      wr_data_fire |->
         ref_count != 0 && wr_req_pd[511:0] == ref_mem[ref_rd_ptr]);

   C_COMMAND: cover property (@(posedge clk) disable iff (!reset_n)
      cmd_fire);
   C_TWO_COMMANDS: cover property (@(posedge clk) disable iff (!reset_n)
      commands_seen >= 2);
   C_READ_REQUEST: cover property (@(posedge clk) disable iff (!reset_n)
      rd_req_fire);
   C_RESPONSE: cover property (@(posedge clk) disable iff (!reset_n)
      rd_rsp_fire);
   C_REFERENCE_DEPTH16: cover property (@(posedge clk) disable iff (!reset_n)
      ref_count >= 16);
   C_WRITE_DATA: cover property (@(posedge clk) disable iff (!reset_n)
      wr_data_fire);
   C_SIMULTANEOUS_IO: cover property (@(posedge clk) disable iff (!reset_n)
      rd_rsp_fire && wr_data_fire);

endmodule
