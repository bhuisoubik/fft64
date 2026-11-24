module tb_cmul;
  import fft_pkg::*;
  localparam int LAT = 2;
  localparam int MAXV = 8192;

  logic clk = 0;
  always #5 clk = ~clk;
  logic signed [DW-1:0]   b_re = 0, b_im = 0;
  logic signed [TW_W-1:0] w_re = 0, w_im = 0;
  logic signed [DW-1:0]   t_re, t_im;
  logic                   ovf;
  cmul dut (.*);

  logic [DW-1:0]   vb_re [MAXV], vb_im [MAXV], vt_re [MAXV], vt_im [MAXV];
  logic [TW_W-1:0] vw_re [MAXV], vw_im [MAXV];
  logic            vov [MAXV];
  int n = 0, fd, r, errors = 0, tie_ovf = 0;

  initial begin
    fd = $fopen("cmul_vec.txt", "r");
    if (fd == 0) $fatal(1, "cannot open cmul_vec.txt");
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%h %h %h %h %h %h %h\n",
                  vb_re[n], vb_im[n], vw_re[n], vw_im[n], vt_re[n], vt_im[n], vov[n]);
      if (r == 7) n++;
    end
    for (int c = 0; c < n + LAT; c++) begin
      @(negedge clk);
      if (c >= LAT) begin
        int i = c - LAT;
        if (ovf !== vov[i]) begin
          $display("OVF MISMATCH vec %0d got %b exp %b", i, ovf, vov[i]);
          errors++;
        end else if (!vov[i] && (t_re !== $signed(vt_re[i]) || t_im !== $signed(vt_im[i]))) begin
          $display("MISMATCH vec %0d b=(%0d,%0d) w=(%0d,%0d) got (%0d,%0d) exp (%0d,%0d)", i,
                   $signed(vb_re[i]), $signed(vb_im[i]), $signed(vw_re[i]), $signed(vw_im[i]),
                   t_re, t_im, $signed(vt_re[i]), $signed(vt_im[i]));
          errors++;
        end
        if (vov[i]) tie_ovf++;
      end
      if (c < n) begin
        b_re = $signed(vb_re[c]); b_im = $signed(vb_im[c]);
        w_re = $signed(vw_re[c]); w_im = $signed(vw_im[c]);
      end
    end
    if (errors == 0) $display("tb_cmul: PASS (%0d vectors, %0d overflow-flag vectors)", n, tie_ovf);
    else $fatal(1, "tb_cmul: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
