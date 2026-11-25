/* AXI4-Lite rule checker. It is bound to the two protocol front ends instead of being wired by
   hand, so every port of every block is watched: a testbench only has to include the bind file.
   The rules are the ones a block can break on its own, plus the single transaction per master
   that the interface contract promises and the interconnect relies on. */
module axil_checker
  import soc_pkg::*;
#(
    parameter string NAME = "axil"
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [AXIL_ADDR_WIDTH-1:0] awaddr,
    input logic awvalid,
    input logic awready,
    input logic [AXIL_DATA_WIDTH-1:0] wdata,
    input logic [AXIL_STRB_WIDTH-1:0] wstrb,
    input logic wvalid,
    input logic wready,
    input logic [1:0] bresp,
    input logic bvalid,
    input logic bready,
    input logic [AXIL_ADDR_WIDTH-1:0] araddr,
    input logic arvalid,
    input logic arready,
    input logic [AXIL_DATA_WIDTH-1:0] rdata,
    input logic [1:0] rresp,
    input logic rvalid,
    input logic rready
);

  default clocking cb @(posedge clk_i);
  endclocking
  default disable iff (!rst_ni);

  // Once offered, a transfer stays offered with the same payload until the other side takes it.
  aw_held : assert property (awvalid && !awready |=> awvalid && $stable(awaddr));
  w_held : assert property (wvalid && !wready |=> wvalid && $stable({wdata, wstrb}));
  b_held : assert property (bvalid && !bready |=> bvalid && $stable(bresp));
  ar_held : assert property (arvalid && !arready |=> arvalid && $stable(araddr));
  r_held : assert property (rvalid && !rready |=> rvalid && $stable({rdata, rresp}));

  // Address and write data must be readable numbers while they are being offered.
  aw_known : assert property (awvalid |-> !$isunknown(awaddr));
  w_known : assert property (wvalid |-> !$isunknown({wdata, wstrb}));
  ar_known : assert property (arvalid |-> !$isunknown(araddr));
  b_known : assert property (bvalid |-> !$isunknown(bresp));
  r_known : assert property (rvalid |-> !$isunknown(rresp));

  // AXI4-Lite has no exclusive access, so that response code never appears.
  b_resp_legal : assert property (bvalid |-> bresp != 2'b01);
  r_resp_legal : assert property (rvalid |-> rresp != 2'b01);

  int unsigned aw_cnt, w_cnt, b_cnt, ar_cnt, r_cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_cnt <= 0;
      w_cnt  <= 0;
      b_cnt  <= 0;
      ar_cnt <= 0;
      r_cnt  <= 0;
    end else begin
      if (awvalid && awready) aw_cnt <= aw_cnt + 1;
      if (wvalid && wready) w_cnt <= w_cnt + 1;
      if (bvalid && bready) b_cnt <= b_cnt + 1;
      if (arvalid && arready) ar_cnt <= ar_cnt + 1;
      if (rvalid && rready) r_cnt <= r_cnt + 1;
    end
  end

  /* One transaction at a time per port. This is what lets the interconnect grant a whole
     transaction and skip response reordering, so it is checked and not assumed. */
  one_write : assert property (aw_cnt - b_cnt <= 1);
  one_read : assert property (ar_cnt - r_cnt <= 1);

  // A write answer belongs to an address and to data that were both already accepted.
  b_after_aw : assert property (b_cnt <= aw_cnt);
  b_after_w : assert property (b_cnt <= w_cnt);
  r_after_ar : assert property (r_cnt <= ar_cnt);

  final begin
    if (aw_cnt != 0 || ar_cnt != 0) begin
      $display("CHECKER %s %m: %0d escritas, %0d leituras", NAME, b_cnt, r_cnt);
    end
  end

endmodule
