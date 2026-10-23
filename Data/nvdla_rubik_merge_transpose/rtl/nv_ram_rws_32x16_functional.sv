// Functional contract for the single-clock NVDLA 32x16 RAM wrapper.
// The RUBIK residual does not exercise DFT, sleep, retention, or read/write
// contention; this model preserves the functional synchronous RAM behavior.
module nv_ram_rws_32x16 (
   input  logic        clk,
   input  logic [4:0]  ra,
   input  logic        re,
   output logic [15:0] dout,
   input  logic [4:0]  wa,
   input  logic        we,
   input  logic [15:0] di,
   input  logic [31:0] pwrbus_ram_pd
);
   logic [15:0] mem [0:31];

   always_ff @(posedge clk) begin
      if (we)
         mem[wa] <= di;
      if (re)
         dout <= mem[ra];
   end

   wire _unused = ^pwrbus_ram_pd;
endmodule
