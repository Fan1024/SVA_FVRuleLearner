// Independent end-to-end oracle for four tagged source streams. It observes
// only legal endpoint injections and the shared destination endpoint.
module openpiton_pmesh_order_scaled_checker #(
    parameter integer REF_DEPTH   = 128,
    parameter integer REF_PTR_W   = $clog2(REF_DEPTH),
    parameter integer REF_COUNT_W = $clog2(REF_DEPTH + 1)
) (
    input wire        clk,
    input wire        reset_n,
    input wire        inject0,
    input wire [63:0] inject0_flit,
    input wire        inject1,
    input wire [63:0] inject1_flit,
    input wire        inject2,
    input wire [63:0] inject2_flit,
    input wire        inject3,
    input wire [63:0] inject3_flit,
    input wire        dst_fire,
    input wire [63:0] dst_flit,
    input wire        upstream_contention,
    input wire        downstream_contention
);
    reg [63:0] ref_mem [0:3][0:REF_DEPTH-1];
    reg [REF_PTR_W-1:0] ref_wr_ptr [0:3];
    reg [REF_PTR_W-1:0] ref_rd_ptr [0:3];
    reg [REF_COUNT_W-1:0] ref_count [0:3];

    wire [3:0] inject;
    wire [63:0] inject_flit [0:3];
    wire [1:0] dst_flow;
    wire [3:0] pop;
    assign inject = {inject3, inject2, inject1, inject0};
    assign inject_flit[0] = inject0_flit;
    assign inject_flit[1] = inject1_flit;
    assign inject_flit[2] = inject2_flit;
    assign inject_flit[3] = inject3_flit;
    assign dst_flow = dst_flit[21:20];
    assign pop[0] = dst_fire && (dst_flow == 2'd0);
    assign pop[1] = dst_fire && (dst_flow == 2'd1);
    assign pop[2] = dst_fire && (dst_flow == 2'd2);
    assign pop[3] = dst_fire && (dst_flow == 2'd3);

    integer flow;
    always @(posedge clk) begin
        if (!reset_n) begin
            for (flow = 0; flow < 4; flow = flow + 1) begin
                ref_wr_ptr[flow] <= {REF_PTR_W{1'b0}};
                ref_rd_ptr[flow] <= {REF_PTR_W{1'b0}};
                ref_count[flow]  <= {REF_COUNT_W{1'b0}};
            end
        end else begin
            for (flow = 0; flow < 4; flow = flow + 1) begin
                if (inject[flow]) begin
                    ref_mem[flow][ref_wr_ptr[flow]] <= inject_flit[flow];
                    if (ref_wr_ptr[flow] == REF_DEPTH-1)
                        ref_wr_ptr[flow] <= {REF_PTR_W{1'b0}};
                    else
                        ref_wr_ptr[flow] <= ref_wr_ptr[flow] + 1'b1;
                end
                if (pop[flow]) begin
                    if (ref_rd_ptr[flow] == REF_DEPTH-1)
                        ref_rd_ptr[flow] <= {REF_PTR_W{1'b0}};
                    else
                        ref_rd_ptr[flow] <= ref_rd_ptr[flow] + 1'b1;
                end
                case ({inject[flow], pop[flow]})
                    2'b10: ref_count[flow] <= ref_count[flow] + 1'b1;
                    2'b01: ref_count[flow] <= ref_count[flow] - 1'b1;
                    default: begin end
                endcase
            end
        end
    end

    wire selected_nonempty;
    wire selected_match;
    wire target_ok;
    assign selected_nonempty = (ref_count[dst_flow] != 0);
    assign selected_match = selected_nonempty &&
                            (dst_flit == ref_mem[dst_flow][ref_rd_ptr[dst_flow]]);
    assign target_ok = !dst_fire || selected_match;

    // One checker of one type: the composite assertion conjoins the four
    // per-flow FIFO-order obligations at the single destination.
    T_ORDER: assert property (@(posedge clk) disable iff (!reset_n)
        target_ok);

    C_FLOW0_INJECT: cover property (@(posedge clk) disable iff (!reset_n)
        inject0);
    C_FLOW1_INJECT: cover property (@(posedge clk) disable iff (!reset_n)
        inject1);
    C_FLOW2_INJECT: cover property (@(posedge clk) disable iff (!reset_n)
        inject2);
    C_FLOW3_INJECT: cover property (@(posedge clk) disable iff (!reset_n)
        inject3);
    C_FLOW0_DELIVER: cover property (@(posedge clk) disable iff (!reset_n)
        dst_fire && (dst_flow == 2'd0));
    C_FLOW1_DELIVER: cover property (@(posedge clk) disable iff (!reset_n)
        dst_fire && (dst_flow == 2'd1));
    C_FLOW2_DELIVER: cover property (@(posedge clk) disable iff (!reset_n)
        dst_fire && (dst_flow == 2'd2));
    C_FLOW3_DELIVER: cover property (@(posedge clk) disable iff (!reset_n)
        dst_fire && (dst_flow == 2'd3));
    C_ALL_BACKLOG: cover property (@(posedge clk) disable iff (!reset_n)
        (ref_count[0] >= 4) && (ref_count[1] >= 4) &&
        (ref_count[2] >= 4) && (ref_count[3] >= 4));
    C_UPSTREAM_CONTEND: cover property (@(posedge clk) disable iff (!reset_n)
        upstream_contention);
    C_DOWNSTREAM_CONTEND: cover property (@(posedge clk) disable iff (!reset_n)
        downstream_contention);
    C_FOUR_FLOW_DELIVERY: cover property (@(posedge clk) disable iff (!reset_n)
        (dst_fire && (dst_flow == 2'd0)) ##[1:20]
        (dst_fire && (dst_flow == 2'd1)) ##[1:20]
        (dst_fire && (dst_flow == 2'd2)) ##[1:20]
        (dst_fire && (dst_flow == 2'd3)));
endmodule
