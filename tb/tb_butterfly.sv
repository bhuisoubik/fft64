module tb_butterfly;
  import fft_pkg::*;
  localparam int LAT = 3;
  localparam int MAXV = 8192;

  logic clk = 0;
  always #5 clk = ~clk;
  logic signed [DW-1:0]   a_re = 0, a_im = 0, b_re = 0, b_im = 0;
  logic signed [TW_W-1:0] w_re = 0, w_im = 0;
  logic signed [DW-1:0]   x_re, x_im, y_re, y_im;
  logic                   ovf;
  butterfly dut (.*);

  logic [DW-1:0]   va_re [MAXV], va_im [MAXV], vb_re [MAXV], vb_im [MAXV];
  logic [TW_W-1:0] vw_re [MAXV], vw_im [MAXV];
  logic [DW-1:0]   vx_re [MAXV], vx_im [MAXV], vy_re [MAXV], vy_im [MAXV];
  logic            vov [MAXV];
  int n = 0, fd, r, errors = 0, nov = 0;

  initial begin
    fd = $fopen("bfly_vec.txt", "r");
    if (fd == 0) $fatal(1, "cannot open bfly_vec.txt");
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h\n",
                  va_re[n], va_im[n], vb_re[n], vb_im[n], vw_re[n], vw_im[n],
                  vx_re[n], vx_im[n], vy_re[n], vy_im[n], vov[n]);
      if (r == 11) n++;
    end
    for (int c = 0; c < n + LAT; c++) begin
      @(negedge clk);
      if (c >= LAT) begin
        int i = c - LAT;
        if (ovf !== vov[i]) begin
          $display("OVF MISMATCH vec %0d got %b exp %b", i, ovf, vov[i]);
          errors++;
        end else if (!vov[i] && (x_re !== $signed(vx_re[i]) || x_im !== $signed(vx_im[i]) ||
                                 y_re !== $signed(vy_re[i]) || y_im !== $signed(vy_im[i]))) begin
          $display("MISMATCH vec %0d got X(%0d,%0d) Y(%0d,%0d) exp X(%0d,%0d) Y(%0d,%0d)", i,
                   x_re, x_im, y_re, y_im,
                   $signed(vx_re[i]), $signed(vx_im[i]), $signed(vy_re[i]), $signed(vy_im[i]));
          errors++;
        end
        if (vov[i]) nov++;
      end
      if (c < n) begin
        a_re = $signed(va_re[c]); a_im = $signed(va_im[c]);
        b_re = $signed(vb_re[c]); b_im = $signed(vb_im[c]);
        w_re = $signed(vw_re[c]); w_im = $signed(vw_im[c]);
      end
    end
    if (errors == 0) $display("tb_butterfly: PASS (%0d vectors, %0d overflow-flag vectors)", n, nov);
    else $fatal(1, "tb_butterfly: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
