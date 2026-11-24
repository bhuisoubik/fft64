// System testbench for fft64_top.
// Plusargs: +INFILE= +OUTFILE= +SNAPFILE= +IN_PROB=<0..100> +OUT_PROB=<0..100> +SEED=
// Reads frames from INFILE ("RRRR IIII" per line, 64 lines per frame), writes the
// output stream to OUTFILE ("RRRRRR IIIIII" 23-bit hex) and, after every stage, a
// snapshot of the internal memory to SNAPFILE for stage-level golden comparison.
module tb_fft64;
  import fft_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst_n = 0;
  logic in_valid = 0, in_ready;
  logic signed [IN_W-1:0] in_re = 0, in_im = 0;
  logic out_valid, out_ready = 0;
  logic signed [DW-1:0] out_re, out_im;
  logic out_last, ovf;

  fft64_top #(.HEX_FILE("twiddle.hex")) dut (.*);

  // ------------------------------------------------------------ configuration
  string infile = "input.hex", outfile = "output.hex", snapfile = "snap.txt";
  int in_prob = 100, out_prob = 100;
  int unsigned seed = 1;
  logic [31:0] rng;

  function automatic bit hit(input int prob);
    rng ^= rng << 13;  rng ^= rng >> 17;  rng ^= rng << 5;
    return int'(rng % 100) < prob;
  endfunction

  // ---------------------------------------------------------------- stimulus
  logic [15:0] q_re [$], q_im [$];
  int nframes;
  int ofd, sfd;
  int cycle = 0;

  initial begin
    int fd, r;
    logic [15:0] a, b;
    void'($value$plusargs("INFILE=%s", infile));
    void'($value$plusargs("OUTFILE=%s", outfile));
    void'($value$plusargs("SNAPFILE=%s", snapfile));
    void'($value$plusargs("IN_PROB=%d", in_prob));
    void'($value$plusargs("OUT_PROB=%d", out_prob));
    void'($value$plusargs("SEED=%d", seed));
    rng = 32'h9E3779B9 ^ seed;
    if (rng == 0) rng = 1;

    fd = $fopen(infile, "r");
    if (fd == 0) $fatal(1, "cannot open %s", infile);
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%h %h\n", a, b);
      if (r == 2) begin q_re.push_back(a); q_im.push_back(b); end
    end
    $fclose(fd);
    nframes = q_re.size() / N;
    ofd = $fopen(outfile, "w");
    sfd = $fopen(snapfile, "w");
    $display("tb_fft64: %0d frames, IN_PROB=%0d OUT_PROB=%0d SEED=%0d", nframes, in_prob, out_prob, seed);

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    for (int f = 0; f < nframes; f++) begin
      for (int i = 0; i < N; i++) begin
        while (!hit(in_prob)) begin in_valid <= 0; @(posedge clk); end
        in_valid <= 1;
        in_re    <= $signed(q_re[f*N+i]);
        in_im    <= $signed(q_im[f*N+i]);
        do @(posedge clk); while (!in_ready);        // transfer happened at this edge
      end
      in_valid <= 0;
    end
  end

  // ------------------------------------------------------- output monitor/checks
  int out_idx = 0, out_frames = 0, errors = 0;
  int in_cnt = 0, t_in_done = 0, lat = -1, lat_ref = -1;
  bit stall_q = 0, first_seen = 0;
  logic signed [DW-1:0] held_re, held_im;
  logic held_last;

  always @(posedge clk) if (rst_n) begin
    cycle <= cycle + 1;
    out_ready <= hit(out_prob);

    // input-side bookkeeping (latency from last accepted sample to first valid output)
    if (in_valid && in_ready) begin
      in_cnt <= (in_cnt == N-1) ? 0 : in_cnt + 1;
      if (in_cnt == N-1) begin t_in_done <= cycle; first_seen <= 0; end
    end
    if (out_valid && !first_seen) begin
      first_seen <= 1;
      lat = cycle - t_in_done;
      if (lat_ref < 0) lat_ref = lat;
      if (lat != lat_ref) begin $display("ERROR: latency %0d != %0d", lat, lat_ref); errors++; end
    end

    // protocol checks
    if (stall_q && !(out_valid && out_re === held_re && out_im === held_im && out_last === held_last)) begin
      $display("ERROR: output changed/dropped while stalled (frame %0d idx %0d)", out_frames, out_idx);
      errors++;
    end
    if (out_valid && in_ready) begin $display("ERROR: in_ready while out_valid"); errors++; end
    stall_q   <= out_valid && !out_ready;
    held_re   <= out_re;
    held_im   <= out_im;
    held_last <= out_last;

    if (out_valid && out_ready) begin
      $fwrite(ofd, "%06h %06h\n", {1'b0, out_re}, {1'b0, out_im});
      if (out_last !== (out_idx == N-1)) begin
        $display("ERROR: out_last=%b at idx %0d", out_last, out_idx); errors++;
      end
      if (out_idx == 0 && ovf) begin $display("ERROR: ovf set in frame %0d", out_frames); errors++; end
      if (out_idx == N-1) begin out_idx <= 0; out_frames <= out_frames + 1; end
      else                out_idx <= out_idx + 1;
    end

    if (out_frames == nframes && nframes > 0) begin
      $fclose(ofd); $fclose(sfd);
      $display("tb_fft64: done, %0d frames, %0d cycles, first-output latency after last input = %0d cycles, %0d protocol errors",
               nframes, cycle, lat_ref, errors);
      if (errors != 0) $fatal(1, "tb_fft64: FAIL");
      $finish;
    end
    if (cycle > nframes * 6000 + 2000) $fatal(1, "tb_fft64: watchdog timeout");
  end

  // --------------------------------------------------- per-stage memory snapshots
  int snap_frame = 0;
  logic [1:0] prev_state = 0;

  function automatic void dump_snap(input int frame, input int label);
    logic [2*DW-1:0] w;
    for (int a = 0; a < N; a++) begin
      w = (^a[5:0]) ? dut.u_mem.bank1[a >> 1] : dut.u_mem.bank0[a >> 1];
      $fwrite(sfd, "%0d %0d %0d %0d %0d\n", frame, label, a,
              $signed(w[2*DW-1:DW]), $signed(w[DW-1:0]));
    end
  endfunction

  // label k = memory contents after k completed stages (0 = bit-reversed input)
  always @(negedge clk) if (rst_n) begin
    if (dut.state == 2'd1 && dut.cyc == 0) dump_snap(snap_frame, int'(dut.stage));
    if (dut.state == 2'd2 && prev_state == 2'd1) begin
      dump_snap(snap_frame, LOGN);
      snap_frame++;
    end
    prev_state <= dut.state;
  end
endmodule
