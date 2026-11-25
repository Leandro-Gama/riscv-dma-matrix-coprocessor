/* Interconnect of the system: two masters (data port of the CPU, DMA) reach three slaves (data
   memory, DMA registers, accelerator). The arbiter grants a whole transaction, so the five
   channels of the winning master are wired to one slave until the response completes. The slave
   choice is registered at the start, because a master may change the address right after the
   address channel is accepted. A write is only taken once its address is on the bus: a master
   that offers write data first simply waits, which is allowed and keeps the choice of slave
   unambiguous. */
module soc_axil_xbar
  import soc_pkg::*;
#(
    parameter int DMEM_BYTES = DMEM_BYTES_DEFAULT,
    parameter logic [0:0] ARB_POLICY = ARB_DMA_PRIORITY
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [NUM_MASTERS-1:0] s_axi_awvalid,
    output logic [NUM_MASTERS-1:0] s_axi_awready,
    input  logic [NUM_MASTERS-1:0][AXIL_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [NUM_MASTERS-1:0][AXIL_STRB_WIDTH-1:0] s_axi_wstrb,
    input  logic [NUM_MASTERS-1:0] s_axi_wvalid,
    output logic [NUM_MASTERS-1:0] s_axi_wready,
    output logic [NUM_MASTERS-1:0][1:0] s_axi_bresp,
    output logic [NUM_MASTERS-1:0] s_axi_bvalid,
    input  logic [NUM_MASTERS-1:0] s_axi_bready,
    input  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [NUM_MASTERS-1:0] s_axi_arvalid,
    output logic [NUM_MASTERS-1:0] s_axi_arready,
    output logic [NUM_MASTERS-1:0][AXIL_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [NUM_MASTERS-1:0][1:0] s_axi_rresp,
    output logic [NUM_MASTERS-1:0] s_axi_rvalid,
    input  logic [NUM_MASTERS-1:0] s_axi_rready,

    output logic [NUM_SLAVES-1:0][AXIL_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [NUM_SLAVES-1:0] m_axi_awvalid,
    input  logic [NUM_SLAVES-1:0] m_axi_awready,
    output logic [NUM_SLAVES-1:0][AXIL_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [NUM_SLAVES-1:0][AXIL_STRB_WIDTH-1:0] m_axi_wstrb,
    output logic [NUM_SLAVES-1:0] m_axi_wvalid,
    input  logic [NUM_SLAVES-1:0] m_axi_wready,
    input  logic [NUM_SLAVES-1:0][1:0] m_axi_bresp,
    input  logic [NUM_SLAVES-1:0] m_axi_bvalid,
    output logic [NUM_SLAVES-1:0] m_axi_bready,
    output logic [NUM_SLAVES-1:0][AXIL_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [NUM_SLAVES-1:0] m_axi_arvalid,
    input  logic [NUM_SLAVES-1:0] m_axi_arready,
    input  logic [NUM_SLAVES-1:0][AXIL_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [NUM_SLAVES-1:0][1:0] m_axi_rresp,
    input  logic [NUM_SLAVES-1:0] m_axi_rvalid,
    output logic [NUM_SLAVES-1:0] m_axi_rready
);

  logic [NUM_MASTERS-1:0] mreq, grant;
  logic hold, start, done;

  logic [AXIL_ADDR_WIDTH-1:0] g_awaddr, g_araddr;
  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] mst_addr;
  logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0] mst_sel;
  logic [NUM_MASTERS-1:0] mst_err;
  logic [AXIL_DATA_WIDTH-1:0] g_wdata;
  logic [AXIL_STRB_WIDTH-1:0] g_wstrb;
  logic g_awvalid, g_wvalid, g_bready, g_arvalid, g_rready;

  logic [NUM_SLAVES-1:0] dec_sel, sel, sel_q;
  logic dec_err, err_sel, err_q;

  logic e_awready, e_wready, e_bvalid, e_arready, e_rvalid;
  logic [1:0] e_bresp, e_rresp;
  logic [AXIL_DATA_WIDTH-1:0] e_rdata;

  logic r_awready, r_wready, r_bvalid, r_arready, r_rvalid;
  logic [1:0] r_bresp, r_rresp;
  logic [AXIL_DATA_WIDTH-1:0] r_rdata;

  for (genvar m = 0; m < NUM_MASTERS; m++) begin : gen_req
    assign mreq[m] = s_axi_awvalid[m] || s_axi_arvalid[m];
  end

  // The grant is one hot, so picking the winning master is a plain mux.
  always_comb begin
    g_awaddr = '0;
    g_awvalid = 1'b0;
    g_wdata = '0;
    g_wstrb = '0;
    g_wvalid = 1'b0;
    g_bready = 1'b0;
    g_araddr = '0;
    g_arvalid = 1'b0;
    g_rready = 1'b0;
    for (int m = 0; m < NUM_MASTERS; m++) begin
      if (grant[m]) begin
        g_awaddr = s_axi_awaddr[m];
        g_awvalid = s_axi_awvalid[m];
        g_wdata = s_axi_wdata[m];
        g_wstrb = s_axi_wstrb[m];
        g_wvalid = s_axi_wvalid[m];
        g_bready = s_axi_bready[m];
        g_araddr = s_axi_araddr[m];
        g_arvalid = s_axi_arvalid[m];
        g_rready = s_axi_rready[m];
      end
    end
  end

  assign start = g_awvalid || g_arvalid;
  assign done = (r_bvalid && g_bready) || (r_rvalid && g_rready);

  soc_axil_arbiter #(
      .ARB_POLICY(ARB_POLICY)
  ) u_arb (
      .clk_i,
      .rst_ni,
      .req_i(mreq),
      .start_i(start),
      .done_i(done),
      .grant_o(grant),
      .hold_o(hold)
  );

  /* Every master is decoded in parallel with arbitration and only the resulting selection is
     muxed by the grant. Muxing the address first and decoding afterwards puts the address
     comparators in series with the arbiter, which measured 1184 ps on the longest path. */
  for (genvar m = 0; m < NUM_MASTERS; m++) begin : gen_dec
    assign mst_addr[m] = s_axi_awvalid[m] ? s_axi_awaddr[m] : s_axi_araddr[m];

    soc_axil_addr_decoder #(
        .DMEM_BYTES(DMEM_BYTES)
    ) u_dec (
        .addr_i(mst_addr[m]),
        .sel_o(mst_sel[m]),
        .decerr_o(mst_err[m])
    );
  end

  always_comb begin
    dec_sel = '0;
    dec_err = 1'b0;
    for (int m = 0; m < NUM_MASTERS; m++) begin
      if (grant[m]) begin
        dec_sel = mst_sel[m];
        dec_err = mst_err[m];
      end
    end
  end

  assign sel = hold ? sel_q : dec_sel;
  assign err_sel = hold ? err_q : dec_err;

  /* The address is only guaranteed stable until its channel is accepted, so the slave that owns
     this transaction is remembered for the rest of it. */
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sel_q <= '0;
      err_q <= 1'b0;
    end else if (!hold && start) begin
      sel_q <= dec_sel;
      err_q <= dec_err;
    end
  end

  for (genvar s = 0; s < NUM_SLAVES; s++) begin : gen_slv
    assign m_axi_awaddr[s] = g_awaddr;
    assign m_axi_awvalid[s] = sel[s] && g_awvalid;
    assign m_axi_wdata[s] = g_wdata;
    assign m_axi_wstrb[s] = g_wstrb;
    assign m_axi_wvalid[s] = sel[s] && g_wvalid;
    assign m_axi_bready[s] = sel[s] && g_bready;
    assign m_axi_araddr[s] = g_araddr;
    assign m_axi_arvalid[s] = sel[s] && g_arvalid;
    assign m_axi_rready[s] = sel[s] && g_rready;
  end

  soc_axil_err_slave u_err (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr(g_awaddr),
      .s_axi_awvalid(err_sel && g_awvalid),
      .s_axi_awready(e_awready),
      .s_axi_wdata(g_wdata),
      .s_axi_wstrb(g_wstrb),
      .s_axi_wvalid(err_sel && g_wvalid),
      .s_axi_wready(e_wready),
      .s_axi_bresp(e_bresp),
      .s_axi_bvalid(e_bvalid),
      .s_axi_bready(err_sel && g_bready),
      .s_axi_araddr(g_araddr),
      .s_axi_arvalid(err_sel && g_arvalid),
      .s_axi_arready(e_arready),
      .s_axi_rdata(e_rdata),
      .s_axi_rresp(e_rresp),
      .s_axi_rvalid(e_rvalid),
      .s_axi_rready(err_sel && g_rready)
  );

  /* Exactly one responder answers a transaction: either a selected slave or, when no region owns
     the address, the decode error responder. */
  always_comb begin
    r_awready = err_sel && e_awready;
    r_wready = err_sel && e_wready;
    r_bvalid = err_sel && e_bvalid;
    r_bresp = e_bresp;
    r_arready = err_sel && e_arready;
    r_rvalid = err_sel && e_rvalid;
    r_rdata = e_rdata;
    r_rresp = e_rresp;
    for (int s = 0; s < NUM_SLAVES; s++) begin
      if (sel[s]) begin
        r_awready = m_axi_awready[s];
        r_wready = m_axi_wready[s];
        r_bvalid = m_axi_bvalid[s];
        r_bresp = m_axi_bresp[s];
        r_arready = m_axi_arready[s];
        r_rvalid = m_axi_rvalid[s];
        r_rdata = m_axi_rdata[s];
        r_rresp = m_axi_rresp[s];
      end
    end
  end

  for (genvar m = 0; m < NUM_MASTERS; m++) begin : gen_mst_rsp
    assign s_axi_awready[m] = grant[m] && r_awready;
    assign s_axi_wready[m] = grant[m] && r_wready;
    assign s_axi_bvalid[m] = grant[m] && r_bvalid;
    assign s_axi_bresp[m] = r_bresp;
    assign s_axi_arready[m] = grant[m] && r_arready;
    assign s_axi_rvalid[m] = grant[m] && r_rvalid;
    assign s_axi_rdata[m] = r_rdata;
    assign s_axi_rresp[m] = r_rresp;
  end

endmodule
