/* Passive view of one AXI4-Lite port. The harness drives every signal from the port it watches,
   so the environment observes the bus without being able to touch it. */

// Connects TAP to the port whose signals are named PFX<signal>SFX, e.g. u_dut.mst_awaddr[1].
`define MM_TAP(TAP, PFX, SFX) \
  assign TAP.awaddr = PFX``awaddr SFX; \
  assign TAP.awvalid = PFX``awvalid SFX; \
  assign TAP.awready = PFX``awready SFX; \
  assign TAP.wdata = PFX``wdata SFX; \
  assign TAP.wstrb = PFX``wstrb SFX; \
  assign TAP.wvalid = PFX``wvalid SFX; \
  assign TAP.wready = PFX``wready SFX; \
  assign TAP.bresp = PFX``bresp SFX; \
  assign TAP.bvalid = PFX``bvalid SFX; \
  assign TAP.bready = PFX``bready SFX; \
  assign TAP.araddr = PFX``araddr SFX; \
  assign TAP.arvalid = PFX``arvalid SFX; \
  assign TAP.arready = PFX``arready SFX; \
  assign TAP.rdata = PFX``rdata SFX; \
  assign TAP.rresp = PFX``rresp SFX; \
  assign TAP.rvalid = PFX``rvalid SFX; \
  assign TAP.rready = PFX``rready SFX;

interface axil_tap_if (
    input logic clk,
    input logic rst_n
);

  logic [31:0] awaddr;
  logic awvalid;
  logic awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [31:0] araddr;
  logic arvalid;
  logic arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n;
    input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bresp, bvalid, bready;
    input araddr, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

endinterface
