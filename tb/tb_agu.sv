module tb_agu;
  logic [2:0] stage;
  logic [4:0] j;
  logic [5:0] a_addr, b_addr;
  logic [4:0] tw_idx;
  fft_agu dut (.*);

  int fd, r, s, jj, ea, eb, et, n = 0, errors = 0;
  initial begin
    fd = $fopen("agu_vec.txt", "r");
    if (fd == 0) $fatal(1, "cannot open agu_vec.txt");
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%d %d %d %d %d\n", s, jj, ea, eb, et);
      if (r == 5) begin
        stage = 3'(s); j = 5'(jj);
        #1;
        if (a_addr !== 6'(ea) || b_addr !== 6'(eb) || tw_idx !== 5'(et)) begin
          $display("MISMATCH s=%0d j=%0d got a=%0d b=%0d tw=%0d exp a=%0d b=%0d tw=%0d",
                   s, jj, a_addr, b_addr, tw_idx, ea, eb, et);
          errors++;
        end
        n++;
      end
    end
    if (errors == 0) $display("tb_agu: PASS (%0d vectors)", n);
    else $fatal(1, "tb_agu: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
