module tb_env_smoke;

  import uvm_pkg::*;
  import env_smoke_pkg::*;

  logic clk = 1'b0;
  always #5ns clk = ~clk;

  env_smoke_if #(.WIDTH(WIDTH)) smoke_if (.clk(clk));

  env_smoke_counter #(
      .WIDTH(WIDTH)
  ) dut (
      .clk  (clk),
      .rst_n(smoke_if.rst_n),
      .en   (smoke_if.en),
      .count(smoke_if.count)
  );

  initial begin
    uvm_config_db#(env_smoke_vif_t)::set(null, "uvm_test_top", "vif", smoke_if);
    run_test();
  end

endmodule
