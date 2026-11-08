`timescale 1ns/1ps
`default_nettype none

module corundum_txrx_targets (input wire clk, input wire rst,
    input logic configured,
    input logic txreq_queue,
    input logic [2:0] txreq_tag,
    input logic [4:0] txreq_dest,
    input logic txreq_valid,
    input logic txreq_ready,
    input logic txreq_st_valid,
    input logic tdr_valid,
    input logic tdr_ready,
    input logic rdr_valid,
    input logic rdr_ready,
    input logic df_req_sel,
    input logic df_req_queue,
    input logic [3:0] df_req_tag,
    input logic df_req_valid,
    input logic df_req_ready,
    input logic df_st_empty,
    input logic df_st_error,
    input logic df_st_valid,
    input logic [127:0] df_desc_tdata,
    input logic [15:0] df_desc_tkeep,
    input logic df_desc_tvalid,
    input logic df_desc_tready,
    input logic df_desc_tlast,
    input logic [3:0] df_desc_tid,
    input logic [127:0] txd_tdata,
    input logic txd_tvalid,
    input logic txd_tready,
    input logic [127:0] rxd_tdata,
    input logic rxd_tvalid,
    input logic rxd_tready,
    input logic [1:0] dq_req_valid,
    input logic [1:0] dq_req_ready,
    input logic [1:0] dq_req_queue,
    input logic [7:0] dq_req_tag,
    input logic [1:0] dq_resp_valid,
    input logic [1:0] dq_resp_ready,
    input logic [1:0] dq_resp_queue,
    input logic [7:0] dq_resp_tag,
    input logic [3:0] dq_resp_optag,
    input logic [1:0] dq_resp_empty,
    input logic [1:0] dq_resp_error,
    input logic [3:0] dq_commit_optag,
    input logic [1:0] dq_commit_valid,
    input logic [1:0] dq_commit_ready,
    input logic [63:0] dh_addr,
    input logic [15:0] dh_len,
    input logic [3:0] dh_tag,
    input logic dh_valid,
    input logic dh_ready,
    input logic [3:0] dh_st_tag,
    input logic dh_st_valid,
    input logic [63:0] th_addr,
    input logic [15:0] th_len,
    input logic [3:0] th_tag,
    input logic th_valid,
    input logic th_ready,
    input logic [3:0] th_st_tag,
    input logic th_st_valid,
    input logic [63:0] rh_addr,
    input logic [15:0] rh_len,
    input logic [3:0] rh_tag,
    input logic rh_valid,
    input logic rh_ready,
    input logic [3:0] rh_st_tag,
    input logic rh_st_valid,
    input logic rxhw_valid,
    input logic [63:0] rxhw_addr,
    input logic [63:0] rxhw_data,
    input logic [63:0] ch_addr,
    input logic [15:0] ch_len,
    input logic [3:0] ch_tag,
    input logic ch_valid,
    input logic ch_ready,
    input logic [3:0] ch_st_tag,
    input logic ch_st_valid,
    input logic cplhw_valid,
    input logic [63:0] cplhw_addr,
    input logic [255:0] cplhw_data,
    input logic [63:0] iftx_tdata,
    input logic [7:0] iftx_tkeep,
    input logic iftx_tvalid,
    input logic iftx_tready,
    input logic iftx_tlast,
    input logic [4:0] iftx_tdest,
    input logic [3:0] iftx_tuser,
    input logic [63:0] mactx_tdata,
    input logic [1:0] mactx_tvalid,
    input logic [1:0] mactx_tready,
    input logic [1:0] mactx_tlast,
    input logic [7:0] mactx_tuser,
    input logic [63:0] ifrx_tdata,
    input logic ifrx_tvalid,
    input logic ifrx_tready,
    input logic ifrx_tlast,
    input logic ifrx_tid,
    input logic [15:0] txfifo_depth0,
    input logic [15:0] txfifo_depth1,
    input logic [15:0] rxfifo_depth0,
    input logic [15:0] rxfifo_depth1,
    input logic [2:0] txcpl_tag,
    input logic txcpl_valid,
    input logic txcpl_ready,
    input logic [1:0] maccpl_valid,
    input logic [1:0] maccpl_ready,
    input logic tcr_valid,
    input logic tcr_ready,
    input logic rcr_valid,
    input logic rcr_ready,
    input logic cw_req_queue,
    input logic [3:0] cw_req_tag,
    input logic cw_req_valid,
    input logic cw_req_ready,
    input logic cq_req_valid,
    input logic cq_req_ready,
    input logic cq_resp_valid,
    input logic cq_resp_ready,
    input logic cq_resp_queue,
    input logic [1:0] cq_resp_optag,
    input logic cq_resp_full,
    input logic cq_resp_error,
    input logic [1:0] cq_commit_optag,
    input logic cq_commit_valid,
    input logic cq_commit_ready,
    input logic [2:0] df_active_count,
    input logic [2:0] df_start_ptr,
    input logic [2:0] df_finish_ptr,
    input logic [3:0] df_table_active,
    input logic [3:0] txe_table_active,
    input logic [3:0] rxe_table_active,
    input logic [3:0] cw_table_active,
    input logic [3:0] txqm_op_active,
    input logic [3:0] cqm_op_active
);

localparam DF_TABLE_SIZE = 4;
localparam TX_TABLE_SIZE = 4;
localparam RX_TABLE_SIZE = 4;
localparam CW_TABLE_SIZE = 4;
localparam OP_TABLE_SIZE = 4;
localparam RING_SIZE     = 4;
localparam MAC_FIFO_BYTES = 128;

localparam FIFO_N  = 8;
localparam FIFO_AW = 3;

localparam CSAT = 12'd4095;
localparam TSAT = 12'd4095;

localparam N_BLOCK    = 12'd200;
localparam N_FETCH    = 12'd400;
localparam N_PKT      = 12'd1500;

localparam N_TXCPL    = 12'd64;
localparam N_PROGRESS = 12'd400;
localparam N_DFFULL   = 12'd400;

wire        txreq_fire   = txreq_valid && txreq_ready;

wire        df_req_fire  = df_req_valid && df_req_ready;

wire        df_st_ok     = df_st_valid && !df_st_empty && !df_st_error;

wire         df_desc_beat   = df_desc_tvalid && df_desc_tready;

wire         txd_beat   = txd_tvalid && txd_tready;

wire         rxd_beat   = rxd_tvalid && rxd_tready;

wire        dh_fire  = dh_valid && dh_ready;

wire        th_fire  = th_valid && th_ready;

wire        rh_fire  = rh_valid && rh_ready;

wire        ch_fire  = ch_valid && ch_ready;

wire        iftx_beat   = iftx_tvalid && iftx_tready;
wire        iftx_port   = iftx_tdest[4];

wire        ifrx_beat   = ifrx_tvalid && ifrx_tready;

wire        cw_req_fire  = cw_req_valid && cw_req_ready;

function automatic [63:0] host_word(input [63:0] a);
    host_word = {a[31:0], ~a[31:0]};
endfunction

function automatic [31:0] tx_pbuf(input [63:0] a);
    tx_pbuf = 32'h4000_0000 | ({16'd0, a[15:0]} << 8);
endfunction

function automatic [31:0] rx_pbuf(input [63:0] a);
    rx_pbuf = 32'h8000_0000 | ({16'd0, a[15:0]} << 8);
endfunction

function automatic [127:0] desc_word(input [63:0] a);
    reg [31:0] len;
    reg [63:0] pbuf;
    begin
        if (a[17]) begin
            len  = 32'd64;
            pbuf = {32'h0000_0000, rx_pbuf(a)};
        end else begin
            len  = a[4] ? 32'd16 : 32'd8;
            pbuf = {32'h0000_0000, tx_pbuf(a)};
        end
        desc_word = {pbuf, len, 32'h0000_0000};
    end
endfunction

function automatic [11:0] sat_inc(input [11:0] v);
    sat_inc = (v == CSAT) ? CSAT : v + 12'd1;
endfunction

integer i;

reg [4:0]        dqq_mem   [0:1][0:FIFO_N-1];
reg [FIFO_AW:0]  dqq_wr    [0:1];
reg [FIFO_AW:0]  dqq_rd    [0:1];
reg              dqq_bad   [0:1];

reg [63:0]       dfq_mem [0:FIFO_N-1];
reg [FIFO_AW:0]  dfq_wr;
reg [FIFO_AW:0]  dfq_rd;
reg              dfq_bad;

reg [31:0]       tbq_addr [0:FIFO_N-1];
reg [15:0]       tbq_len  [0:FIFO_N-1];
reg [FIFO_AW:0]  tbq_wr;
reg [FIFO_AW:0]  tbq_rd;
reg              tbq_bad;

reg [31:0]       rbq_addr [0:FIFO_N-1];
reg [FIFO_AW:0]  rbq_wr;
reg [FIFO_AW:0]  rbq_rd;
reg              rbq_bad;

reg [31:0]       tpq_mem [0:1][0:FIFO_N-1];
reg [FIFO_AW:0]  tpq_wr  [0:1];
reg [FIFO_AW:0]  tpq_rd  [0:1];
reg              tpq_bad [0:1];

reg [31:0]       rpq_mem [0:FIFO_N-1];
reg [FIFO_AW:0]  rpq_wr;
reg [FIFO_AW:0]  rpq_rd;
reg              rpq_bad;

reg [15:0] dh_out;
reg [15:0] th_out;
reg [15:0] rh_out;
reg [15:0] ch_out;
reg [3:0]  dqop_out [0:1];
reg [3:0]  cqop_out;

reg dh_reuse, th_reuse, rh_reuse, ch_reuse;
reg dh_unsol, th_unsol, rh_unsol, ch_unsol;
reg dqop_reuse, cqop_reuse;
reg dq_commit_stale, cq_commit_stale;

reg        iftx_in_frame;
reg [31:0] iftx_prev_addr;
reg        iftx_word_bad;
reg        iftx_step_bad;

reg [1:0]  mac_odd;
reg [31:0] mac_prev [0:1];
reg [1:0]  mac_pair_bad;

reg        ifrx_in_frame;
reg        ifrx_word_bad;
reg [1:0]  ifrx_order_bad;

reg        rxhw_first;
reg [31:0] rxhw_prev_addr;
reg        rxhw_word_bad;
reg        rxhw_step_bad;
reg        rxhw_region_bad;
reg        rxhw_order_bad;

reg        desc_data_bad;
reg        desc_order_bad;
reg        txdma_addr_bad;
reg        txdma_len_bad;
reg        rxdma_addr_bad;
reg [1:0]  dq_order_bad;

reg [11:0] cq_slot   [0:1];
reg        cpl_slot_bad;
reg        cpl_len_bad;
reg        cpl_queue_bad;

reg [11:0] n_txreq, n_txreq_st;
reg [11:0] n_dfreq, n_dfst_ok;
reg [11:0] n_desc_stream;
reg [11:0] n_thdma;
reg [11:0] n_iftx_pkt;
reg [11:0] n_ifrx_pkt;
reg [11:0] n_rh_dma;
reg [11:0] n_rxhw_word;
reg [11:0] n_rxhw_pkt;
reg [11:0] n_cw_req;
reg [11:0] n_ch_dma;
reg [11:0] n_cplhw;

reg [11:0] t_txreq_block;
reg [11:0] t_tdr_block;
reg [11:0] t_rdr_block;
reg [11:0] t_tcr_block;
reg [11:0] t_rcr_block;
reg [11:0] t_fetch;
reg [11:0] t_pkt;
reg [11:0] t_txcpl0, t_txcpl1;
reg [11:0] t_progress;
reg [11:0] t_dffull;

wire        dq_fire0 = dq_req_valid[0] && dq_req_ready[0];
wire        dq_fire1 = dq_req_valid[1] && dq_req_ready[1];
wire        dq_rfire0 = dq_resp_valid[0] && dq_resp_ready[0];
wire        dq_rfire1 = dq_resp_valid[1] && dq_resp_ready[1];
wire        dq_rok0  = dq_rfire0 && !dq_resp_empty[0] && !dq_resp_error[0];
wire        dq_rok1  = dq_rfire1 && !dq_resp_empty[1] && !dq_resp_error[1];
wire        cq_rfire = cq_resp_valid && cq_resp_ready;
wire        cq_rok   = cq_rfire && !cq_resp_full && !cq_resp_error;

wire        iftx_first = iftx_beat && !iftx_in_frame;
wire        ifrx_first = ifrx_beat && !ifrx_in_frame;

wire [FIFO_AW:0] tpq_occ0 = tpq_wr[0] - tpq_rd[0];
wire [FIFO_AW:0] tpq_occ1 = tpq_wr[1] - tpq_rd[1];
wire [FIFO_AW:0] rpq_occ  = rpq_wr - rpq_rd;
wire [FIFO_AW:0] dfq_occ  = dfq_wr - dfq_rd;

wire any_work = (n_txreq != n_txreq_st) || (n_iftx_pkt != n_rxhw_pkt)
                || (n_cw_req != n_cplhw);
wire any_event = txreq_fire || txreq_st_valid || df_req_fire || df_st_valid
                 || df_desc_beat || dh_fire || dh_st_valid || th_fire
                 || th_st_valid || iftx_beat || ifrx_beat || rh_fire
                 || rh_st_valid || rxhw_valid || cw_req_fire || ch_fire
                 || ch_st_valid || cplhw_valid || txcpl_valid;

integer j;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 2; i = i + 1) begin
            dqq_wr[i] <= 0; dqq_rd[i] <= 0; dqq_bad[i] <= 1'b0;
            tpq_wr[i] <= 0; tpq_rd[i] <= 0; tpq_bad[i] <= 1'b0;
            dqop_out[i] <= 4'd0;
            mac_prev[i] <= 32'd0;
            cq_slot[i]  <= 12'd0;
        end
        dfq_wr <= 0; dfq_rd <= 0; dfq_bad <= 1'b0;
        tbq_wr <= 0; tbq_rd <= 0; tbq_bad <= 1'b0;
        rbq_wr <= 0; rbq_rd <= 0; rbq_bad <= 1'b0;
        rpq_wr <= 0; rpq_rd <= 0; rpq_bad <= 1'b0;

        dh_out <= 16'd0; th_out <= 16'd0; rh_out <= 16'd0; ch_out <= 16'd0;
        cqop_out <= 4'd0;
        dh_reuse <= 1'b0; th_reuse <= 1'b0; rh_reuse <= 1'b0; ch_reuse <= 1'b0;
        dh_unsol <= 1'b0; th_unsol <= 1'b0; rh_unsol <= 1'b0; ch_unsol <= 1'b0;
        dqop_reuse <= 1'b0; cqop_reuse <= 1'b0;
        dq_commit_stale <= 1'b0; cq_commit_stale <= 1'b0;

        iftx_in_frame <= 1'b0; iftx_prev_addr <= 32'd0;
        iftx_word_bad <= 1'b0; iftx_step_bad <= 1'b0;
        mac_odd <= 2'b00; mac_pair_bad <= 2'b00;
        ifrx_in_frame <= 1'b0; ifrx_word_bad <= 1'b0; ifrx_order_bad <= 2'b00;
        rxhw_first <= 1'b1; rxhw_prev_addr <= 32'd0;
        rxhw_word_bad <= 1'b0; rxhw_step_bad <= 1'b0;
        rxhw_region_bad <= 1'b0; rxhw_order_bad <= 1'b0;

        desc_data_bad <= 1'b0; desc_order_bad <= 1'b0;
        txdma_addr_bad <= 1'b0; txdma_len_bad <= 1'b0; rxdma_addr_bad <= 1'b0;
        dq_order_bad <= 2'b00;
        cpl_slot_bad <= 1'b0; cpl_len_bad <= 1'b0; cpl_queue_bad <= 1'b0;

        n_txreq <= 0; n_txreq_st <= 0; n_dfreq <= 0; n_dfst_ok <= 0;
        n_desc_stream <= 0; n_thdma <= 0; n_iftx_pkt <= 0; n_ifrx_pkt <= 0;
        n_rh_dma <= 0; n_rxhw_word <= 0; n_rxhw_pkt <= 0;
        n_cw_req <= 0; n_ch_dma <= 0; n_cplhw <= 0;

        t_txreq_block <= 0; t_tdr_block <= 0; t_rdr_block <= 0;
        t_tcr_block <= 0; t_rcr_block <= 0;
        t_fetch <= 0; t_pkt <= 0; t_txcpl0 <= 0; t_txcpl1 <= 0;
        t_progress <= 0; t_dffull <= 0;
    end else begin

        if (dq_fire0) begin
            dqq_mem[0][dqq_wr[0][FIFO_AW-1:0]] <= {dq_req_queue[0], dq_req_tag[3:0]};
            dqq_wr[0] <= dqq_wr[0] + 1'b1;
        end
        if (dq_rfire0) begin
            if (dqq_wr[0] == dqq_rd[0]) dqq_bad[0] <= 1'b1;
            else begin
                dqq_rd[0] <= dqq_rd[0] + 1'b1;
                if (dqq_mem[0][dqq_rd[0][FIFO_AW-1:0]]
                    != {dq_resp_queue[0], dq_resp_tag[3:0]}) dq_order_bad[0] <= 1'b1;
            end
        end
        if (dq_fire1) begin
            dqq_mem[1][dqq_wr[1][FIFO_AW-1:0]] <= {dq_req_queue[1], dq_req_tag[7:4]};
            dqq_wr[1] <= dqq_wr[1] + 1'b1;
        end
        if (dq_rfire1) begin
            if (dqq_wr[1] == dqq_rd[1]) dqq_bad[1] <= 1'b1;
            else begin
                dqq_rd[1] <= dqq_rd[1] + 1'b1;
                if (dqq_mem[1][dqq_rd[1][FIFO_AW-1:0]]
                    != {dq_resp_queue[1], dq_resp_tag[7:4]}) dq_order_bad[1] <= 1'b1;
            end
        end

        if (dh_fire) begin
            dfq_mem[dfq_wr[FIFO_AW-1:0]] <= dh_addr;
            dfq_wr <= dfq_wr + 1'b1;
        end
        if (df_desc_beat && df_desc_tlast) begin
            if (dfq_wr == dfq_rd) dfq_bad <= 1'b1;
            else begin
                dfq_rd <= dfq_rd + 1'b1;
                if (df_desc_tdata != desc_word(dfq_mem[dfq_rd[FIFO_AW-1:0]]))
                    desc_data_bad <= 1'b1;
                if (df_desc_tdata[127:64] !=
                    {32'h0000_0000, dfq_mem[dfq_rd[FIFO_AW-1:0]][17]
                                    ? rx_pbuf(dfq_mem[dfq_rd[FIFO_AW-1:0]])
                                    : tx_pbuf(dfq_mem[dfq_rd[FIFO_AW-1:0]])})
                    desc_order_bad <= 1'b1;
            end
        end

        if (txd_beat) begin
            tbq_addr[tbq_wr[FIFO_AW-1:0]] <= txd_tdata[95:64];
            tbq_len [tbq_wr[FIFO_AW-1:0]] <= txd_tdata[47:32];
            tbq_wr <= tbq_wr + 1'b1;
        end
        if (th_fire) begin
            if (tbq_wr == tbq_rd) tbq_bad <= 1'b1;
            else begin
                tbq_rd <= tbq_rd + 1'b1;
                if (th_addr[31:0] != tbq_addr[tbq_rd[FIFO_AW-1:0]])
                    txdma_addr_bad <= 1'b1;
                if (th_len != tbq_len[tbq_rd[FIFO_AW-1:0]])
                    txdma_len_bad <= 1'b1;
            end
        end

        if (rxd_beat) begin
            rbq_addr[rbq_wr[FIFO_AW-1:0]] <= rxd_tdata[95:64];
            rbq_wr <= rbq_wr + 1'b1;
        end
        if (rh_fire) begin
            if (rbq_wr == rbq_rd) rbq_bad <= 1'b1;
            else begin
                rbq_rd <= rbq_rd + 1'b1;
                if (rh_addr[31:0] != rbq_addr[rbq_rd[FIFO_AW-1:0]])
                    rxdma_addr_bad <= 1'b1;
            end
        end

        if (iftx_beat) begin
            iftx_in_frame  <= !iftx_tlast;
            iftx_prev_addr <= iftx_tdata[63:32];
            if (iftx_tdata[63:32] != ~iftx_tdata[31:0]) iftx_word_bad <= 1'b1;
            if (iftx_in_frame
                && iftx_tdata[63:32] != iftx_prev_addr + 32'd8)
                iftx_step_bad <= 1'b1;
            if (iftx_tlast) n_iftx_pkt <= sat_inc(n_iftx_pkt);
            if (!iftx_in_frame) begin
                tpq_mem[iftx_port][tpq_wr[iftx_port][FIFO_AW-1:0]]
                    <= iftx_tdata[63:32];
                tpq_wr[iftx_port] <= tpq_wr[iftx_port] + 1'b1;
            end
        end

        for (j = 0; j < 2; j = j + 1) begin
            if (mactx_tvalid[j] && mactx_tready[j]) begin
                mac_prev[j] <= mactx_tdata[j*32 +: 32];
                if (mac_odd[j] && mactx_tdata[j*32 +: 32] != ~mac_prev[j])
                    mac_pair_bad[j] <= 1'b1;
                mac_odd[j] <= mactx_tlast[j] ? 1'b0 : ~mac_odd[j];
            end
        end

        if (ifrx_beat) begin
            ifrx_in_frame <= !ifrx_tlast;
            if (ifrx_tdata[63:32] != ~ifrx_tdata[31:0]) ifrx_word_bad <= 1'b1;
            if (ifrx_tlast) n_ifrx_pkt <= sat_inc(n_ifrx_pkt);
            if (!ifrx_in_frame) begin

                if (tpq_wr[ifrx_tid] == tpq_rd[ifrx_tid]) tpq_bad[ifrx_tid] <= 1'b1;
                else begin
                    tpq_rd[ifrx_tid] <= tpq_rd[ifrx_tid] + 1'b1;
                    if (tpq_mem[ifrx_tid][tpq_rd[ifrx_tid][FIFO_AW-1:0]]
                        != ifrx_tdata[63:32]) ifrx_order_bad[ifrx_tid] <= 1'b1;
                end

                rpq_mem[rpq_wr[FIFO_AW-1:0]] <= ifrx_tdata[63:32];
                rpq_wr <= rpq_wr + 1'b1;
            end
        end

        if (rxhw_valid) begin
            n_rxhw_word <= sat_inc(n_rxhw_word);
            rxhw_first <= 1'b0;
            rxhw_prev_addr <= rxhw_data[63:32];
            if (rxhw_data[63:32] != ~rxhw_data[31:0]) rxhw_word_bad <= 1'b1;
            if (rxhw_data[63:62] != 2'b01) rxhw_region_bad <= 1'b1;
            if (rxhw_addr[63:32] != 32'd0 || rxhw_addr[31:30] != 2'b10)
                rxhw_region_bad <= 1'b1;
            if (!rxhw_first && rxhw_data[63:32] != rxhw_prev_addr + 32'd8)
                rxhw_step_bad <= 1'b1;
            if (rxhw_first) begin
                n_rxhw_pkt <= sat_inc(n_rxhw_pkt);
                if (rpq_wr == rpq_rd) rpq_bad <= 1'b1;
                else begin
                    rpq_rd <= rpq_rd + 1'b1;
                    if (rpq_mem[rpq_rd[FIFO_AW-1:0]] != rxhw_data[63:32])
                        rxhw_order_bad <= 1'b1;
                end
            end
        end

        if (rh_fire) begin
            rxhw_first <= 1'b1;
            n_rh_dma <= sat_inc(n_rh_dma);
        end

        if (dh_fire) begin
            if (dh_out[dh_tag]) dh_reuse <= 1'b1;
            dh_out[dh_tag] <= 1'b1;
        end
        if (dh_st_valid) begin
            if (!dh_out[dh_st_tag] && !(dh_fire && dh_tag == dh_st_tag))
                dh_unsol <= 1'b1;
            if (!(dh_fire && dh_tag == dh_st_tag)) dh_out[dh_st_tag] <= 1'b0;
        end
        if (th_fire) begin
            if (th_out[th_tag]) th_reuse <= 1'b1;
            th_out[th_tag] <= 1'b1;
            n_thdma <= sat_inc(n_thdma);
        end
        if (th_st_valid) begin
            if (!th_out[th_st_tag] && !(th_fire && th_tag == th_st_tag))
                th_unsol <= 1'b1;
            if (!(th_fire && th_tag == th_st_tag)) th_out[th_st_tag] <= 1'b0;
        end
        if (rh_fire) begin
            if (rh_out[rh_tag]) rh_reuse <= 1'b1;
            rh_out[rh_tag] <= 1'b1;
        end
        if (rh_st_valid) begin
            if (!rh_out[rh_st_tag] && !(rh_fire && rh_tag == rh_st_tag))
                rh_unsol <= 1'b1;
            if (!(rh_fire && rh_tag == rh_st_tag)) rh_out[rh_st_tag] <= 1'b0;
        end
        if (ch_fire) begin
            if (ch_out[ch_tag]) ch_reuse <= 1'b1;
            ch_out[ch_tag] <= 1'b1;
            n_ch_dma <= sat_inc(n_ch_dma);

            if (ch_addr[63:32] != 32'd0 || ch_addr[31:13] != 19'd24
                || ch_addr[11:7] != 5'd0 || ch_addr[4:0] != 5'd0
                || ch_addr[6:5] != cq_slot[ch_addr[12]][1:0])
                cpl_slot_bad <= 1'b1;
            cq_slot[ch_addr[12]] <= cq_slot[ch_addr[12]] + 12'd1;
        end
        if (ch_st_valid) begin
            if (!ch_out[ch_st_tag] && !(ch_fire && ch_tag == ch_st_tag))
                ch_unsol <= 1'b1;
            if (!(ch_fire && ch_tag == ch_st_tag)) ch_out[ch_st_tag] <= 1'b0;
        end

        if (dq_rok0) begin
            if (dqop_out[0][dq_resp_optag[1:0]]) dqop_reuse <= 1'b1;
            dqop_out[0][dq_resp_optag[1:0]] <= 1'b1;
        end
        if (dq_commit_valid[0] && dq_commit_ready[0]) begin
            if (!dqop_out[0][dq_commit_optag[1:0]]) dq_commit_stale <= 1'b1;
            dqop_out[0][dq_commit_optag[1:0]] <= 1'b0;
        end
        if (dq_rok1) begin
            if (dqop_out[1][dq_resp_optag[3:2]]) dqop_reuse <= 1'b1;
            dqop_out[1][dq_resp_optag[3:2]] <= 1'b1;
        end
        if (dq_commit_valid[1] && dq_commit_ready[1]) begin
            if (!dqop_out[1][dq_commit_optag[3:2]]) dq_commit_stale <= 1'b1;
            dqop_out[1][dq_commit_optag[3:2]] <= 1'b0;
        end
        if (cq_rok) begin
            if (cqop_out[cq_resp_optag]) cqop_reuse <= 1'b1;
            cqop_out[cq_resp_optag] <= 1'b1;
        end
        if (cq_commit_valid && cq_commit_ready) begin
            if (!cqop_out[cq_commit_optag]) cq_commit_stale <= 1'b1;
            cqop_out[cq_commit_optag] <= 1'b0;
        end

        if (cplhw_valid) begin
            n_cplhw <= sat_inc(n_cplhw);
            if (cplhw_data[47:32] != 16'd8 && cplhw_data[47:32] != 16'd16)
                cpl_len_bad <= 1'b1;
            if (cplhw_data[15:1] != 15'd0) cpl_queue_bad <= 1'b1;
        end

        if (txreq_fire)     n_txreq       <= sat_inc(n_txreq);
        if (txreq_st_valid) n_txreq_st    <= sat_inc(n_txreq_st);
        if (df_req_fire)    n_dfreq       <= sat_inc(n_dfreq);
        if (df_st_ok)       n_dfst_ok     <= sat_inc(n_dfst_ok);
        if (df_desc_beat && df_desc_tlast) n_desc_stream <= sat_inc(n_desc_stream);
        if (cw_req_fire)    n_cw_req      <= sat_inc(n_cw_req);

        t_txreq_block <= (txreq_valid && !txreq_ready)
                         ? ((t_txreq_block == TSAT) ? TSAT : t_txreq_block + 1) : 0;
        t_tdr_block   <= (tdr_valid && !tdr_ready)
                         ? ((t_tdr_block == TSAT) ? TSAT : t_tdr_block + 1) : 0;
        t_rdr_block   <= (rdr_valid && !rdr_ready)
                         ? ((t_rdr_block == TSAT) ? TSAT : t_rdr_block + 1) : 0;
        t_tcr_block   <= (tcr_valid && !tcr_ready)
                         ? ((t_tcr_block == TSAT) ? TSAT : t_tcr_block + 1) : 0;
        t_rcr_block   <= (rcr_valid && !rcr_ready)
                         ? ((t_rcr_block == TSAT) ? TSAT : t_rcr_block + 1) : 0;

        if (df_st_valid || (n_dfreq == n_dfst_ok)) t_fetch <= 0;
        else t_fetch <= (t_fetch == TSAT) ? TSAT : t_fetch + 1;

        if (rxhw_valid || (n_iftx_pkt == n_rxhw_pkt)) t_pkt <= 0;
        else t_pkt <= (t_pkt == TSAT) ? TSAT : t_pkt + 1;

        t_txcpl0 <= (maccpl_valid[0] && !maccpl_ready[0])
                    ? ((t_txcpl0 == TSAT) ? TSAT : t_txcpl0 + 1) : 0;
        t_txcpl1 <= (maccpl_valid[1] && !maccpl_ready[1])
                    ? ((t_txcpl1 == TSAT) ? TSAT : t_txcpl1 + 1) : 0;

        if (any_event || !any_work) t_progress <= 0;
        else t_progress <= (t_progress == TSAT) ? TSAT : t_progress + 1;

        t_dffull <= (df_active_count == DF_TABLE_SIZE)
                    ? ((t_dffull == TSAT) ? TSAT : t_dffull + 1) : 0;
    end
end

// __ASSERTION_INSERTION_POINT__
endmodule

`default_nettype wire
