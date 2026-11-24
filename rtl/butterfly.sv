// Radix-2 DIT butterfly, 3-cycle latency.
//   t = W*B (cmul, 2 cycles);  X = A + t;  Y = A - t  (exact, 24-bit sum, 1 cycle)
// A is delayed by 2 cycles to line up with t.
// ovf: any of cmul result / X / Y does not fit in 23 bits (aligned with outputs).
module butterfly #(
  parameter int DW = 23,
  parameter int TW = 16
) (
  input  logic                  clk,
  input  logic signed [DW-1:0]  a_re, a_im,
  input  logic signed [DW-1:0]  b_re, b_im,
  input  logic signed [TW-1:0]  w_re, w_im,
  output logic signed [DW-1:0]  x_re, x_im,
  output logic signed [DW-1:0]  y_re, y_im,
  output logic                  ovf
);
  logic signed [DW-1:0] t_re, t_im;
  logic                 c_ovf;

  cmul #(.DW(DW), .TW(TW)) u_cmul (
    .clk, .b_re, .b_im, .w_re, .w_im, .t_re, .t_im, .ovf(c_ovf)
  );

  logic signed [DW-1:0] a1_re, a1_im, a2_re, a2_im;
  always_ff @(posedge clk) begin
    a1_re <= a_re;  a1_im <= a_im;
    a2_re <= a1_re; a2_im <= a1_im;
  end

  logic signed [DW:0] xr, xi, yr, yi;
  always_comb begin
    xr = (DW+1)'(a2_re) + (DW+1)'(t_re);
    xi = (DW+1)'(a2_im) + (DW+1)'(t_im);
    yr = (DW+1)'(a2_re) - (DW+1)'(t_re);
    yi = (DW+1)'(a2_im) - (DW+1)'(t_im);
  end

  // A (DW+1)-bit value fits in DW bits iff its top two bits agree.
  always_ff @(posedge clk) begin
    x_re <= xr[DW-1:0];
    x_im <= xi[DW-1:0];
    y_re <= yr[DW-1:0];
    y_im <= yi[DW-1:0];
    ovf  <= c_ovf | (xr[DW] ^ xr[DW-1]) | (xi[DW] ^ xi[DW-1])
                  | (yr[DW] ^ yr[DW-1]) | (yi[DW] ^ yi[DW-1]);
  end
endmodule
