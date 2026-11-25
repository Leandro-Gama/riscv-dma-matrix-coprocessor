/* The interconnect with real slaves behind it: the data memory, a stand in for the DMA registers
   and a stand in for the accelerator. The accelerator stand in is smaller than its region on
   purpose, so the testbench can tell a slave that refuses an access apart from an address that
   belongs to no slave at all. */
module tb_axil_xbar
  import soc_pkg::*;
();

  localparam int CLK_PERIOD = 10;
  localparam int DMEM_BYTES = DMEM_BYTES_DEFAULT;
  localparam int ACCEL_MODEL_BYTES = 16 * 1024;
  localparam logic [AXIL_ADDR_WIDTH-1:0] NO_REGION = 32'h3000_0000;

  logic clk, rst_n;
  int n_ok, n_err;

  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] m_awaddr;
  logic [NUM_MASTERS-1:0] m_awvalid, m_awready;
  logic [NUM_MASTERS-1:0][AXIL_DATA_WIDTH-1:0] m_wdata;
  logic [NUM_MASTERS-1:0][AXIL_STRB_WIDTH-1:0] m_wstrb;
  logic [NUM_MASTERS-1:0] m_wvalid, m_wready;
  logic [NUM_MASTERS-1:0][1:0] m_bresp;
  logic [NUM_MASTERS-1:0] m_bvalid, m_bready;
  logic [NUM_MASTERS-1:0][AXIL_ADDR_WIDTH-1:0] m_araddr;
  logic [NUM_MASTERS-1:0] m_arvalid, m_arready;
  logic [NUM_MASTERS-1:0][AXIL_DATA_WIDTH-1:0] m_rdata;
  logic [NUM_MASTERS-1:0][1:0] m_rresp;
  logic [NUM_MASTERS-1:0] m_rvalid, m_rready;

  logic [NUM_SLAVES-1:0][AXIL_ADDR_WIDTH-1:0] s_awaddr;
  logic [NUM_SLAVES-1:0] s_awvalid, s_awready;
  logic [NUM_SLAVES-1:0][AXIL_DATA_WIDTH-1:0] s_wdata;
  logic [NUM_SLAVES-1:0][AXIL_STRB_WIDTH-1:0] s_wstrb;
  logic [NUM_SLAVES-1:0] s_wvalid, s_wready;
  logic [NUM_SLAVES-1:0][1:0] s_bresp;
  logic [NUM_SLAVES-1:0] s_bvalid, s_bready;
  logic [NUM_SLAVES-1:0][AXIL_ADDR_WIDTH-1:0] s_araddr;
  logic [NUM_SLAVES-1:0] s_arvalid, s_arready;
  logic [NUM_SLAVES-1:0][AXIL_DATA_WIDTH-1:0] s_rdata;
  logic [NUM_SLAVES-1:0][1:0] s_rresp;
  logic [NUM_SLAVES-1:0] s_rvalid, s_rready;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  for (genvar m = 0; m < NUM_MASTERS; m++) begin : gen_mst
    axil_master_drv u_drv (
        .clk_i(clk),
        .rst_ni(rst_n),
        .m_axi_awaddr(m_awaddr[m]),
        .m_axi_awvalid(m_awvalid[m]),
        .m_axi_awready(m_awready[m]),
        .m_axi_wdata(m_wdata[m]),
        .m_axi_wstrb(m_wstrb[m]),
        .m_axi_wvalid(m_wvalid[m]),
        .m_axi_wready(m_wready[m]),
        .m_axi_bresp(m_bresp[m]),
        .m_axi_bvalid(m_bvalid[m]),
        .m_axi_bready(m_bready[m]),
        .m_axi_araddr(m_araddr[m]),
        .m_axi_arvalid(m_arvalid[m]),
        .m_axi_arready(m_arready[m]),
        .m_axi_rdata(m_rdata[m]),
        .m_axi_rresp(m_rresp[m]),
        .m_axi_rvalid(m_rvalid[m]),
        .m_axi_rready(m_rready[m])
    );
  end

  soc_axil_xbar #(
      .DMEM_BYTES(DMEM_BYTES),
      .ARB_POLICY(ARB_DMA_PRIORITY)
  ) u_xbar (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(m_awaddr),
      .s_axi_awvalid(m_awvalid),
      .s_axi_awready(m_awready),
      .s_axi_wdata(m_wdata),
      .s_axi_wstrb(m_wstrb),
      .s_axi_wvalid(m_wvalid),
      .s_axi_wready(m_wready),
      .s_axi_bresp(m_bresp),
      .s_axi_bvalid(m_bvalid),
      .s_axi_bready(m_bready),
      .s_axi_araddr(m_araddr),
      .s_axi_arvalid(m_arvalid),
      .s_axi_arready(m_arready),
      .s_axi_rdata(m_rdata),
      .s_axi_rresp(m_rresp),
      .s_axi_rvalid(m_rvalid),
      .s_axi_rready(m_rready),
      .m_axi_awaddr(s_awaddr),
      .m_axi_awvalid(s_awvalid),
      .m_axi_awready(s_awready),
      .m_axi_wdata(s_wdata),
      .m_axi_wstrb(s_wstrb),
      .m_axi_wvalid(s_wvalid),
      .m_axi_wready(s_wready),
      .m_axi_bresp(s_bresp),
      .m_axi_bvalid(s_bvalid),
      .m_axi_bready(s_bready),
      .m_axi_araddr(s_araddr),
      .m_axi_arvalid(s_arvalid),
      .m_axi_arready(s_arready),
      .m_axi_rdata(s_rdata),
      .m_axi_rresp(s_rresp),
      .m_axi_rvalid(s_rvalid),
      .m_axi_rready(s_rready)
  );

  mem_data #(
      .BASE_ADDR(DMEM_BASE),
      .DMEM_BYTES(DMEM_BYTES)
  ) u_dmem (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(s_awaddr[SLV_DMEM]),
      .s_axi_awvalid(s_awvalid[SLV_DMEM]),
      .s_axi_awready(s_awready[SLV_DMEM]),
      .s_axi_wdata(s_wdata[SLV_DMEM]),
      .s_axi_wstrb(s_wstrb[SLV_DMEM]),
      .s_axi_wvalid(s_wvalid[SLV_DMEM]),
      .s_axi_wready(s_wready[SLV_DMEM]),
      .s_axi_bresp(s_bresp[SLV_DMEM]),
      .s_axi_bvalid(s_bvalid[SLV_DMEM]),
      .s_axi_bready(s_bready[SLV_DMEM]),
      .s_axi_araddr(s_araddr[SLV_DMEM]),
      .s_axi_arvalid(s_arvalid[SLV_DMEM]),
      .s_axi_arready(s_arready[SLV_DMEM]),
      .s_axi_rdata(s_rdata[SLV_DMEM]),
      .s_axi_rresp(s_rresp[SLV_DMEM]),
      .s_axi_rvalid(s_rvalid[SLV_DMEM]),
      .s_axi_rready(s_rready[SLV_DMEM])
  );

  // Stand in for the DMA registers: enough to prove that the region is reached and kept apart.
  mem_data #(
      .BASE_ADDR(DMAREG_BASE),
      .DMEM_BYTES(DMAREG_BYTES)
  ) u_dmareg (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(s_awaddr[SLV_DMAREG]),
      .s_axi_awvalid(s_awvalid[SLV_DMAREG]),
      .s_axi_awready(s_awready[SLV_DMAREG]),
      .s_axi_wdata(s_wdata[SLV_DMAREG]),
      .s_axi_wstrb(s_wstrb[SLV_DMAREG]),
      .s_axi_wvalid(s_wvalid[SLV_DMAREG]),
      .s_axi_wready(s_wready[SLV_DMAREG]),
      .s_axi_bresp(s_bresp[SLV_DMAREG]),
      .s_axi_bvalid(s_bvalid[SLV_DMAREG]),
      .s_axi_bready(s_bready[SLV_DMAREG]),
      .s_axi_araddr(s_araddr[SLV_DMAREG]),
      .s_axi_arvalid(s_arvalid[SLV_DMAREG]),
      .s_axi_arready(s_arready[SLV_DMAREG]),
      .s_axi_rdata(s_rdata[SLV_DMAREG]),
      .s_axi_rresp(s_rresp[SLV_DMAREG]),
      .s_axi_rvalid(s_rvalid[SLV_DMAREG]),
      .s_axi_rready(s_rready[SLV_DMAREG])
  );

  mem_data #(
      .BASE_ADDR(ACCEL_BASE),
      .DMEM_BYTES(ACCEL_MODEL_BYTES)
  ) u_accel (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(s_awaddr[SLV_ACCEL]),
      .s_axi_awvalid(s_awvalid[SLV_ACCEL]),
      .s_axi_awready(s_awready[SLV_ACCEL]),
      .s_axi_wdata(s_wdata[SLV_ACCEL]),
      .s_axi_wstrb(s_wstrb[SLV_ACCEL]),
      .s_axi_wvalid(s_wvalid[SLV_ACCEL]),
      .s_axi_wready(s_wready[SLV_ACCEL]),
      .s_axi_bresp(s_bresp[SLV_ACCEL]),
      .s_axi_bvalid(s_bvalid[SLV_ACCEL]),
      .s_axi_bready(s_bready[SLV_ACCEL]),
      .s_axi_araddr(s_araddr[SLV_ACCEL]),
      .s_axi_arvalid(s_arvalid[SLV_ACCEL]),
      .s_axi_arready(s_arready[SLV_ACCEL]),
      .s_axi_rdata(s_rdata[SLV_ACCEL]),
      .s_axi_rresp(s_rresp[SLV_ACCEL]),
      .s_axi_rvalid(s_rvalid[SLV_ACCEL]),
      .s_axi_rready(s_rready[SLV_ACCEL])
  );

  task automatic check(input string what, input logic cond);
    if (cond === 1'b1) begin
      n_ok++;
    end else begin
      n_err++;
      $display("ERRO %s", what);
    end
  endtask

  initial begin
    n_ok  = 0;
    n_err = 0;
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    gen_mst[MST_CPU].u_drv.write(DMEM_BASE + 32'h40, 32'hC0DE_0001, 4'hF);
    check("CPU escreve na memoria de dados", gen_mst[MST_CPU].u_drv.last_resp == RESP_OKAY);
    gen_mst[MST_CPU].u_drv.read(DMEM_BASE + 32'h40);
    check("CPU le de volta da memoria de dados",
          gen_mst[MST_CPU].u_drv.last_rdata == 32'hC0DE_0001);

    /* The same offset is written in two regions with different values, so a read of one of them
       cannot pass by accident. */
    gen_mst[MST_CPU].u_drv.write(DMEM_BASE + DMA_REG_DIM_M, 32'h600D_600D, 4'hF);
    gen_mst[MST_CPU].u_drv.write(DMAREG_BASE + DMA_REG_DIM_M, 32'd16, 4'hF);
    check("CPU escreve nos registradores do DMA", gen_mst[MST_CPU].u_drv.last_resp == RESP_OKAY);
    gen_mst[MST_CPU].u_drv.read(DMAREG_BASE + DMA_REG_DIM_M);
    check("CPU le de volta dos registradores do DMA",
          gen_mst[MST_CPU].u_drv.last_rdata == 32'd16);

    gen_mst[MST_DMA].u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN, 32'hABCD_1234, 4'hF);
    check("DMA escreve no acelerador", gen_mst[MST_DMA].u_drv.last_resp == RESP_OKAY);
    gen_mst[MST_DMA].u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_IN);
    check("DMA le de volta do acelerador",
          gen_mst[MST_DMA].u_drv.last_rdata == 32'hABCD_1234);

    gen_mst[MST_CPU].u_drv.read(DMEM_BASE + DMA_REG_DIM_M);
    check("as regioes nao se misturam", gen_mst[MST_CPU].u_drv.last_rdata == 32'h600D_600D);

    // The instruction memory is not on the bus, so a data access to it has no owner.
    gen_mst[MST_CPU].u_drv.write(IMEM_BASE, 32'hDEAD_BEEF, 4'hF);
    check("escrever na memoria de instrucoes pelo barramento da erro de decodificacao",
          gen_mst[MST_CPU].u_drv.last_resp == RESP_DECERR);
    gen_mst[MST_CPU].u_drv.read(IMEM_BASE + 32'h10);
    check("ler a memoria de instrucoes pelo barramento da erro de decodificacao",
          gen_mst[MST_CPU].u_drv.last_resp == RESP_DECERR);

    gen_mst[MST_CPU].u_drv.read(NO_REGION);
    check("endereco sem regiao nenhuma da erro de decodificacao",
          gen_mst[MST_CPU].u_drv.last_resp == RESP_DECERR);
    gen_mst[MST_DMA].u_drv.write(NO_REGION, 32'h1111_2222, 4'hF);
    check("o DMA tambem recebe erro de decodificacao",
          gen_mst[MST_DMA].u_drv.last_resp == RESP_DECERR);

    gen_mst[MST_CPU].u_drv.read(DMEM_BASE + DMEM_BYTES);
    check("um byte depois do fim da memoria de dados nao pertence a regiao",
          gen_mst[MST_CPU].u_drv.last_resp == RESP_DECERR);

    /* Inside the region but past what the block implements: the slave itself refuses, and that
       is a different answer from an address that no slave owns. */
    gen_mst[MST_DMA].u_drv.read(ACCEL_BASE + ACCEL_MODEL_BYTES);
    check("dentro da regiao do acelerador mas fora do bloco da erro do escravo",
          gen_mst[MST_DMA].u_drv.last_resp == RESP_SLVERR);

    gen_mst[MST_CPU].u_drv.read(DMEM_BASE + 32'h40);
    check("depois dos erros o barramento continua servindo",
          gen_mst[MST_CPU].u_drv.last_rdata == 32'hC0DE_0001);

    gen_mst[MST_CPU].u_drv.write(DMEM_BASE + 32'h80, 32'h0000_0000, 4'hF);
    gen_mst[MST_CPU].u_drv.write(DMEM_BASE + 32'h80, 32'hFFFF_FFFF, 4'b0010);
    gen_mst[MST_CPU].u_drv.read(DMEM_BASE + 32'h80);
    check("escrita por byte atravessa o barramento",
          gen_mst[MST_CPU].u_drv.last_rdata == 32'h0000_FF00);

    /* Both masters hammering at once, each on its own region: this is where arbitration, the
       held grant and the response routing are really exercised. */
    fork
      begin
        for (int i = 0; i < 48; i++) begin
          gen_mst[MST_CPU].u_drv.write(DMEM_BASE + 32'h1000 + i * 4, 32'h5A00_0000 + i, 4'hF);
        end
      end
      begin
        for (int i = 0; i < 48; i++) begin
          gen_mst[MST_DMA].u_drv.write(ACCEL_BASE + 32'h100 + i * 4, 32'hA500_0000 + i, 4'hF);
        end
      end
    join

    fork
      begin
        for (int i = 0; i < 48; i++) begin
          gen_mst[MST_CPU].u_drv.read(DMEM_BASE + 32'h1000 + i * 4);
          check($sformatf("a CPU le a palavra %0d que escreveu durante a disputa", i),
                gen_mst[MST_CPU].u_drv.last_rdata == (32'h5A00_0000 + i));
        end
      end
      begin
        for (int i = 0; i < 48; i++) begin
          gen_mst[MST_DMA].u_drv.read(ACCEL_BASE + 32'h100 + i * 4);
          check($sformatf("o DMA le a palavra %0d que escreveu durante a disputa", i),
                gen_mst[MST_DMA].u_drv.last_rdata == (32'hA500_0000 + i));
        end
      end
    join

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

  /* Deliberate protocol break, used to show that the bound checker really is watching: run with
     BUG=ADDR and the run is expected to fail. */
  string bug;

  initial begin
    if ($value$plusargs("BUG=%s", bug) && bug == "ADDR") begin
      wait (gen_mst[MST_CPU].u_drv.u_port.m_axi_awvalid === 1'b1);
      $display("BUG injetado: endereco de escrita indefinido com a oferta no ar");
      force gen_mst[MST_CPU].u_drv.u_port.m_axi_awaddr = 'x;
      // The break has to survive one sampling edge, which is where the checker looks.
      @(posedge clk);
      @(negedge clk);
      release gen_mst[MST_CPU].u_drv.u_port.m_axi_awaddr;
    end
  end

  initial begin
    #(20000 * CLK_PERIOD);
    $fatal(1, "tb_axil_xbar nao terminou no tempo previsto");
  end

endmodule
