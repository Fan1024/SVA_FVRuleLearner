// Functional formal replacements for the two generated NVDLA SRAM wrappers
// used by NV_NVDLA_MCIF_READ_cq.
//
// The public nvdlav1 wrappers add DFT, power, and foundry-cell plumbing around
// one synchronous 1R1W memory.  The task fixes pwrbus_ram_pd to functional
// mode, so only this interface-visible behavior remains.  Nonblocking updates
// give read-before-write behavior on a same-cycle same-address collision.

module nv_ram_rws_256x7 (
   input  wire         clk,
   input  wire [7:0]   ra,
   input  wire         re,
   output reg  [6:0]   dout,
   input  wire [7:0]   wa,
   input  wire         we,
   input  wire [6:0]   di,
   input  wire [31:0]  pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;

   reg [6:0] mem [0:255];

   always @(posedge clk) begin
      if (we)
         mem[wa] <= di;
      if (re)
         dout <= mem[ra];
   end

   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule

module nv_ram_rwst_256x8 (
   input  wire         clk,
   input  wire [7:0]   ra,
   input  wire         re,
   output reg  [7:0]   dout,
   input  wire [7:0]   wa,
   input  wire         we,
   input  wire [7:0]   di,
   input  wire [31:0]  pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;

   reg [7:0] mem [0:255];

   always @(posedge clk) begin
      if (we)
         mem[wa] <= di;
      if (re)
         dout <= mem[ra];
   end

   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule
