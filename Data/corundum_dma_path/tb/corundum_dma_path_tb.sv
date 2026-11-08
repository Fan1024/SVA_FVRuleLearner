`timescale 1ns/1ps
`default_nettype none

module corundum_dma_targets (
    input wire clk,
    input wire rst,
    input wire df_req_sel,
    input wire df_req_queue,
    input wire [3:0] df_req_tag,
    input wire df_req_valid,
    input wire df_req_ready,
    input wire df_st_queue,
    input wire df_st_cpl,
    input wire [3:0] df_st_tag,
    input wire df_st_empty,
    input wire df_st_error,
    input wire df_st_valid,
    input wire [63:0] desc_tdata,
    input wire [7:0] desc_tkeep,
    input wire desc_tvalid,
    input wire desc_tready,
    input wire desc_tlast,
    input wire [3:0] desc_tid,
    input wire [1:0] dq_req_valid,
    input wire [1:0] dq_req_ready,
    input wire [1:0] dq_req_queue,
    input wire [7:0] dq_req_tag,
    input wire [1:0] dq_resp_valid,
    input wire [1:0] dq_resp_ready,
    input wire [1:0] dq_resp_queue,
    input wire [7:0] dq_resp_tag,
    input wire [3:0] dq_resp_optag,
    input wire [1:0] dq_resp_empty,
    input wire [1:0] dq_resp_error,
    input wire [3:0] dq_commit_optag,
    input wire [1:0] dq_commit_valid,
    input wire [1:0] dq_commit_ready,
    input wire [63:0] rd_addr,
    input wire [5:0] rd_ram,
    input wire [7:0] rd_len,
    input wire [3:0] rd_tag,
    input wire rd_valid,
    input wire rd_ready,
    input wire [3:0] rd_st_tag,
    input wire rd_st_val,
    input wire cw_req_sel,
    input wire cw_req_queue,
    input wire [3:0] cw_req_tag,
    input wire [63:0] cw_req_data,
    input wire cw_req_valid,
    input wire cw_req_ready,
    input wire [3:0] cw_st_tag,
    input wire cw_st_valid,
    input wire [1:0] cq_req_valid,
    input wire [1:0] cq_req_ready,
    input wire [1:0] cq_resp_valid,
    input wire [1:0] cq_resp_ready,
    input wire [1:0] cq_resp_queue,
    input wire [3:0] cq_resp_optag,
    input wire [1:0] cq_resp_full,
    input wire [1:0] cq_resp_error,
    input wire [3:0] cq_commit_optag,
    input wire [1:0] cq_commit_valid,
    input wire [1:0] cq_commit_ready,
    input wire [63:0] wr_addr,
    input wire [5:0] wr_ram,
    input wire [7:0] wr_len,
    input wire [3:0] wr_tag,
    input wire wr_valid,
    input wire wr_ready,
    input wire [3:0] wr_st_tag,
    input wire wr_st_val,
    input wire host_valid,
    input wire [63:0] host_addr,
    input wire [63:0] host_data,
    input wire [1:0] dq_adv,
    input wire [1:0] dq_adv_q,
    input wire [1:0] cq_adv,
    input wire [1:0] cq_adv_q,
    input wire configured,
    input wire [3:0] df_tbl_active,
    input wire [2:0] df_start_ptr,
    input wire [2:0] df_read_ptr,
    input wire [2:0] df_fin_ptr,
    input wire [2:0] df_active_cnt,
    input wire [3:0] cw_tbl_active,
    input wire [2:0] cw_start_ptr,
    input wire [2:0] cw_fin_ptr,
    input wire [3:0] qm0_op_active,
    input wire [3:0] qm1_op_active,
    input wire [3:0] cqm0_op_active,
    input wire [3:0] cqm1_op_active,
    input wire [127:0] qm0_q0,
    input wire [127:0] qm0_q1,
    input wire [127:0] cqm0_q0,
    input wire [127:0] cqm0_q1
);

localparam PORTS            = 2;
localparam DESC_TABLE_SIZE  = 4;
localparam CPL_TABLE_SIZE   = 4;
localparam OP_TABLE_SIZE    = 4;
localparam RING_SIZE        = 4;
localparam FIFO_N           = 8;
localparam SAT              = 10'd1023;

localparam N_BLOCK   = 10'd96;
localparam N_FETCH   = 10'd255;
localparam N_DESC    = 10'd255;
localparam N_CPL     = 10'd255;
localparam N_STALL   = 10'd255;
localparam N_FULL    = 10'd255;

wire        df_req_fire  = df_req_valid && df_req_ready;

wire        df_st_ok     = df_st_valid && !df_st_empty && !df_st_error;

wire        desc_beat   = desc_tvalid && desc_tready;

wire        rd_fire   = rd_valid && rd_ready;

wire        cw_req_fire  = cw_req_valid && cw_req_ready;

wire        wr_fire   = wr_valid && wr_ready;

wire [2:0]  df_span      = df_start_ptr - df_fin_ptr;
wire [2:0]  df_read_span = df_start_ptr - df_read_ptr;
wire [2:0]  cw_span      = cw_start_ptr - cw_fin_ptr;

function automatic [63:0] host_word(input [31:0] a);
    host_word = {a, ~a};
endfunction

reg [3:0] dqq_tag  [0:PORTS*4-1];
reg       dqq_q    [0:PORTS*4-1];
reg [2:0] dqq_wr   [0:PORTS-1];
reg [2:0] dqq_rd   [0:PORTS-1];

wire [1:0] dq_req_fire  = dq_req_valid & dq_req_ready;
wire [1:0] dq_resp_fire = dq_resp_valid & dq_resp_ready;

wire dqq0_empty = (dqq_wr[0] == dqq_rd[0]);
wire dqq1_empty = (dqq_wr[1] == dqq_rd[1]);
wire [3:0] dqq0_head_tag = dqq_tag[0*4 + dqq_rd[0][1:0]];
wire [3:0] dqq1_head_tag = dqq_tag[1*4 + dqq_rd[1][1:0]];
wire       dqq0_head_q   = dqq_q  [0*4 + dqq_rd[0][1:0]];
wire       dqq1_head_q   = dqq_q  [1*4 + dqq_rd[1][1:0]];

integer i;
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < PORTS; i = i + 1) begin
            dqq_wr[i] <= 3'd0;
            dqq_rd[i] <= 3'd0;
        end
    end else begin
        if (dq_req_fire[0]) begin
            dqq_tag[0*4 + dqq_wr[0][1:0]] <= dq_req_tag[3:0];
            dqq_q  [0*4 + dqq_wr[0][1:0]] <= dq_req_queue[0];
            dqq_wr[0] <= dqq_wr[0] + 3'd1;
        end
        if (dq_req_fire[1]) begin
            dqq_tag[1*4 + dqq_wr[1][1:0]] <= dq_req_tag[7:4];
            dqq_q  [1*4 + dqq_wr[1][1:0]] <= dq_req_queue[1];
            dqq_wr[1] <= dqq_wr[1] + 3'd1;
        end
        if (dq_resp_fire[0] && !dqq0_empty) dqq_rd[0] <= dqq_rd[0] + 3'd1;
        if (dq_resp_fire[1] && !dqq1_empty) dqq_rd[1] <= dqq_rd[1] + 3'd1;
    end
end

reg [3:0]  sq_tag  [0:FIFO_N-1];
reg [3:0]  sq_wr, sq_rd;
reg [31:0] fq_addr [0:FIFO_N-1];
reg [7:0]  fq_len  [0:FIFO_N-1];
reg [3:0]  fq_wr, fq_rd;
reg [1:0]  beat_idx;

wire sq_empty = (sq_wr == sq_rd);
wire fq_empty = (fq_wr == fq_rd);
wire [3:0]  sq_head_tag  = sq_tag [sq_rd[2:0]];
wire [31:0] fq_head_addr = fq_addr[fq_rd[2:0]];
wire [7:0]  fq_head_len  = fq_len [fq_rd[2:0]];
wire [3:0]  sq_occ = sq_wr - sq_rd;
wire [3:0]  fq_occ = fq_wr - fq_rd;

wire [63:0] desc_expect = host_word(fq_head_addr + {26'd0, beat_idx, 3'd0});

always @(posedge clk) begin
    if (rst) begin
        sq_wr <= 4'd0; sq_rd <= 4'd0;
        fq_wr <= 4'd0; fq_rd <= 4'd0;
        beat_idx <= 2'd0;
    end else begin
        if (df_st_ok) begin
            sq_tag[sq_wr[2:0]] <= df_st_tag;
            sq_wr <= sq_wr + 4'd1;
        end
        if (rd_fire) begin
            fq_addr[fq_wr[2:0]] <= rd_addr[31:0];
            fq_len [fq_wr[2:0]] <= rd_len;
            fq_wr <= fq_wr + 4'd1;
        end
        if (desc_beat && desc_tlast) begin
            if (!sq_empty) sq_rd <= sq_rd + 4'd1;
            if (!fq_empty) fq_rd <= fq_rd + 4'd1;
            beat_idx <= 2'd0;
        end else if (desc_beat) begin
            beat_idx <= beat_idx + 2'd1;
        end
    end
end

reg [15:0] rd_out;
reg [15:0] wr_out;

always @(posedge clk) begin
    if (rst) begin
        rd_out <= 16'd0;
        wr_out <= 16'd0;
    end else begin
        if (rd_fire)   rd_out[rd_tag]    <= 1'b1;
        if (rd_st_val) rd_out[rd_st_tag] <= 1'b0;
        if (wr_fire)   wr_out[wr_tag]    <= 1'b1;
        if (wr_st_val) wr_out[wr_st_tag] <= 1'b0;
    end
end

reg [3:0] dq_ops [0:PORTS-1];
reg [3:0] cq_ops [0:PORTS-1];

wire [1:0] dq_take = dq_resp_fire & ~dq_resp_empty & ~dq_resp_error;
wire [1:0] cq_take = (cq_resp_valid & cq_resp_ready) & ~cq_resp_full & ~cq_resp_error;
wire [1:0] dq_commit_fire = dq_commit_valid & dq_commit_ready;
wire [1:0] cq_commit_fire = cq_commit_valid & cq_commit_ready;

always @(posedge clk) begin
    if (rst) begin
        dq_ops[0] <= 4'd0; dq_ops[1] <= 4'd0;
        cq_ops[0] <= 4'd0; cq_ops[1] <= 4'd0;
    end else begin
        if (dq_take[0])        dq_ops[0][dq_resp_optag[1:0]]   <= 1'b1;
        if (dq_commit_fire[0]) dq_ops[0][dq_commit_optag[1:0]] <= 1'b0;
        if (dq_take[1])        dq_ops[1][dq_resp_optag[3:2]]   <= 1'b1;
        if (dq_commit_fire[1]) dq_ops[1][dq_commit_optag[3:2]] <= 1'b0;
        if (cq_take[0])        cq_ops[0][cq_resp_optag[1:0]]   <= 1'b1;
        if (cq_commit_fire[0]) cq_ops[0][cq_commit_optag[1:0]] <= 1'b0;
        if (cq_take[1])        cq_ops[1][cq_resp_optag[3:2]]   <= 1'b1;
        if (cq_commit_fire[1]) cq_ops[1][cq_commit_optag[3:2]] <= 1'b0;
    end
end

reg [63:0] cs_data [0:CPL_TABLE_SIZE-1];
reg [3:0]  cs_tag  [0:CPL_TABLE_SIZE-1];
reg [CPL_TABLE_SIZE-1:0] cs_live;
reg [1:0]  cs_idx;
reg [1:0]  hw_slot;

always @(posedge clk) begin
    if (rst) begin
        cs_live <= {CPL_TABLE_SIZE{1'b0}};
        cs_idx  <= 2'd0;
        hw_slot <= 2'd0;
    end else begin
        if (wr_st_val) cs_live[wr_st_tag[1:0]] <= 1'b0;
        if (cw_req_fire) begin
            cs_data[cs_idx] <= cw_req_data;
            cs_tag [cs_idx] <= cw_req_tag;
            cs_live[cs_idx] <= 1'b1;
            cs_idx <= cs_idx + 2'd1;
        end
        if (wr_fire) hw_slot <= wr_ram[4:3];
    end
end

reg [7:0] dring_post [0:PORTS*2-1];
reg [7:0] dring_take [0:PORTS*2-1];
reg [7:0] cring_make [0:PORTS*2-1];
reg [7:0] cring_eat  [0:PORTS*2-1];

wire [7:0] dring_bal0 = dring_post[0] - dring_take[0];
wire [7:0] dring_bal1 = dring_post[1] - dring_take[1];
wire [7:0] dring_bal2 = dring_post[2] - dring_take[2];
wire [7:0] dring_bal3 = dring_post[3] - dring_take[3];
wire [7:0] cring_occ0 = cring_make[0] - cring_eat[0];
wire [7:0] cring_occ1 = cring_make[1] - cring_eat[1];
wire [7:0] cring_occ2 = cring_make[2] - cring_eat[2];
wire [7:0] cring_occ3 = cring_make[3] - cring_eat[3];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < PORTS*2; i = i + 1) begin
            dring_post[i] <= 8'd0;
            dring_take[i] <= 8'd0;
            cring_make[i] <= 8'd0;
            cring_eat [i] <= 8'd0;
        end
    end else begin
        if (dq_adv[0]) dring_post[{1'b0, dq_adv_q[0]}] <= dring_post[{1'b0, dq_adv_q[0]}] + 8'd1;
        if (dq_adv[1]) dring_post[{1'b1, dq_adv_q[1]}] <= dring_post[{1'b1, dq_adv_q[1]}] + 8'd1;
        if (dq_take[0]) dring_take[{1'b0, dq_resp_queue[0]}] <= dring_take[{1'b0, dq_resp_queue[0]}] + 8'd1;
        if (dq_take[1]) dring_take[{1'b1, dq_resp_queue[1]}] <= dring_take[{1'b1, dq_resp_queue[1]}] + 8'd1;
        if (cq_take[0]) cring_make[{1'b0, cq_resp_queue[0]}] <= cring_make[{1'b0, cq_resp_queue[0]}] + 8'd1;
        if (cq_take[1]) cring_make[{1'b1, cq_resp_queue[1]}] <= cring_make[{1'b1, cq_resp_queue[1]}] + 8'd1;
        if (cq_adv[0]) cring_eat[{1'b0, cq_adv_q[0]}] <= cring_eat[{1'b0, cq_adv_q[0]}] + 8'd1;
        if (cq_adv[1]) cring_eat[{1'b1, cq_adv_q[1]}] <= cring_eat[{1'b1, cq_adv_q[1]}] + 8'd1;
    end
end

reg [9:0] n_req, n_status, n_fetched, n_delivered, n_cplreq, n_cplst, n_hostwr;

always @(posedge clk) begin
    if (rst) begin
        n_req <= 10'd0; n_status <= 10'd0; n_fetched <= 10'd0;
        n_delivered <= 10'd0; n_cplreq <= 10'd0; n_cplst <= 10'd0;
        n_hostwr <= 10'd0;
    end else begin
        if (df_req_fire && n_req     != SAT) n_req     <= n_req + 10'd1;
        if (df_st_valid && n_status  != SAT) n_status  <= n_status + 10'd1;
        if (df_st_ok    && n_fetched != SAT) n_fetched <= n_fetched + 10'd1;
        if (desc_beat && desc_tlast && n_delivered != SAT) n_delivered <= n_delivered + 10'd1;
        if (cw_req_fire && n_cplreq  != SAT) n_cplreq  <= n_cplreq + 10'd1;
        if (cw_st_valid && n_cplst   != SAT) n_cplst   <= n_cplst + 10'd1;
        if (host_valid  && n_hostwr  != SAT) n_hostwr  <= n_hostwr + 10'd1;
    end
end

wire [9:0] req_out = n_req - n_status;
wire [9:0] cpl_out = n_cplreq - n_cplst;

reg [2:0] cw_tagcnt [0:15];
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 16; i = i + 1) cw_tagcnt[i] <= 3'd0;
    end else begin

        if (!(cw_req_fire && cw_st_valid && cw_req_tag == cw_st_tag)) begin
            if (cw_req_fire) cw_tagcnt[cw_req_tag] <= cw_tagcnt[cw_req_tag] + 3'd1;
            if (cw_st_valid) cw_tagcnt[cw_st_tag]  <= cw_tagcnt[cw_st_tag]  - 3'd1;
        end
    end
end

reg [9:0] ctr_dq0_blocked, ctr_dq1_blocked, ctr_desc_blocked;
reg [9:0] age_fetch, age_desc, age_cpl, ctr_stall, ctr_full;

wire any_event = df_req_fire || df_st_valid || rd_fire || rd_st_val
                 || desc_beat || cw_req_fire || cw_st_valid
                 || wr_fire || wr_st_val || host_valid
                 || (|dq_resp_fire) || (|(cq_resp_valid & cq_resp_ready));
wire any_work  = (req_out != 10'd0) || (cpl_out != 10'd0)
                 || (rd_out != 16'd0) || (wr_out != 16'd0) || !sq_empty;

always @(posedge clk) begin
    if (rst) begin
        ctr_dq0_blocked <= 10'd0; ctr_dq1_blocked <= 10'd0;
        ctr_desc_blocked <= 10'd0;
        age_fetch <= 10'd0; age_desc <= 10'd0; age_cpl <= 10'd0;
        ctr_stall <= 10'd0; ctr_full <= 10'd0;
    end else begin
        if (dq_resp_valid[0] && !dq_resp_ready[0])
            ctr_dq0_blocked <= (ctr_dq0_blocked == SAT) ? SAT : ctr_dq0_blocked + 10'd1;
        else ctr_dq0_blocked <= 10'd0;

        if (dq_resp_valid[1] && !dq_resp_ready[1])
            ctr_dq1_blocked <= (ctr_dq1_blocked == SAT) ? SAT : ctr_dq1_blocked + 10'd1;
        else ctr_dq1_blocked <= 10'd0;

        if (desc_tvalid && !desc_tready)
            ctr_desc_blocked <= (ctr_desc_blocked == SAT) ? SAT : ctr_desc_blocked + 10'd1;
        else ctr_desc_blocked <= 10'd0;

        if (df_st_valid || req_out == 10'd0) age_fetch <= 10'd0;
        else age_fetch <= (age_fetch == SAT) ? SAT : age_fetch + 10'd1;

        if ((desc_beat && desc_tlast) || sq_empty) age_desc <= 10'd0;
        else age_desc <= (age_desc == SAT) ? SAT : age_desc + 10'd1;

        if (cw_st_valid || cpl_out == 10'd0) age_cpl <= 10'd0;
        else age_cpl <= (age_cpl == SAT) ? SAT : age_cpl + 10'd1;

        if (any_event || !any_work) ctr_stall <= 10'd0;
        else ctr_stall <= (ctr_stall == SAT) ? SAT : ctr_stall + 10'd1;

        if (df_tbl_active == 4'hF)
            ctr_full <= (ctr_full == SAT) ? SAT : ctr_full + 10'd1;
        else ctr_full <= 10'd0;
    end
end

wire desc_page_ok = (rd_addr[63:12] == 52'h00010) || (rd_addr[63:12] == 52'h00011)
                 || (rd_addr[63:12] == 52'h00020) || (rd_addr[63:12] == 52'h00021);
wire desc_off_ok  = (rd_addr[11:6] == 6'd0) && (rd_addr[3:0] == 4'd0);

wire cpl_page_ok  = (wr_addr[63:12] == 52'h00040) || (wr_addr[63:12] == 52'h00041)
                 || (wr_addr[63:12] == 52'h00080) || (wr_addr[63:12] == 52'h00081);
wire cpl_off_ok   = (wr_addr[11:5] == 7'd0) && (wr_addr[2:0] == 3'd0);

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
