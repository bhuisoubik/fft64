// 64-point radix-2 DIT FFT accelerator, iterative single-butterfly.
//
//   in : 16-bit Q1.15 complex samples, natural order, valid/ready, 64 per frame
//   out: 23-bit Q8.15 complex bins 0..63, natural order, valid/ready, out_last on bin 63
//        (unscaled: output = sum_n x[n] * exp(-j*2*pi*k*n/64))
//
// Frame flow:  LOAD (64 transfers, written at bit-reversed address)
//           -> COMPUTE (6 stages x STAGE_CYCLES cycles)
//           -> UNLOAD (64 transfers) -> LOAD ...
// No overlap between frames (single buffer).
//
// ovf: sticky flag, cleared when a new frame's first sample is accepted, set if
//      any intermediate value ever left the Q8.15 range (provably never for
//      Q1.15 inputs; kept as a checkable claim).
module fft64_top
  import fft_pkg::*;
#(
  parameter string HEX_FILE = "twiddle.hex"
) (
  input  logic                  clk,
  input  logic                  rst_n,      // synchronous, active low

  input  logic                  in_valid,
  output logic                  in_ready,
  input  logic signed [IN_W-1:0] in_re,
  input  logic signed [IN_W-1:0] in_im,

  output logic                  out_valid,
  input  logic                  out_ready,
  output logic signed [DW-1:0]  out_re,
  output logic signed [DW-1:0]  out_im,
  output logic                  out_last,

  output logic                  ovf
);

  typedef enum logic [1:0] {S_LOAD = 2'd0, S_COMPUTE = 2'd1, S_UNLOAD = 2'd2} state_t;
  state_t state;

  logic [5:0] load_cnt;   // samples accepted this frame
  logic [2:0] stage;      // 0..5
  logic [5:0] cyc;        // 0..STAGE_CYCLES-1 within a stage
  logic [5:0] cur;        // index of the bin presented at the output
  logic       vld;        // output register holds valid data

  wire in_xfer = in_valid & in_ready;
  assign in_ready = (state == S_LOAD);

  // ---------------------------------------------------------------- control
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state    <= S_LOAD;
      load_cnt <= '0;
      stage    <= '0;
      cyc      <= '0;
      cur      <= '0;
      vld      <= 1'b0;
    end else begin
      case (state)
        S_LOAD: begin
          if (in_xfer) begin
            load_cnt <= load_cnt + 6'd1;            // wraps to 0 after 63
            if (load_cnt == 6'(N-1)) begin
              state <= S_COMPUTE;
              stage <= '0;
              cyc   <= '0;
            end
          end
        end
        S_COMPUTE: begin
          if (cyc == 6'(STAGE_CYCLES-1)) begin
            cyc <= '0;
            if (stage == 3'(LOGN-1)) begin
              state <= S_UNLOAD;
              cur   <= '0;
              vld   <= 1'b0;
            end else begin
              stage <= stage + 3'd1;
            end
          end else begin
            cyc <= cyc + 6'd1;
          end
        end
        S_UNLOAD: begin
          vld <= 1'b1;
          if (vld && out_ready) begin
            if (cur == 6'(N-1)) begin
              vld   <= 1'b0;
              cur   <= '0;
              state <= S_LOAD;
            end else begin
              cur <= cur + 6'd1;
            end
          end
        end
        default: state <= S_LOAD;
      endcase
    end
  end

  // ------------------------------------------------------- address generation
  wire        issue = (state == S_COMPUTE) && (cyc < 6'(NHALF));
  wire  [4:0] j     = cyc[4:0];

  logic [5:0] agu_a, agu_b;
  logic [4:0] agu_tw;
  fft_agu u_agu (.stage(stage), .j(j), .a_addr(agu_a), .b_addr(agu_b), .tw_idx(agu_tw));

  // issue-to-writeback pipeline bookkeeping (index 3 == write-back cycle)
  logic [PIPE_LAT-1:0] vpipe;
  logic [5:0]          a_pipe [PIPE_LAT];
  logic [5:0]          b_pipe [PIPE_LAT];

  always_ff @(posedge clk) begin
    if (!rst_n) vpipe <= '0;
    else        vpipe <= {vpipe[PIPE_LAT-2:0], issue};
    a_pipe[0] <= agu_a;
    b_pipe[0] <= agu_b;
    for (int i = 1; i < PIPE_LAT; i++) begin
      a_pipe[i] <= a_pipe[i-1];
      b_pipe[i] <= b_pipe[i-1];
    end
  end
  wire wr_en = vpipe[PIPE_LAT-1];

  // ------------------------------------------------------------------ memory
  logic [5:0]          ra_addr, rb_addr;
  logic [2*DW-1:0]     ra_data, rb_data;
  logic [5:0]          cur_next;

  // address of the bin that the output register will hold after this edge
  assign cur_next = (vld && out_ready) ? (cur + 6'd1) : cur;

  assign ra_addr = (state == S_COMPUTE) ? agu_a : cur_next;
  assign rb_addr = (state == S_COMPUTE) ? agu_b : (ra_addr ^ 6'd1);   // opposite parity

  logic                we_a, we_b;
  logic [5:0]          wa_addr, wb_addr;
  logic [2*DW-1:0]     wa_data, wb_data;

  logic signed [DW-1:0] x_re, x_im, y_re, y_im;

  always_comb begin
    if (state == S_LOAD) begin
      we_a    = in_xfer;
      wa_addr = bitrev6(load_cnt);
      wa_data = {DW'(in_re), DW'(in_im)};        // Q1.15 -> Q8.15: sign extend
    end else begin
      we_a    = wr_en;
      wa_addr = a_pipe[PIPE_LAT-1];
      wa_data = {x_re, x_im};
    end
    we_b    = wr_en;
    wb_addr = b_pipe[PIPE_LAT-1];
    wb_data = {y_re, y_im};
  end

  fft_mem #(.DW(DW)) u_mem (
    .clk,
    .we_a, .wa_addr, .wa_data,
    .we_b, .wb_addr, .wb_data,
    .ra_addr, .rb_addr, .ra_data, .rb_data
  );

  // --------------------------------------------------------- twiddle + butterfly
  logic signed [TW_W-1:0] w_re, w_im;
  twiddle_rom #(.HEX_FILE(HEX_FILE)) u_rom (.clk, .addr(agu_tw), .w_re, .w_im);

  logic bf_ovf;
  butterfly #(.DW(DW), .TW(TW_W)) u_bf (
    .clk,
    .a_re(ra_data[2*DW-1:DW]), .a_im(ra_data[DW-1:0]),
    .b_re(rb_data[2*DW-1:DW]), .b_im(rb_data[DW-1:0]),
    .w_re, .w_im,
    .x_re, .x_im, .y_re, .y_im,
    .ovf(bf_ovf)
  );

  // ------------------------------------------------------------------ outputs
  assign out_valid = vld;
  assign out_re    = ra_data[2*DW-1:DW];
  assign out_im    = ra_data[DW-1:0];
  assign out_last  = vld && (cur == 6'(N-1));

  always_ff @(posedge clk) begin
    if (!rst_n)                                      ovf <= 1'b0;
    else if (in_xfer && load_cnt == 6'd0)            ovf <= 1'b0;
    else if (wr_en && bf_ovf)                        ovf <= 1'b1;
  end

endmodule
