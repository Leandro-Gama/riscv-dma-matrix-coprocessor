/* Master front end wired straight into the slave front end, with a small memory behind the slave
   request. It proves the pair agrees on the five channels before either one is used by the
   interconnect, the data memory or the accelerator adapter. The settable answer delay covers a
   slave that is slower than one cycle. */
module tb_axil_port_loop
  import soc_pkg::*;
();

  localparam int MEM_WORDS = 16;
  localparam int MEM_BYTES = MEM_WORDS * AXIL_STRB_WIDTH;

  logic clk, rst_n;

  logic [AXIL_ADDR_WIDTH-1:0] awaddr, araddr;
  logic [AXIL_DATA_WIDTH-1:0] axi_wdata, axi_rdata;
  logic [AXIL_STRB_WIDTH-1:0] axi_wstrb;
  logic awvalid, awready, wvalid, wready, bvalid, bready;
  logic arvalid, arready, rvalid, rready;
  logic [1:0] bresp, rresp;

  logic s_req, s_we, s_ack, s_err;
  logic [AXIL_ADDR_WIDTH-1:0] s_addr;
  logic [AXIL_STRB_WIDTH-1:0] s_be;
  logic [AXIL_DATA_WIDTH-1:0] s_wdata, s_rdata;

  logic [AXIL_DATA_WIDTH-1:0] mem[MEM_WORDS];
  int unsigned slave_latency;
  int unsigned lat_q;
  int unsigned n_ok, n_err;

  initial clk = 1'b0;
  always #5ns clk = ~clk;

  axil_master_drv u_drv (
      .clk_i(clk),
      .rst_ni(rst_n),
      .m_axi_awaddr(awaddr),
      .m_axi_awvalid(awvalid),
      .m_axi_awready(awready),
      .m_axi_wdata(axi_wdata),
      .m_axi_wstrb(axi_wstrb),
      .m_axi_wvalid(wvalid),
      .m_axi_wready(wready),
      .m_axi_bresp(bresp),
      .m_axi_bvalid(bvalid),
      .m_axi_bready(bready),
      .m_axi_araddr(araddr),
      .m_axi_arvalid(arvalid),
      .m_axi_arready(arready),
      .m_axi_rdata(axi_rdata),
      .m_axi_rresp(rresp),
      .m_axi_rvalid(rvalid),
      .m_axi_rready(rready)
  );

  /* The master drives one address channel at a time, so both of its address outputs carry the
     same value and either one can feed the slave. */
  axil_slave_port u_slv (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(awaddr),
      .s_axi_awvalid(awvalid),
      .s_axi_awready(awready),
      .s_axi_wdata(axi_wdata),
      .s_axi_wstrb(axi_wstrb),
      .s_axi_wvalid(wvalid),
      .s_axi_wready(wready),
      .s_axi_bresp(bresp),
      .s_axi_bvalid(bvalid),
      .s_axi_bready(bready),
      .s_axi_araddr(araddr),
      .s_axi_arvalid(arvalid),
      .s_axi_arready(arready),
      .s_axi_rdata(axi_rdata),
      .s_axi_rresp(rresp),
      .s_axi_rvalid(rvalid),
      .s_axi_rready(rready),
      .req_o(s_req),
      .we_o(s_we),
      .addr_o(s_addr),
      .be_o(s_be),
      .wdata_o(s_wdata),
      .ack_i(s_ack),
      .rdata_i(s_rdata),
      .err_i(s_err)
  );

  // Memory behind the slave request, with a settable number of cycles before it answers.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_ack <= 1'b0;
      s_err <= 1'b0;
      s_rdata <= '0;
      lat_q <= 0;
    end else begin
      s_ack <= 1'b0;
      if (s_req && !s_ack) begin
        if ((lat_q + 1) >= slave_latency) begin
          lat_q <= 0;
          s_ack <= 1'b1;
          if (s_addr >= MEM_BYTES) begin
            s_err <= 1'b1;
            s_rdata <= '0;
          end else begin
            s_err <= 1'b0;
            s_rdata <= mem[s_addr[5:2]];
            if (s_we) begin
              for (int b = 0; b < AXIL_STRB_WIDTH; b++) begin
                if (s_be[b]) mem[s_addr[5:2]][8*b+:8] <= s_wdata[8*b+:8];
              end
            end
          end
        end else begin
          lat_q <= lat_q + 1;
        end
      end else begin
        lat_q <= 0;
      end
    end
  end

  task automatic check(input string name, input logic cond);
    if (cond) begin
      n_ok = n_ok + 1;
      $display("OK   %s", name);
    end else begin
      n_err = n_err + 1;
      $display("ERRO %s", name);
    end
  endtask

  initial begin
    n_ok = 0;
    n_err = 0;
    slave_latency = 1;
    foreach (mem[i]) mem[i] = '0;

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    u_drv.write(32'h0000_0004, 32'hDEAD_BEEF, 4'hF);
    check("escrita de palavra responde OKAY", u_drv.last_resp == RESP_OKAY);
    u_drv.read(32'h0000_0004);
    check("leitura devolve a palavra escrita", u_drv.last_rdata == 32'hDEAD_BEEF);
    check("leitura responde OKAY", u_drv.last_resp == RESP_OKAY);

    u_drv.write(32'h0000_0004, 32'h0000_AA00, 4'b0010);
    u_drv.read(32'h0000_0004);
    check("byte enable troca so a faixa pedida", u_drv.last_rdata == 32'hDEAD_AAEF);

    u_drv.read(32'h0000_0008);
    check("palavra nao escrita le zero", u_drv.last_rdata == 32'h0000_0000);

    u_drv.write(32'h0000_0100, 32'h1234_5678, 4'hF);
    check("escrita fora da faixa responde SLVERR", u_drv.last_resp == RESP_SLVERR);
    u_drv.read(32'h0000_0100);
    check("leitura fora da faixa responde SLVERR", u_drv.last_resp == RESP_SLVERR);

    u_drv.read(32'h0000_0004);
    check("escrita recusada nao alterou a memoria", u_drv.last_rdata == 32'hDEAD_AAEF);

    slave_latency = 4;
    u_drv.write(32'h0000_000C, 32'hCAFE_0001, 4'hF);
    check("escrita com escravo lento responde OKAY", u_drv.last_resp == RESP_OKAY);
    u_drv.read(32'h0000_000C);
    check("leitura com escravo lento devolve o dado", u_drv.last_rdata == 32'hCAFE_0001);

    slave_latency = 1;
    for (int i = 0; i < MEM_WORDS; i++) begin
      u_drv.write(i * 4, 32'h0100_0000 + i, 4'hF);
    end
    for (int i = 0; i < MEM_WORDS; i++) begin
      u_drv.read(i * 4);
      check($sformatf("varredura devolve a palavra %0d", i),
            u_drv.last_rdata == (32'h0100_0000 + i));
    end

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

  // A transaction that never answers would otherwise hang the regression.
  initial begin
    #200us;
    $display("RESUMO: %0d OK, %0d ERRO (timeout)", n_ok, n_err + 1);
    $fatal(1, "timeout");
  end

endmodule
