// Address generation unit (combinational).
// For stage s (0..5) and butterfly index j (0..31):
//   A  = j with a 0 bit inserted at bit position s
//   B  = A | 2^s
//   tw = (j mod 2^s) * 2^(5-s)      -> index into the 32-entry twiddle ROM
module fft_agu (
  input  logic [2:0] stage,
  input  logic [4:0] j,
  output logic [5:0] a_addr,
  output logic [5:0] b_addr,
  output logic [4:0] tw_idx
);
  logic [4:0] lo, hi;
  always_comb begin
    lo     = j & 5'((6'd1 << stage) - 6'd1);
    hi     = j >> stage;
    a_addr = (6'(hi) << (stage + 3'd1)) | 6'(lo);
    b_addr = a_addr | (6'd1 << stage);
    tw_idx = lo << (3'd5 - stage);
  end
endmodule
