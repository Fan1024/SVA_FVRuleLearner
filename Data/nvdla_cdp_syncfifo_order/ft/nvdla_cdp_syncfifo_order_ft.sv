// Component-local formal top for the real NVDLA CDP synchronization FIFO.
// Symbolic paired CVT traffic and SUM traffic traverse three independently
// backpressured production FIFOs.

module nvdla_cdp_syncfifo_order_ft (
   input wire         nvdla_core_clk,
   input wire         nvdla_core_rstn,
   input wire [86:0]  cvt2sync_pd,
   input wire         cvt2sync_pvld,
   input wire [167:0] sum2sync_pd,
   input wire         sum2sync_pvld,
   input wire         sync2itp_prdy,
   input wire         sync2mul_prdy,
   input wire         sync2ocvt_prdy
);
   wire [31:0] pwrbus_ram_pd = 32'd0;
   wire cvt2sync_prdy;
   wire sum2sync_prdy;
   wire [167:0] sync2itp_pd;
   wire sync2itp_pvld;
   wire [71:0] sync2mul_pd;
   wire sync2mul_pvld;
   wire [14:0] sync2ocvt_pd;
   wire sync2ocvt_pvld;

   NV_NVDLA_CDP_DP_syncfifo u_dut (
      .nvdla_core_clk,
      .nvdla_core_rstn,
      .cvt2sync_pd,
      .cvt2sync_pvld,
      .pwrbus_ram_pd,
      .sum2sync_pd,
      .sum2sync_pvld,
      .sync2itp_prdy,
      .sync2mul_prdy,
      .sync2ocvt_prdy,
      .cvt2sync_prdy,
      .sum2sync_prdy,
      .sync2itp_pd,
      .sync2itp_pvld,
      .sync2mul_pd,
      .sync2mul_pvld,
      .sync2ocvt_pd,
      .sync2ocvt_pvld
   );

   nvdla_cdp_syncfifo_order_checker u_checker (
      .clk          (nvdla_core_clk),
      .reset_n      (nvdla_core_rstn),
      .cvt_valid    (cvt2sync_pvld),
      .cvt_ready    (cvt2sync_prdy),
      .cvt_pd       (cvt2sync_pd),
      .sum_valid    (sum2sync_pvld),
      .sum_ready    (sum2sync_prdy),
      .sum_pd       (sum2sync_pd),
      .mul_valid    (sync2mul_pvld),
      .mul_ready    (sync2mul_prdy),
      .mul_pd       (sync2mul_pd),
      .ocvt_valid   (sync2ocvt_pvld),
      .ocvt_ready   (sync2ocvt_prdy),
      .ocvt_pd      (sync2ocvt_pd),
      .itp_valid    (sync2itp_pvld),
      .itp_ready    (sync2itp_prdy),
      .itp_pd       (sync2itp_pd)
   );

endmodule
