/* Shared data memory against the interface contract: byte lanes, the default matrix regions, the
   last word that fits and the first one that does not. A second shallow instance covers the
   parameter used for synthesis, where an access past the end of that instance must be reported
   instead of wrapping onto the start. */
module tb_mem_data
  import soc_pkg::*;
();

  localparam int SMALL_BYTES = 256;

  logic clk, rst_n;
  int unsigned n_ok, n_err;

  logic [AXIL_ADDR_WIDTH-1:0] aw0, ar0, aw1, ar1;
  logic [AXIL_DATA_WIDTH-1:0] wd0, rd0, wd1, rd1;
  logic [AXIL_STRB_WIDTH-1:0] ws0, ws1;
  logic awv0, awr0, wv0, wr0, bv0, br0, arv0, arr0, rv0, rr0;
  logic awv1, awr1, wv1, wr1, bv1, br1, arv1, arr1, rv1, rr1;
  logic [1:0] bre0, rre0, bre1, rre1;

  initial clk = 1'b0;
  always #5ns clk = ~clk;

  axil_master_drv u_drv_full (
      .clk_i(clk), .rst_ni(rst_n),
      .m_axi_awaddr(aw0), .m_axi_awvalid(awv0), .m_axi_awready(awr0),
      .m_axi_wdata(wd0), .m_axi_wstrb(ws0), .m_axi_wvalid(wv0), .m_axi_wready(wr0),
      .m_axi_bresp(bre0), .m_axi_bvalid(bv0), .m_axi_bready(br0),
      .m_axi_araddr(ar0), .m_axi_arvalid(arv0), .m_axi_arready(arr0),
      .m_axi_rdata(rd0), .m_axi_rresp(rre0), .m_axi_rvalid(rv0), .m_axi_rready(rr0)
  );

  mem_data u_dmem (
      .clk_i(clk), .rst_ni(rst_n),
      .s_axi_awaddr(aw0), .s_axi_awvalid(awv0), .s_axi_awready(awr0),
      .s_axi_wdata(wd0), .s_axi_wstrb(ws0), .s_axi_wvalid(wv0), .s_axi_wready(wr0),
      .s_axi_bresp(bre0), .s_axi_bvalid(bv0), .s_axi_bready(br0),
      .s_axi_araddr(ar0), .s_axi_arvalid(arv0), .s_axi_arready(arr0),
      .s_axi_rdata(rd0), .s_axi_rresp(rre0), .s_axi_rvalid(rv0), .s_axi_rready(rr0)
  );

  axil_master_drv u_drv_small (
      .clk_i(clk), .rst_ni(rst_n),
      .m_axi_awaddr(aw1), .m_axi_awvalid(awv1), .m_axi_awready(awr1),
      .m_axi_wdata(wd1), .m_axi_wstrb(ws1), .m_axi_wvalid(wv1), .m_axi_wready(wr1),
      .m_axi_bresp(bre1), .m_axi_bvalid(bv1), .m_axi_bready(br1),
      .m_axi_araddr(ar1), .m_axi_arvalid(arv1), .m_axi_arready(arr1),
      .m_axi_rdata(rd1), .m_axi_rresp(rre1), .m_axi_rvalid(rv1), .m_axi_rready(rr1)
  );

  mem_data #(
      .DMEM_BYTES(SMALL_BYTES)
  ) u_dmem_small (
      .clk_i(clk), .rst_ni(rst_n),
      .s_axi_awaddr(aw1), .s_axi_awvalid(awv1), .s_axi_awready(awr1),
      .s_axi_wdata(wd1), .s_axi_wstrb(ws1), .s_axi_wvalid(wv1), .s_axi_wready(wr1),
      .s_axi_bresp(bre1), .s_axi_bvalid(bv1), .s_axi_bready(br1),
      .s_axi_araddr(ar1), .s_axi_arvalid(arv1), .s_axi_arready(arr1),
      .s_axi_rdata(rd1), .s_axi_rresp(rre1), .s_axi_rvalid(rv1), .s_axi_rready(rr1)
  );

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

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    u_drv_full.write(DMEM_BASE, 32'h1122_3344, 4'hF);
    check("escrita na base responde OKAY", u_drv_full.last_resp == RESP_OKAY);
    u_drv_full.read(DMEM_BASE);
    check("leitura na base devolve o dado", u_drv_full.last_rdata == 32'h1122_3344);

    u_drv_full.write(DMEM_BASE + 1, 32'h0000_FF00, 4'b0010);
    u_drv_full.read(DMEM_BASE);
    check("escrita de byte muda so a lane 1", u_drv_full.last_rdata == 32'h1122_FF44);

    u_drv_full.write(DMEM_BASE + 2, 32'hBEEF_0000, 4'b1100);
    u_drv_full.read(DMEM_BASE);
    check("escrita de meia palavra muda as lanes 2 e 3", u_drv_full.last_rdata == 32'hBEEF_FF44);

    // The default matrix regions of the memory map must be reachable.
    u_drv_full.write(DMEM_BASE + 32'h1000, 32'h0000_00A0, 4'hF);
    u_drv_full.write(DMEM_BASE + 32'h2000, 32'h0000_00B0, 4'hF);
    u_drv_full.write(DMEM_BASE + 32'h3000, 32'h0000_00C0, 4'hF);
    u_drv_full.read(DMEM_BASE + 32'h1000);
    check("regiao da matriz A responde", u_drv_full.last_rdata == 32'h0000_00A0);
    u_drv_full.read(DMEM_BASE + 32'h2000);
    check("regiao da matriz B responde", u_drv_full.last_rdata == 32'h0000_00B0);
    u_drv_full.read(DMEM_BASE + 32'h3000);
    check("regiao da matriz C responde", u_drv_full.last_rdata == 32'h0000_00C0);

    u_drv_full.write(DMEM_BASE + DMEM_BYTES_DEFAULT - 4, 32'h0FF0_0FF0, 4'hF);
    check("escrita na ultima palavra da faixa responde OKAY",
          u_drv_full.last_resp == RESP_OKAY);
    u_drv_full.read(DMEM_BASE + DMEM_BYTES_DEFAULT - 4);
    check("ultima palavra da faixa devolve o dado", u_drv_full.last_rdata == 32'h0FF0_0FF0);

    u_drv_full.write(DMEM_BASE + DMEM_BYTES_DEFAULT, 32'hDEAD_DEAD, 4'hF);
    check("escrita um byte apos o fim responde SLVERR", u_drv_full.last_resp == RESP_SLVERR);
    u_drv_full.read(DMEM_BASE + DMEM_BYTES_DEFAULT);
    check("leitura um byte apos o fim responde SLVERR", u_drv_full.last_resp == RESP_SLVERR);

    u_drv_full.read(DMEM_BASE);
    check("acesso recusado nao mexeu na base", u_drv_full.last_rdata == 32'hBEEF_FF44);

    for (int i = 0; i < 32; i++) begin
      u_drv_full.write(DMEM_BASE + 32'h0800 + i * 4, 32'h0770_0000 + i, 4'hF);
    end
    for (int i = 0; i < 32; i++) begin
      u_drv_full.read(DMEM_BASE + 32'h0800 + i * 4);
      check($sformatf("varredura devolve a palavra %0d", i),
            u_drv_full.last_rdata == (32'h0770_0000 + i));
    end

    // Shallow instance: the end of the array, not the end of the region, decides.
    u_drv_small.write(DMEM_BASE + SMALL_BYTES - 4, 32'h5555_AAAA, 4'hF);
    check("instancia rasa aceita a ultima palavra dela",
          u_drv_small.last_resp == RESP_OKAY);
    u_drv_small.read(DMEM_BASE + SMALL_BYTES - 4);
    check("instancia rasa devolve a ultima palavra dela",
          u_drv_small.last_rdata == 32'h5555_AAAA);
    u_drv_small.write(DMEM_BASE, 32'h1234_5678, 4'hF);
    u_drv_small.write(DMEM_BASE + SMALL_BYTES, 32'h9999_9999, 4'hF);
    check("instancia rasa recusa um byte apos o fim dela",
          u_drv_small.last_resp == RESP_SLVERR);
    u_drv_small.read(DMEM_BASE);
    check("acesso recusado na instancia rasa nao deu a volta",
          u_drv_small.last_rdata == 32'h1234_5678);

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

  initial begin
    #2ms;
    $display("RESUMO: %0d OK, %0d ERRO (timeout)", n_ok, n_err + 1);
    $fatal(1, "timeout");
  end

endmodule
