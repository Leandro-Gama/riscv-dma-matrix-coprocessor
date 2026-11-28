/* The link of the accelerator as the subsystem builds it: the local decoder sends CTRL/STATUS to
   the adapter and the buffers to the AXI4-Lite port of the accelerator. Checked here: which
   accesses of the region are refused, that commands and byte writes reach the accelerator, that
   the decoder adds no cycle (against a second accelerator wired straight to a driver), and that
   STATUS no longer shows the DONE of the previous command right after a new one. */
module tb_accel_link
  import soc_pkg::*;
();

  localparam int N = 4;
  localparam int DW = 8;
  localparam int BUF_BYTES = N * N * DW / 8;
  localparam logic [31:0] CTRL = ACCEL_BASE + ACCEL_OFF_CTRL;
  localparam logic [31:0] STATUS = ACCEL_BASE + ACCEL_OFF_STATUS;
  localparam logic [31:0] DIN = ACCEL_BASE + ACCEL_OFF_DATA_IN;
  localparam logic [31:0] DOUT = ACCEL_BASE + ACCEL_OFF_DATA_OUT;
  localparam int CSR_BYTES = int'(ACCEL_OFF_DATA_IN);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  int unsigned n_ok, n_err;

  // Driver side of the link under test.
  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [3:0] m_wstrb;
  logic [1:0] m_bresp, m_rresp;
  logic m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic m_arvalid, m_arready, m_rvalid, m_rready;

  logic [1:0][31:0] d_awaddr, d_wdata, d_araddr, d_rdata;
  logic [1:0][2:0] d_awprot, d_arprot;
  logic [1:0][3:0] d_wstrb;
  logic [1:0][1:0] d_bresp, d_rresp;
  logic [1:0] d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  logic [1:0] d_arvalid, d_arready, d_rvalid, d_rready;

  logic acc_mode, acc_load, acc_start, acc_clr, shell_req;
  wire [31:0] acc_status;

  axil_master_drv u_drv (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .m_axi_awaddr (m_awaddr),
      .m_axi_awvalid(m_awvalid),
      .m_axi_awready(m_awready),
      .m_axi_wdata  (m_wdata),
      .m_axi_wstrb  (m_wstrb),
      .m_axi_wvalid (m_wvalid),
      .m_axi_wready (m_wready),
      .m_axi_bresp  (m_bresp),
      .m_axi_bvalid (m_bvalid),
      .m_axi_bready (m_bready),
      .m_axi_araddr (m_araddr),
      .m_axi_arvalid(m_arvalid),
      .m_axi_arready(m_arready),
      .m_axi_rdata  (m_rdata),
      .m_axi_rresp  (m_rresp),
      .m_axi_rvalid (m_rvalid),
      .m_axi_rready (m_rready)
  );

  soc_axil_decoder #(
      .NUM_SLAVES(2),
      .SLAVE_BASE({DIN, ACCEL_BASE}),
      .SLAVE_SIZE({32'(ACCEL_BYTES - CSR_BYTES), 32'(CSR_BYTES)})
  ) u_dec (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .s_axi_awaddr (m_awaddr),
      .s_axi_awprot (3'b000),
      .s_axi_awvalid(m_awvalid),
      .s_axi_awready(m_awready),
      .s_axi_wdata  (m_wdata),
      .s_axi_wstrb  (m_wstrb),
      .s_axi_wvalid (m_wvalid),
      .s_axi_wready (m_wready),
      .s_axi_bresp  (m_bresp),
      .s_axi_bvalid (m_bvalid),
      .s_axi_bready (m_bready),
      .s_axi_araddr (m_araddr),
      .s_axi_arprot (3'b000),
      .s_axi_arvalid(m_arvalid),
      .s_axi_arready(m_arready),
      .s_axi_rdata  (m_rdata),
      .s_axi_rresp  (m_rresp),
      .s_axi_rvalid (m_rvalid),
      .s_axi_rready (m_rready),
      .m_axi_awaddr (d_awaddr),
      .m_axi_awprot (d_awprot),
      .m_axi_awvalid(d_awvalid),
      .m_axi_awready(d_awready),
      .m_axi_wdata  (d_wdata),
      .m_axi_wstrb  (d_wstrb),
      .m_axi_wvalid (d_wvalid),
      .m_axi_wready (d_wready),
      .m_axi_bresp  (d_bresp),
      .m_axi_bvalid (d_bvalid),
      .m_axi_bready (d_bready),
      .m_axi_araddr (d_araddr),
      .m_axi_arprot (d_arprot),
      .m_axi_arvalid(d_arvalid),
      .m_axi_arready(d_arready),
      .m_axi_rdata  (d_rdata),
      .m_axi_rresp  (d_rresp),
      .m_axi_rvalid (d_rvalid),
      .m_axi_rready (d_rready)
  );

  accel_adapter #(
      .BASE_ADDR(ACCEL_BASE),
      .ARRAY_SIZE(N),
      .DATA_WIDTH(DW),
      .RESULT_WIDTH(DW)
  ) u_adapter (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .s_axi_awaddr (d_awaddr[0]),
      .s_axi_awvalid(d_awvalid[0]),
      .s_axi_awready(d_awready[0]),
      .s_axi_wdata  (d_wdata[0]),
      .s_axi_wstrb  (d_wstrb[0]),
      .s_axi_wvalid (d_wvalid[0]),
      .s_axi_wready (d_wready[0]),
      .s_axi_bresp  (d_bresp[0]),
      .s_axi_bvalid (d_bvalid[0]),
      .s_axi_bready (d_bready[0]),
      .s_axi_araddr (d_araddr[0]),
      .s_axi_arvalid(d_arvalid[0]),
      .s_axi_arready(d_arready[0]),
      .s_axi_rdata  (d_rdata[0]),
      .s_axi_rresp  (d_rresp[0]),
      .s_axi_rvalid (d_rvalid[0]),
      .s_axi_rready (d_rready[0]),
      .mode_o       (acc_mode),
      .load_o       (acc_load),
      .start_o      (acc_start),
      .clr_error_o  (acc_clr),
      .status_i     (acc_status),
      .data_req_o   (shell_req),
      .data_we_o    (),
      .data_addr_o  (),
      .data_wdata_o (),
      .data_rdata_i ('0),
      .data_ready_i (shell_req),
      .data_error_i (1'b1)
  );

  axil_if acc_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  assign acc_bus.awaddr = d_awaddr[1];
  assign acc_bus.awprot = d_awprot[1];
  assign acc_bus.awvalid = d_awvalid[1];
  assign acc_bus.wdata = d_wdata[1];
  assign acc_bus.wstrb = d_wstrb[1];
  assign acc_bus.wvalid = d_wvalid[1];
  assign acc_bus.bready = d_bready[1];
  assign acc_bus.araddr = d_araddr[1];
  assign acc_bus.arprot = d_arprot[1];
  assign acc_bus.arvalid = d_arvalid[1];
  assign acc_bus.rready = d_rready[1];
  assign d_awready[1] = acc_bus.awready;
  assign d_wready[1] = acc_bus.wready;
  assign d_bresp[1] = acc_bus.bresp;
  assign d_bvalid[1] = acc_bus.bvalid;
  assign d_arready[1] = acc_bus.arready;
  assign d_rdata[1] = acc_bus.rdata;
  assign d_rresp[1] = acc_bus.rresp;
  assign d_rvalid[1] = acc_bus.rvalid;

  accel_top #(
      .N(N),
      .DATA_WIDTH(DW),
      .DATA_IN_BASE(DIN),
      .DATA_OUT_BASE(DOUT)
  ) u_accel (
      .clk_i      (clk),
      .rst_ni     (rst_n),
      .mode_i     (acc_mode),
      .load_i     (acc_load),
      .start_i    (acc_start),
      .clr_error_i(acc_clr),
      .status_o   (acc_status),
      .s_axi      (acc_bus)
  );

  // Reference: a second accelerator wired straight to a driver, to count cycles against.
  logic [31:0] r_awaddr, r_wdata, r_araddr;
  logic [3:0] r_wstrb;
  logic r_awvalid, r_wvalid, r_bready, r_arvalid, r_rready;
  wire [31:0] ref_status;
  axil_if ref_bus (
      .clk  (clk),
      .rst_n(rst_n)
  );

  axil_master_drv u_ref_drv (
      .clk_i        (clk),
      .rst_ni       (rst_n),
      .m_axi_awaddr (r_awaddr),
      .m_axi_awvalid(r_awvalid),
      .m_axi_awready(ref_bus.awready),
      .m_axi_wdata  (r_wdata),
      .m_axi_wstrb  (r_wstrb),
      .m_axi_wvalid (r_wvalid),
      .m_axi_wready (ref_bus.wready),
      .m_axi_bresp  (ref_bus.bresp),
      .m_axi_bvalid (ref_bus.bvalid),
      .m_axi_bready (r_bready),
      .m_axi_araddr (r_araddr),
      .m_axi_arvalid(r_arvalid),
      .m_axi_arready(ref_bus.arready),
      .m_axi_rdata  (ref_bus.rdata),
      .m_axi_rresp  (ref_bus.rresp),
      .m_axi_rvalid (ref_bus.rvalid),
      .m_axi_rready (r_rready)
  );

  assign ref_bus.awaddr = r_awaddr;
  assign ref_bus.awprot = 3'b000;
  assign ref_bus.awvalid = r_awvalid;
  assign ref_bus.wdata = r_wdata;
  assign ref_bus.wstrb = r_wstrb;
  assign ref_bus.wvalid = r_wvalid;
  assign ref_bus.bready = r_bready;
  assign ref_bus.araddr = r_araddr;
  assign ref_bus.arprot = 3'b000;
  assign ref_bus.arvalid = r_arvalid;
  assign ref_bus.rready = r_rready;

  accel_top #(
      .N(N),
      .DATA_WIDTH(DW),
      .DATA_IN_BASE(DIN),
      .DATA_OUT_BASE(DOUT)
  ) u_accel_ref (
      .clk_i      (clk),
      .rst_ni     (rst_n),
      .mode_i     (1'b0),
      .load_i     (1'b0),
      .start_i    (1'b0),
      .clr_error_i(1'b0),
      .status_o   (ref_status),
      .s_axi      (ref_bus)
  );

  task automatic check(input string name, input logic cond);
    if (cond) begin
      n_ok++;
    end else begin
      n_err++;
      $display("ERRO %s", name);
    end
  endtask

  task automatic expect_write(input string name, input logic [31:0] addr, input logic [31:0] data,
                              input logic [3:0] strb, input logic [1:0] resp);
    u_drv.write(addr, data, strb);
    check($sformatf("%s: resposta %0d, esperada %0d", name, u_drv.last_resp, resp),
          u_drv.last_resp == resp);
  endtask

  task automatic expect_read(input string name, input logic [31:0] addr, input logic [1:0] resp);
    u_drv.read(addr);
    check($sformatf("%s: resposta %0d, esperada %0d", name, u_drv.last_resp, resp),
          u_drv.last_resp == resp);
  endtask

  // Cycles from the request to the answer, for one access through the link and one straight.
  task automatic cycles_of(input bit write, input logic [31:0] addr, output int link,
                           output int direct);
    longint t0;
    t0 = $time;
    if (write) u_drv.write(addr, 32'h0102_0304, 4'hF);
    else u_drv.read(addr);
    link = int'(($time - t0) / 10);
    t0 = $time;
    if (write) u_ref_drv.write(addr, 32'h0102_0304, 4'hF);
    else u_ref_drv.read(addr);
    direct = int'(($time - t0) / 10);
  endtask

  task automatic wait_done(input string name);
    int unsigned waited = 0;
    do begin
      u_drv.read(STATUS);
      waited++;
    end while (!u_drv.last_rdata[ACCEL_STATUS_DONE_BIT] && waited < 200);
    check({name, " termina com DONE"}, u_drv.last_rdata[ACCEL_STATUS_DONE_BIT]);
  endtask

  initial begin
    int link, direct, write_cycles;
    logic seen_load;

    n_ok = 0;
    n_err = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // The whole region: only writes into DATA_IN and reads from DATA_OUT, inside the buffers.
    expect_write("escrita em DATA_IN", DIN, 32'h1111_1111, 4'hF, RESP_OKAY);
    expect_read("leitura de DATA_IN", DIN, RESP_SLVERR);
    expect_read("leitura de DATA_OUT", DOUT, RESP_OKAY);
    expect_write("escrita em DATA_OUT", DOUT, 32'h0, 4'hF, RESP_SLVERR);
    expect_write("escrita depois do fim de DATA_IN", DIN + BUF_BYTES, 32'h0, 4'hF, RESP_SLVERR);
    expect_read("leitura depois do fim de DATA_OUT", DOUT + BUF_BYTES, RESP_SLVERR);
    expect_write("escrita desalinhada em DATA_IN", DIN + 1, 32'h0, 4'hF, RESP_SLVERR);
    expect_read("registrador inexistente na janela de controle", ACCEL_BASE + 8, RESP_SLVERR);
    expect_write("escrita em STATUS", STATUS, 32'h0, 4'hF, RESP_SLVERR);
    expect_read("endereco entre os buffers e o fim da regiao", ACCEL_BASE + 32'h3000,
                RESP_SLVERR);
    expect_read("ultima palavra da regiao", ACCEL_BASE + ACCEL_BYTES - 4, RESP_SLVERR);

    // Commands reach the accelerator, STATUS comes from it, byte writes keep the other bytes.
    expect_write("DATA_IN palavra 0", DIN, 32'h4433_2211, 4'hF, RESP_OKAY);
    expect_write("DATA_IN so o byte 1", DIN, 32'h0000_AA00, 4'b0010, RESP_OKAY);
    check("escrita por byte preservada no buffer", u_accel.input_q[0] == 32'h4433_AA11);
    seen_load = 1'b0;
    fork
      begin
        repeat (20) begin
          @(posedge clk);
          if (acc_load) seen_load = 1'b1;
        end
      end
      expect_write("LOAD pelo CTRL", CTRL, 32'h0000_0002, 4'hF, RESP_OKAY);
    join
    check("o pulso de LOAD chegou ao acelerador", seen_load);
    wait_done("LOAD");
    u_drv.read(STATUS);
    check("STATUS lido e o do acelerador", u_drv.last_rdata == acc_status);

    // The DONE of the previous command is gone at the first read after a new command. START
    // goes with MODE = 1, as the accelerator requires and the DMA writes it.
    expect_write("START pelo CTRL", CTRL, 32'h0000_0005, 4'hF, RESP_OKAY);
    u_drv.read(STATUS);
    check("logo depois do START, STATUS nao mostra o DONE do LOAD",
          !u_drv.last_rdata[ACCEL_STATUS_DONE_BIT]);
    wait_done("START");
    check("nenhum comando recusado pelo acelerador", !acc_status[ACCEL_STATUS_ERROR_BIT]);
    expect_read("DATA_OUT com o acelerador parado", DOUT, RESP_OKAY);

    // No cycle added by the local decoder.
    cycles_of(1'b1, DIN + 4, link, direct);
    check($sformatf("escrita em DATA_IN: %0d ciclos pelo decodificador, %0d direto", link, direct),
          link == direct);
    write_cycles = link;
    cycles_of(1'b0, DOUT + 4, link, direct);
    check($sformatf("leitura de DATA_OUT: %0d ciclos pelo decodificador, %0d direto", link,
                    direct), link == direct);
    $display("ciclos por acesso a buffer, vistos pelo driver: escrita %0d, leitura %0d",
             write_cycles, link);

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

endmodule
