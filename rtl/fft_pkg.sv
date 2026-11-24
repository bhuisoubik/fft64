// -----------------------------------------------------------------------------
// fft_pkg: shared constants for the 64-point radix-2 DIT FFT accelerator.
//
// Number formats (Qm.n, m includes the sign bit):
//   input sample   Q1.15  (16 bit)   per component
//   twiddle        Q2.14  (16 bit)   per component
//   memory/output  Q8.15  (23 bit)   per component, unscaled (gain = 64)
// -----------------------------------------------------------------------------
package fft_pkg;
  localparam int N      = 64;
  localparam int LOGN   = 6;
  localparam int NHALF  = N / 2;      // butterflies per stage

  localparam int IN_W    = 16;        // Q1.15
  localparam int TW_W    = 16;        // Q2.14
  localparam int DW      = 23;        // Q8.15
  localparam int FRAC    = 15;
  localparam int TW_FRAC = 14;

  // Cycles from "address issued" to "result written back":
  //   RAM read (1) + cmul (2) + add/sub (1) = 4.
  // The next stage may issue its first read PIPE_LAT cycles after the previous
  // stage issued its last butterfly.
  localparam int PIPE_LAT     = 4;
  localparam int STAGE_CYCLES = NHALF + PIPE_LAT;   // 36

  function automatic logic [LOGN-1:0] bitrev6(input logic [LOGN-1:0] x);
    logic [LOGN-1:0] r;
    for (int i = 0; i < LOGN; i++) r[i] = x[LOGN-1-i];
    return r;
  endfunction
endpackage
