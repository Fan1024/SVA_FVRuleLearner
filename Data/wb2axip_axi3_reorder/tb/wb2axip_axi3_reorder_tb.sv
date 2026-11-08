`timescale 1ns/1ps
`default_nettype none

module axi3_reorder_targets (input wire clock, input wire reset,
    input logic aw_val,
    input logic aw_rdy,
    input logic [1:0] aw_id,
    input logic w_val,
    input logic w_rdy,
    input logic [1:0] w_id,
    input logic [7:0] w_dat,
    input logic w_stb,
    input logic w_lst,
    input logic m_val,
    input logic m_rdy,
    input logic [1:0] m_id,
    input logic [7:0] m_dat,
    input logic m_stb,
    input logic m_lst,
    input logic [15:0] sr_valid,
    input logic cid_valid,
    input logic [1:0] current_id,
    input logic [3:0] awf_fill,
    input logic [3:0] awf_wr,
    input logic [3:0] awf_rd
);

    localparam integer AR    = 32;
    localparam integer AWQ   = 16;
    localparam integer NSREG = 16;

    localparam [7:0] N_HEAD_STALL = 8'd8;
    localparam [7:0] N_AW_LOAD    = 8'd8;
    localparam [7:0] N_NO_MOVE    = 8'd16;
    localparam [7:0] N_AW_BLOCK   = 8'd24;
    localparam [7:0] CTR_MAX      = 8'd255;

    wire       push_aw = aw_val && aw_rdy;

    wire       push_w = w_val && w_rdy;

    wire       pop_w  = m_val && m_rdy;
    wire       pop_aw = pop_w && m_lst;

    reg [1:0] ar_id  [0:AR-1];
    reg [7:0] ar_dat [0:AR-1];
    reg       ar_stb [0:AR-1];
    reg       ar_lst [0:AR-1];
    reg [1:0] ar_pos [0:AR-1];
    reg       ar_liv [0:AR-1];
    reg [4:0] ar_wr;
    reg [5:0] ar_occ;

    reg [1:0] awq_id [0:AWQ-1];
    reg [3:0] awq_wr, awq_rd;
    reg [4:0] awq_occ;

    reg [5:0] id_live [0:3];
    reg [1:0] in_beat [0:3];

    reg [1:0] out_beat;
    reg       out_pkt_active;
    reg [1:0] out_pkt_id;

    reg [15:0] w_in_cnt, w_out_cnt, aw_in_cnt, aw_out_cnt;

    reg [7:0] head_stall_ctr;
    reg [7:0] aw_load_ctr;
    reg [7:0] no_move_ctr;
    reg [7:0] aw_block_ctr;
    reg       after_reset;
    reg       seen_two_ids_live;

    reg       first_found;
    reg [4:0] first_idx;
    reg [4:0] scan_ix;
    integer   j;
    always @* begin
        first_found = 1'b0;
        first_idx   = 5'd0;
        for (j = 0; j < AR; j = j + 1) begin
            scan_ix = ar_wr + j[4:0];
            if (!first_found && ar_liv[scan_ix] && (ar_id[scan_ix] == m_id))
                begin
                    first_found = 1'b1;
                    first_idx   = scan_ix;
                end
        end
    end

    reg [5:0] sr_fill;
    reg [7:0] live_sum;
    integer   k;
    always @* begin
        sr_fill = 6'd0;
        for (k = 0; k < NSREG; k = k + 1)
            if (sr_valid[k])
                sr_fill = sr_fill + 6'd1;
        live_sum = 8'd0;
        for (k = 0; k < 4; k = k + 1)
            live_sum = live_sum + {2'd0, id_live[k]};
    end

    wire [1:0] head_id      = awq_id[awq_rd];
    wire       head_has_beat = (awq_occ != 5'd0) && (id_live[head_id] != 6'd0);
    wire [3:0] awq_rd_next  = awq_rd + 4'd1;
    wire [1:0] expect_cid   = (m_val && m_lst) ? awq_id[awq_rd_next]
                                               : awq_id[awq_rd];

    integer u;
    always @(posedge clock) begin
        after_reset <= reset;
        if (reset) begin
            ar_wr <= 5'd0;
            ar_occ <= 6'd0;
            awq_wr <= 4'd0; awq_rd <= 4'd0; awq_occ <= 5'd0;
            out_beat <= 2'd0;
            out_pkt_active <= 1'b0;
            out_pkt_id <= 2'd0;
            w_in_cnt <= 16'd0; w_out_cnt <= 16'd0;
            aw_in_cnt <= 16'd0; aw_out_cnt <= 16'd0;
            head_stall_ctr <= 8'd0;
            aw_load_ctr <= 8'd0;
            no_move_ctr <= 8'd0;
            aw_block_ctr <= 8'd0;
            seen_two_ids_live <= 1'b0;
            for (u = 0; u < 4; u = u + 1) begin
                id_live[u] <= 6'd0;
                in_beat[u] <= 2'd0;
            end
            for (u = 0; u < AR; u = u + 1)
                ar_liv[u] <= 1'b0;
        end else begin

            if (push_w) begin
                ar_id[ar_wr]  <= w_id;
                ar_dat[ar_wr] <= w_dat;
                ar_stb[ar_wr] <= w_stb;
                ar_lst[ar_wr] <= w_lst;
                ar_pos[ar_wr] <= in_beat[w_id];
                ar_liv[ar_wr] <= 1'b1;
                ar_wr <= ar_wr + 5'd1;
                in_beat[w_id] <= w_lst ? 2'd0 : (in_beat[w_id] + 2'd1);
                if (w_in_cnt != 16'hffff)
                    w_in_cnt <= w_in_cnt + 16'd1;
            end
            if (pop_w && first_found)
                ar_liv[first_idx] <= 1'b0;
            ar_occ <= ar_occ + {5'd0, push_w} - {5'd0, pop_w};

            for (u = 0; u < 4; u = u + 1)
                id_live[u] <= id_live[u]
                    + {5'd0, (push_w && (w_id == u[1:0]))}
                    - {5'd0, (pop_w  && (m_id == u[1:0]))};
            if ((id_live[0] != 6'd0) && (id_live[1] != 6'd0))
                seen_two_ids_live <= 1'b1;

            if (push_aw) begin
                awq_id[awq_wr] <= aw_id;
                awq_wr <= awq_wr + 4'd1;
                if (aw_in_cnt != 16'hffff)
                    aw_in_cnt <= aw_in_cnt + 16'd1;
            end
            if (pop_aw) begin
                awq_rd <= awq_rd + 4'd1;
                if (aw_out_cnt != 16'hffff)
                    aw_out_cnt <= aw_out_cnt + 16'd1;
            end
            awq_occ <= awq_occ + {4'd0, push_aw} - {4'd0, pop_aw};

            if (pop_w) begin
                if (w_out_cnt != 16'hffff)
                    w_out_cnt <= w_out_cnt + 16'd1;
                if (!out_pkt_active) begin
                    out_pkt_id     <= m_id;
                    out_pkt_active <= !m_lst;
                    out_beat       <= m_lst ? 2'd0 : 2'd1;
                end else if (m_lst) begin
                    out_pkt_active <= 1'b0;
                    out_beat       <= 2'd0;
                end else begin
                    out_beat       <= out_beat + 2'd1;
                end
            end

            if (!head_has_beat || !m_rdy || pop_w)
                head_stall_ctr <= 8'd0;
            else if (head_stall_ctr != CTR_MAX)
                head_stall_ctr <= head_stall_ctr + 8'd1;

            if ((awq_occ == 5'd0) || cid_valid || !m_rdy || pop_aw)
                aw_load_ctr <= 8'd0;
            else if (aw_load_ctr != CTR_MAX)
                aw_load_ctr <= aw_load_ctr + 8'd1;

            if (!head_has_beat || !m_rdy || pop_w || push_w || push_aw)
                no_move_ctr <= 8'd0;
            else if (no_move_ctr != CTR_MAX)
                no_move_ctr <= no_move_ctr + 8'd1;

            if (!aw_val || aw_rdy || !m_rdy || !head_has_beat)
                aw_block_ctr <= 8'd0;
            else if (aw_block_ctr != CTR_MAX)
                aw_block_ctr <= aw_block_ctr + 8'd1;
        end
    end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
