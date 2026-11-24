// Complex multiplier t = b * w, 2-cycle latency, 4 real multipliers.
//   b: Q8.15 (23 b)   w: Q2.14 (16 b)   t: Q8.15 (23 b)
// Stage 1: four 39-bit products.
// Stage 2: add/sub in 40 bits, round half-up (+2^13, >>> 14) ONCE, truncate to 23 b.
// ovf is set when the rounded result does not fit in 23 bits (never expected).
module cmul #(
  parameter int DW = 23,
  parameter int TW = 16,
  parameter int TF = 14
) (
  input  logic                  clk,
  input  logic signed [DW-1:0]  b_re,
  input  logic signed [DW-1:0]  b_im,
  input  logic signed [TW-1:0]  w_re,
  input  logic signed [TW-1:0]  w_im,
  output logic signed [DW-1:0]  t_re,
  output logic signed [DW-1:0]  t_im,
  output logic                  ovf
);
  localparam int PW = DW + TW;   // 39
  localparam int SW = PW + 1;    // 40

  localparam logic signed [SW-1:0] HALF = SW'(1) << (TF - 1);
  localparam logic signed [SW-1:0] RMAX = (SW'(1) << (DW - 1)) - SW'(1);
  localparam logic signed [SW-1:0] RMIN = -(SW'(1) << (DW - 1));

  logic signed [PW-1:0] p_rr, p_ii, p_ri, p_ir;

  always_ff @(posedge clk) begin
    p_rr <= PW'(b_re) * PW'(w_re);
    p_ii <= PW'(b_im) * PW'(w_im);
    p_ri <= PW'(b_re) * PW'(w_im);
    p_ir <= PW'(b_im) * PW'(w_re);
  end

  logic signed [SW-1:0] s_re, s_im, r_re, r_im;
  always_comb begin
    s_re = SW'(p_rr) - SW'(p_ii);
    s_im = SW'(p_ri) + SW'(p_ir);
    r_re = (s_re + HALF) >>> TF;
    r_im = (s_im + HALF) >>> TF;
  end

  always_ff @(posedge clk) begin
    t_re <= r_re[DW-1:0];
    t_im <= r_im[DW-1:0];
    ovf  <= (r_re > RMAX) || (r_re < RMIN) || (r_im > RMAX) || (r_im < RMIN);
  end
endmodule
