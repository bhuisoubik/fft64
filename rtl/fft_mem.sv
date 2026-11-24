// Two-bank in-place data memory, 64 x {re,im} words (2*DW bits each).
//
// Bank select = XOR of all 6 address bits; bank-local address = addr[5:1].
// A butterfly pair (A, B = A + 2^s) differs in exactly one address bit, so the
// two always map to different banks -> 2 reads and 2 writes per cycle with only
// single-port banks.
//
// Rules for the caller:
//   * Read:  ra_addr and rb_addr must have different parity when both are used.
//            (rb_data is only meaningful in that case; ra_data is always valid.)
//   * Write: wa_addr and wb_addr must have different parity when both enabled.
// Reads have 1-cycle latency; a read of an address written in the same cycle
// returns the OLD data.
module fft_mem #(
  parameter int DW = 23
) (
  input  logic                clk,
  // write ports
  input  logic                we_a,
  input  logic [5:0]          wa_addr,
  input  logic [2*DW-1:0]     wa_data,
  input  logic                we_b,
  input  logic [5:0]          wb_addr,
  input  logic [2*DW-1:0]     wb_data,
  // read ports
  input  logic [5:0]          ra_addr,
  input  logic [5:0]          rb_addr,
  output logic [2*DW-1:0]     ra_data,
  output logic [2*DW-1:0]     rb_data
);
  logic [2*DW-1:0] bank0 [0:31];
  logic [2*DW-1:0] bank1 [0:31];

  // ---------------- write steering ----------------
  logic pa, pb;
  logic        w0_en, w1_en;
  logic [4:0]  w0_addr, w1_addr;
  logic [2*DW-1:0] w0_data, w1_data;

  always_comb begin
    pa = ^wa_addr;
    pb = ^wb_addr;
    // bank 0
    w0_en   = (we_a & ~pa) | (we_b & ~pb);
    w0_addr = (we_a & ~pa) ? wa_addr[5:1] : wb_addr[5:1];
    w0_data = (we_a & ~pa) ? wa_data      : wb_data;
    // bank 1
    w1_en   = (we_a & pa) | (we_b & pb);
    w1_addr = (we_a & pa) ? wa_addr[5:1] : wb_addr[5:1];
    w1_data = (we_a & pa) ? wa_data      : wb_data;
  end

  always_ff @(posedge clk) begin
    if (w0_en) bank0[w0_addr] <= w0_data;
    if (w1_en) bank1[w1_addr] <= w1_data;
  end

  // ---------------- read steering ----------------
  logic sa, sa_q;
  logic [4:0] r0_addr, r1_addr;
  logic [2*DW-1:0] q0, q1;

  always_comb begin
    sa      = ^ra_addr;
    r0_addr = sa ? rb_addr[5:1] : ra_addr[5:1];   // bank0 serves A when parity(A)==0
    r1_addr = sa ? ra_addr[5:1] : rb_addr[5:1];
  end

  always_ff @(posedge clk) begin
    q0   <= bank0[r0_addr];
    q1   <= bank1[r1_addr];
    sa_q <= sa;
  end

  assign ra_data = sa_q ? q1 : q0;
  assign rb_data = sa_q ? q0 : q1;

`ifndef SYNTHESIS
  // synthesis translate_off
  always @(posedge clk) begin
    if (we_a && we_b && (pa == pb))
      $fatal(1, "fft_mem: write bank conflict (wa=%0d wb=%0d)", wa_addr, wb_addr);
  end
  // synthesis translate_on
`endif
endmodule
