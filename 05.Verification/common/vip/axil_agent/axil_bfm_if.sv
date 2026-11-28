/* Active AXI4-Lite master for a harness without CPU. It takes one transaction at a time and
   never offers a write and a read together, which is what the interconnect expects of the data
   port of the CPU. The address of a write goes out with its data, never after it. Every wait is
   bounded: a task that runs out of cycles drops its valid signals and reports failure. */
interface axil_bfm_if (
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

  clocking cb @(posedge clk);
    default input #1step output #1;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  initial begin
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
  end

  task automatic idle();
    cb.awvalid <= 1'b0;
    cb.wvalid <= 1'b0;
    cb.bready <= 1'b0;
    cb.arvalid <= 1'b0;
    cb.rready <= 1'b0;
  endtask

  task automatic write(input logic [31:0] addr, input logic [31:0] data,
                       input logic [3:0] strb, input int unsigned timeout,
                       output logic [1:0] resp, output bit ok);
    bit aw_done = 1'b0;
    bit w_done = 1'b0;
    int unsigned waited = 0;

    ok = 1'b0;
    resp = 2'bxx;
    @(cb);
    cb.awaddr <= addr;
    cb.awvalid <= 1'b1;
    cb.wdata <= data;
    cb.wstrb <= strb;
    cb.wvalid <= 1'b1;
    cb.bready <= 1'b1;
    while (!(aw_done && w_done)) begin
      @(cb);
      if (!aw_done && cb.awready) begin
        aw_done = 1'b1;
        cb.awvalid <= 1'b0;
      end
      if (!w_done && cb.wready) begin
        w_done = 1'b1;
        cb.wvalid <= 1'b0;
      end
      if (++waited > timeout) begin
        idle();
        return;
      end
    end
    do begin
      @(cb);
      if (++waited > timeout) begin
        idle();
        return;
      end
    end while (!cb.bvalid);
    resp = cb.bresp;
    cb.bready <= 1'b0;
    ok = 1'b1;
  endtask

  task automatic read(input logic [31:0] addr, input int unsigned timeout,
                      output logic [31:0] data, output logic [1:0] resp, output bit ok);
    int unsigned waited = 0;

    ok = 1'b0;
    data = 'x;
    resp = 2'bxx;
    @(cb);
    cb.araddr <= addr;
    cb.arvalid <= 1'b1;
    cb.rready <= 1'b1;
    do begin
      @(cb);
      if (++waited > timeout) begin
        idle();
        return;
      end
    end while (!cb.arready);
    cb.arvalid <= 1'b0;
    while (!cb.rvalid) begin
      @(cb);
      if (++waited > timeout) begin
        idle();
        return;
      end
    end
    data = cb.rdata;
    resp = cb.rresp;
    cb.rready <= 1'b0;
    ok = 1'b1;
  endtask

endinterface
