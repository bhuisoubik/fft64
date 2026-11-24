// 32-entry twiddle ROM: W64^k = cos(2*pi*k/64) - j*sin(2*pi*k/64), Q2.14.
// Word = {re[15:0], im[15:0]}. Synchronous read (1 cycle).
module twiddle_rom #(
  parameter string HEX_FILE = "twiddle.hex"
) (
  input  logic               clk,
  input  logic [4:0]         addr,
  output logic signed [15:0] w_re,
  output logic signed [15:0] w_im
);
  logic [31:0] rom [0:31];
  initial $readmemh(HEX_FILE, rom);

  always_ff @(posedge clk) {w_re, w_im} <= rom[addr];
endmodule
