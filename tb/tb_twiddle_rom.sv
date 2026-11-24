// Checks the ROM image against an independent SystemVerilog real-math computation
// (so the Python table generator is cross-checked, not just echoed).
module tb_twiddle_rom;
  logic clk = 0;
  always #5 clk = ~clk;
  logic [4:0] addr = 0;
  logic signed [15:0] w_re, w_im;
  twiddle_rom #(.HEX_FILE("twiddle.hex")) dut (.*);

  real ang;
  int  exp_re, exp_im, errors = 0;
  initial begin
    for (int k = 0; k < 32; k++) begin
      addr = 5'(k);
      @(negedge clk);
      ang    = 2.0 * 3.14159265358979323846 * k / 64.0;
      exp_re = int'($floor( $cos(ang) * 16384.0 + 0.5));
      exp_im = int'($floor(-$sin(ang) * 16384.0 + 0.5));
      if (w_re !== 16'(exp_re) || w_im !== 16'(exp_im)) begin
        $display("MISMATCH k=%0d got (%0d,%0d) exp (%0d,%0d)", k, w_re, w_im, exp_re, exp_im);
        errors++;
      end
    end
    if (errors == 0) $display("tb_twiddle_rom: PASS (32 entries)");
    else $fatal(1, "tb_twiddle_rom: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
