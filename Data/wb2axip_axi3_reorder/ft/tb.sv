`default_nettype none
`undef FORMAL
`include "sfifo.v"
`include "axi3reorder.v"

module testbench (
    input  wire       clock,
    input  wire       reset,
    input  wire       s_awvalid,
    input  wire [1:0] s_awid,
    input  wire       s_wvalid,
    input  wire [1:0] s_wid,
    input  wire [7:0] s_wdata,
    input  wire       s_wstrb,
    input  wire       s_wlast,
    input  wire       m_wready
);
    wire reset_n = !reset;
    wire s_awready;
    wire s_wready;
    wire m_wvalid;
    wire [1:0] m_wid;
    wire [7:0] m_wdata;
    wire m_wstrb;
    wire m_wlast;

    axi3reorder #(
        .C_AXI_ID_WIDTH(2),
        .C_AXI_DATA_WIDTH(8),
        .LGAWFIFO(3),
        .LGWFIFO(4),
        .OPT_METHOD(1),
        .OPT_LOWPOWER(0),
        .OPT_LOW_LATENCY(0)
    ) dut (
        .S_AXI_ACLK(clock),
        .S_AXI_ARESETN(reset_n),
        .S_AXI3_AWVALID(s_awvalid),
        .S_AXI3_AWREADY(s_awready),
        .S_AXI3_AWID(s_awid),
        .S_AXI3_WVALID(s_wvalid),
        .S_AXI3_WREADY(s_wready),
        .S_AXI3_WID(s_wid),
        .S_AXI3_WDATA(s_wdata),
        .S_AXI3_WSTRB(s_wstrb),
        .S_AXI3_WLAST(s_wlast),
        .M_AXI_WVALID(m_wvalid),
        .M_AXI_WREADY(m_wready),
        .M_AXI_WID(m_wid),
        .M_AXI_WDATA(m_wdata),
        .M_AXI_WSTRB(m_wstrb),
        .M_AXI_WLAST(m_wlast)
    );

    wire push_aw = s_awvalid && s_awready;
    wire push_w = s_wvalid && s_wready;
    wire pop_w = m_wvalid && m_wready;
    wire pop_aw = pop_w && m_wlast;

    reg [1:0] aw_ref [0:15];
    reg [3:0] aw_wptr;
    reg [3:0] aw_rptr;
    reg [4:0] aw_count;

    reg [7:0] w_data_ref [0:3][0:31];
    reg       w_strb_ref [0:3][0:31];
    reg       w_last_ref [0:3][0:31];
    reg [4:0] w_wptr [0:3];
    reg [4:0] w_rptr [0:3];
    reg [5:0] w_count [0:3];
    reg [1:0] input_beat [0:3];

    reg past_valid;
    reg seen_interleaved;
    reg seen_wrap;
    integer i;

    initial past_valid = 1'b0;
    always @(posedge clock) begin
        past_valid <= 1'b1;
        if (reset) begin
            A_RESET_AW_IDLE: assume (!s_awvalid);
            A_RESET_W_IDLE: assume (!s_wvalid);
            aw_wptr <= 0;
            aw_rptr <= 0;
            aw_count <= 0;
            seen_interleaved <= 0;
            seen_wrap <= 0;
            for (i = 0; i < 4; i = i + 1) begin
                w_wptr[i] <= 0;
                w_rptr[i] <= 0;
                w_count[i] <= 0;
                input_beat[i] <= 0;
            end
        end else begin
            if (past_valid && $past(!reset)) begin
                if ($past(s_awvalid && !s_awready)) begin
                    A_AW_STICKY: assume (
                        s_awvalid && $stable(s_awid));
                end
                if ($past(s_wvalid && !s_wready)) begin
                    A_W_STICKY: assume (
                        s_wvalid && $stable(s_wid) &&
                        $stable(s_wdata) && $stable(s_wstrb) &&
                        $stable(s_wlast));
                end
            end

            if (push_w) begin
                A_FIXED_PACKET_LAST: assume (
                    s_wlast == (input_beat[s_wid] == 2'd3));
                input_beat[s_wid] <=
                    s_wlast ? 2'd0 : input_beat[s_wid] + 1'b1;
                w_data_ref[s_wid][w_wptr[s_wid]] <= s_wdata;
                w_strb_ref[s_wid][w_wptr[s_wid]] <= s_wstrb;
                w_last_ref[s_wid][w_wptr[s_wid]] <= s_wlast;
                w_wptr[s_wid] <= w_wptr[s_wid] + 1'b1;
                if (s_wid != aw_ref[aw_rptr] && aw_count != 0)
                    seen_interleaved <= 1'b1;
                if (w_wptr[s_wid] == 5'h1f)
                    seen_wrap <= 1'b1;
            end
            if (pop_w)
                w_rptr[m_wid] <= w_rptr[m_wid] + 1'b1;
            for (i = 0; i < 4; i = i + 1) begin
                case ({push_w && s_wid == i[1:0],
                       pop_w && m_wid == i[1:0]})
                    2'b10: w_count[i] <= w_count[i] + 1'b1;
                    2'b01: w_count[i] <= w_count[i] - 1'b1;
                    default: w_count[i] <= w_count[i];
                endcase
            end

            if (push_aw) begin
                aw_ref[aw_wptr] <= s_awid;
                aw_wptr <= aw_wptr + 1'b1;
            end
            if (pop_aw)
                aw_rptr <= aw_rptr + 1'b1;
            case ({push_aw, pop_aw})
                2'b10: aw_count <= aw_count + 1'b1;
                2'b01: aw_count <= aw_count - 1'b1;
                default: aw_count <= aw_count;
            endcase

            o_axi3_reorder_e2e: assert (
                (!push_aw || aw_count < 16 || pop_aw) &&
                (!push_w || w_count[s_wid] < 32 ||
                    (pop_w && m_wid == s_wid)) &&
                (!m_wvalid ||
                    (aw_count != 0 &&
                     w_count[m_wid] != 0 &&
                     m_wid == aw_ref[aw_rptr] &&
                     m_wdata == w_data_ref[m_wid][w_rptr[m_wid]] &&
                     m_wstrb == w_strb_ref[m_wid][w_rptr[m_wid]] &&
                     m_wlast == w_last_ref[m_wid][w_rptr[m_wid]]))
            );

            c_aw_backlog: cover (aw_count >= 4);
            c_interleaved_ids: cover (seen_interleaved && m_wvalid);
            c_reference_wrap: cover (seen_wrap && m_wvalid && m_wlast);
        end
    end

endmodule

`default_nettype wire
