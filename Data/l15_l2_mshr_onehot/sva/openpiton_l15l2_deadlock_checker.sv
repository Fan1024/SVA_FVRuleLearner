// ===========================================================================
// Checker for the OpenPiton L1.5 <-> L2 pair.
//
// One target, one conservation law over the L2 MSHR pool:
//
//   T_L2_MSHR_ONEHOT -- at most one busy MSHR entry per L2 set index.
//
// The conserved item is the CAM's compared address
// (`L2_MSHR_CMP_ADDR == `L2_TAG_INDEX, 3 bits at this build -> 8 distinct
// values over 8 entries) and the "places" it can occupy are the MSHR entries.
// The property is register-free: `cons_dup` is combinational over
// l2_mshr_wrap.state_mem_f and l2_mshr_wrap.data_mem_f, so the checker itself
// carries no state and there is no checker register for a reset cut to make
// arbitrary.
//
// The environment fairness assumptions are also here; both constrain free
// inputs of the formal top directly, never a derived state predicate.
// ===========================================================================

module openpiton_l15l2_deadlock_checker (
    input wire       clk,
    input wire       reset_n,

    input wire [5:0] l15_mshr_val,
    input wire [7:0] l2_mshr_busy,
    input wire [7:0] l2_mshr_wait,
    input wire [7:0] l2_mshr_pend,
    input wire [3:0] l2_empty_slots,

    input wire       noc1_blocked,
    input wire       noc2_l15_blocked,
    input wire       noc3_blocked,

    input wire       mem_holding,
    input wire [1:0] core_active,
    input wire       cpx_ack,
    input wire       mem_send,

    input wire [23:0] l2_mshr_cmp_addr_flat,
    input wire [15:0] l2_mshr_state_flat
);
    // -----------------------------------------------------------------------
    // Environment fairness.  Without these the design is trivially and
    // uninterestingly stalled: a core that never accepts a response, or a
    // memory that never answers, is not a coherence failure.  Both are
    // LEGALITY contracts -- a real core drains CPX and a real memory
    // controller answers -- not convenience restrictions on the DUT.
    //
    // BOTH constrain FREE INPUTS of the formal top directly, never a derived
    // state predicate, so consistency is immediate: holding cpx_ack = 1 and
    // mem_send = 1 for all time satisfies both.  A form written over a derived
    // predicate instead (e.g. "mem_holding must fall within 8") can be
    // unsatisfiable during a multi-flit response burst, which would silently
    // make every proof in this environment vacuous.
    // -----------------------------------------------------------------------
    A_FAIR_CPX: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] cpx_ack);
    A_FAIR_MEM: assume property (@(posedge clk) disable iff (!reset_n)
        1'b1 |-> ##[0:3] mem_send);

    // =======================================================================
    // ONE-HOT CONSERVATION over the L2 MSHR pool.
    // =======================================================================
    reg [3:0] cons_count [0:7];   // 3-bit key -> eight buckets
    reg       cons_dup;
    reg [3:0] cons_busy_total;
    integer   ca, ce;

    always @* begin
        for (ca = 0; ca < 8; ca = ca + 1) cons_count[ca] = 4'd0;
        cons_busy_total = 4'd0;

        for (ce = 0; ce < 8; ce = ce + 1) begin
            if (l2_mshr_state_flat[2*ce +: 2] != `L2_MSHR_STATE_INVAL) begin
                cons_busy_total = cons_busy_total + 4'd1;
                cons_count[l2_mshr_cmp_addr_flat[3*ce +: 3]] =
                    cons_count[l2_mshr_cmp_addr_flat[3*ce +: 3]] + 4'd1;
            end
        end

        cons_dup = 1'b0;
        for (ca = 0; ca < 8; ca = ca + 1)
            if (cons_count[ca] > 4'd1) cons_dup = 1'b1;
    end

    T_L2_MSHR_ONEHOT: assert property (@(posedge clk) disable iff (!reset_n) !cons_dup);

    // =======================================================================
    // COVERS -- vacuity guards for the environment.  These say the two tracker
    // pools and the three NOC channels can actually be driven into their
    // interesting states; without them a proof of the target above could be a
    // statement about a design that never does anything.
    // =======================================================================
    C_L2_MSHR_FULL: cover property (@(posedge clk) disable iff (!reset_n)
        l2_empty_slots == 4'd0);
    C_L2_MSHR_NEAR_FULL: cover property (@(posedge clk) disable iff (!reset_n)
        l2_empty_slots <= 4'd1);
    C_BOTH_POOLS_LOADED: cover property (@(posedge clk) disable iff (!reset_n)
        (l2_empty_slots <= 4'd2) && (l15_mshr_val[2:0] == 3'b111));
    C_ALL_TRACKERS_LOADED: cover property (@(posedge clk) disable iff (!reset_n)
        (l2_empty_slots <= 4'd3) && (l15_mshr_val != 6'd0) &&
        (|l2_mshr_pend) && (|l2_mshr_wait));
    C_NO_L2_TRACKER_FREE: cover property (@(posedge clk) disable iff (!reset_n)
        !(|(~l2_mshr_busy)));
    C_NO_L15_TRACKER_FREE: cover property (@(posedge clk) disable iff (!reset_n)
        !(|(~l15_mshr_val)));
    C_ALL_CHANNELS_BUSY: cover property (@(posedge clk) disable iff (!reset_n)
        noc1_blocked && noc2_l15_blocked && noc3_blocked);
    C_BOTH_CORES_ACTIVE: cover property (@(posedge clk) disable iff (!reset_n)
        &core_active);
    C_MEM_ROUND_TRIP: cover property (@(posedge clk) disable iff (!reset_n)
        mem_holding && (|l2_mshr_wait));

    // occupancy ladder over the pool the target is about
    C_CONS_BUSY_EQ1: cover property (@(posedge clk) disable iff (!reset_n)
        cons_busy_total == 4'd1);
    C_CONS_BUSY_EQ2: cover property (@(posedge clk) disable iff (!reset_n)
        cons_busy_total == 4'd2);
    C_CONS_BUSY_EQ4: cover property (@(posedge clk) disable iff (!reset_n)
        cons_busy_total == 4'd4);
    C_CONS_BUSY_EQ8: cover property (@(posedge clk) disable iff (!reset_n)
        cons_busy_total == 4'd8);
endmodule
