// Functional formal replacement for the generated NVDLA 245x514 SRAM wrapper
// used by NV_NVDLA_BDMA_store.
//
// The public wrapper adds power, DFT, and foundry-cell plumbing around a
// synchronous 1R1W array.  In functional power mode, `re` captures the array
// output and `ore` captures that value at the wrapper output.  Nonblocking
// updates preserve the wrapper's read-before-write collision behavior.

module nv_ram_rwsp_245x514 (
   input  wire         clk,
   input  wire [7:0]   ra,
   input  wire         re,
   input  wire         ore,
   output reg  [513:0] dout,
   input  wire [7:0]   wa,
   input  wire         we,
   input  wire [513:0] di,
   input  wire [31:0]  pwrbus_ram_pd
);
   parameter FORCE_CONTENTION_ASSERTION_RESET_ACTIVE = 1'b0;

   reg [513:0] mem [0:244];
   reg [513:0] read_data;

   always @(posedge clk) begin
      if (we)
         mem[wa] <= di;
      if (re)
         read_data <= mem[ra];
      if (ore)
         dout <= read_data;
   end

   wire _unused = &{1'b0, pwrbus_ram_pd,
                    FORCE_CONTENTION_ASSERTION_RESET_ACTIVE};
endmodule
