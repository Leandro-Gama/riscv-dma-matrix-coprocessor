/* The accelerator adapter against the interface contract: the command pulses and the mode that
   goes with them, the mirrored status, the two buffers with their allowed direction, and every
   refusal. The accelerator shell is a model here, with a settable answer time, so the adapter is
   also checked against a shell that takes its time.
   With ARRAY_SIZE 4 and 8 bit elements the input buffer is 16 bytes and the output buffer, which
   holds accumulator sized results, is 64 bytes. */
module tb_accel_adapter
  import soc_pkg::*;
();

  localparam int CLK_PERIOD = 10;
  localparam int ARRAY_SIZE = 4;
  localparam int DATA_WIDTH = 8;
  localparam int RESULT_WIDTH = 32;
  localparam int DIN_BYTES = ARRAY_SIZE * ARRAY_SIZE * (DATA_WIDTH / 8);
  localparam int DOUT_BYTES = ARRAY_SIZE * ARRAY_SIZE * (RESULT_WIDTH / 8);

  logic clk, rst_n;
  int n_ok, n_err;

  logic [AXIL_ADDR_WIDTH-1:0] awaddr, araddr;
  logic awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
  logic [AXIL_DATA_WIDTH-1:0] wdata, rdata;
  logic [AXIL_STRB_WIDTH-1:0] wstrb;
  logic [1:0] bresp, rresp;

  logic mode, load, start, clr_error;
  logic [AXIL_DATA_WIDTH-1:0] status;
  logic data_req, data_we;
  logic [15:0] data_addr;
  logic [AXIL_DATA_WIDTH-1:0] data_wdata, data_rdata;
  logic data_ready, data_error;

  int unsigned shell_latency;
  logic shell_force_error;

  int n_load, n_start, n_clr;
  logic mode_at_load, mode_at_start;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  axil_master_drv u_drv (
      .clk_i(clk),
      .rst_ni(rst_n),
      .m_axi_awaddr(awaddr),
      .m_axi_awvalid(awvalid),
      .m_axi_awready(awready),
      .m_axi_wdata(wdata),
      .m_axi_wstrb(wstrb),
      .m_axi_wvalid(wvalid),
      .m_axi_wready(wready),
      .m_axi_bresp(bresp),
      .m_axi_bvalid(bvalid),
      .m_axi_bready(bready),
      .m_axi_araddr(araddr),
      .m_axi_arvalid(arvalid),
      .m_axi_arready(arready),
      .m_axi_rdata(rdata),
      .m_axi_rresp(rresp),
      .m_axi_rvalid(rvalid),
      .m_axi_rready(rready)
  );

  accel_adapter #(
      .BASE_ADDR(ACCEL_BASE),
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .RESULT_WIDTH(RESULT_WIDTH)
  ) u_dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .s_axi_awaddr(awaddr),
      .s_axi_awvalid(awvalid),
      .s_axi_awready(awready),
      .s_axi_wdata(wdata),
      .s_axi_wstrb(wstrb),
      .s_axi_wvalid(wvalid),
      .s_axi_wready(wready),
      .s_axi_bresp(bresp),
      .s_axi_bvalid(bvalid),
      .s_axi_bready(bready),
      .s_axi_araddr(araddr),
      .s_axi_arvalid(arvalid),
      .s_axi_arready(arready),
      .s_axi_rdata(rdata),
      .s_axi_rresp(rresp),
      .s_axi_rvalid(rvalid),
      .s_axi_rready(rready),
      .mode_o(mode),
      .load_o(load),
      .start_o(start),
      .clr_error_o(clr_error),
      .status_i(status),
      .data_req_o(data_req),
      .data_we_o(data_we),
      .data_addr_o(data_addr),
      .data_wdata_o(data_wdata),
      .data_rdata_i(data_rdata),
      .data_ready_i(data_ready),
      .data_error_i(data_error)
  );

  /* Model of the accelerator shell: it answers a request after the number of cycles the test
     chooses, never in the same cycle the request is raised, which is what the contract says. */
  logic [AXIL_DATA_WIDTH-1:0] din_mem[64];
  logic [AXIL_DATA_WIDTH-1:0] dout_mem[64];

  logic [15:0] off_in, off_out;
  logic [5:0] idx;
  int unsigned lat_cnt;

  assign off_in = data_addr - ACCEL_OFF_DATA_IN;
  assign off_out = data_addr - ACCEL_OFF_DATA_OUT;
  assign idx = data_we ? off_in[7:2] : off_out[7:2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lat_cnt <= 0;
      data_ready <= 1'b0;
      data_error <= 1'b0;
      data_rdata <= '0;
      for (int i = 0; i < 64; i++) begin
        din_mem[i] <= '0;
      end
    end else begin
      data_ready <= 1'b0;
      if (data_req && !data_ready) begin
        if (lat_cnt + 1 >= shell_latency) begin
          lat_cnt <= 0;
          data_ready <= 1'b1;
          data_error <= shell_force_error;
          data_rdata <= dout_mem[idx];
          if (data_we && !shell_force_error) din_mem[idx] <= data_wdata;
        end else begin
          lat_cnt <= lat_cnt + 1;
        end
      end else begin
        lat_cnt <= 0;
      end
    end
  end

  /* Pulses are counted with the mode seen in the same cycle, which is the rule being checked.
     The counters are cleared here and not in the test body, because a variable driven by a
     sequential block cannot also be written from somewhere else. */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      n_load <= 0;
      n_start <= 0;
      n_clr <= 0;
      mode_at_load <= 1'b0;
      mode_at_start <= 1'b0;
    end else begin
      if (load) begin
        n_load <= n_load + 1;
        mode_at_load <= mode;
      end
      if (start) begin
        n_start <= n_start + 1;
        mode_at_start <= mode;
      end
      if (clr_error) begin
        n_clr <= n_clr + 1;
      end
    end
  end

  task automatic check(input string what, input logic cond);
    if (cond === 1'b1) begin
      n_ok++;
    end else begin
      n_err++;
      $display("ERRO %s", what);
    end
  endtask

  initial begin
    n_ok = 0;
    n_err = 0;
    shell_latency = 1;
    shell_force_error = 1'b0;
    status = 32'h0000_0000;
    for (int i = 0; i < 64; i++) begin
      dout_mem[i] = 32'hD0_00_00_00 + i;
    end
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // Loading the weights: mode 0 with the load command in the same write.
    u_drv.write(ACCEL_BASE + ACCEL_OFF_CTRL, 32'h0000_0002, 4'hF);
    check("escrever CTRL e aceito", u_drv.last_resp == RESP_OKAY);
    repeat (3) @(negedge clk);
    check("escrever LOAD gera um pulso de carregar", n_load == 1);
    check("o pulso de carregar sai com o modo escrito junto", mode_at_load == 1'b0);
    check("escrever LOAD nao gera pulso de calcular", n_start == 0);

    // Computing: mode 1 with the start command, which is the rule that mode comes with the pulse.
    u_drv.write(ACCEL_BASE + ACCEL_OFF_CTRL, 32'h0000_0005, 4'hF);
    repeat (3) @(negedge clk);
    check("escrever START gera um pulso de calcular", n_start == 1);
    check("o pulso de calcular sai com o modo escrito junto", mode_at_start == 1'b1);
    check("o modo fica guardado depois do pulso", mode == 1'b1);
    check("escrever START nao repete o pulso de carregar", n_load == 1);

    u_drv.write(ACCEL_BASE + ACCEL_OFF_CTRL, 32'h0000_0008, 4'hF);
    repeat (3) @(negedge clk);
    check("escrever CLR_ERROR gera um pulso de limpar erro", n_clr == 1);
    check("escrever CLR_ERROR zera o modo escrito junto", mode == 1'b0);

    u_drv.write(ACCEL_BASE + ACCEL_OFF_CTRL, 32'h0000_0001, 4'hF);
    repeat (2) @(negedge clk);
    u_drv.read(ACCEL_BASE + ACCEL_OFF_CTRL);
    check("ler CTRL devolve o modo guardado", u_drv.last_rdata == 32'h0000_0001);
    check("ler CTRL devolve zero nos bits de comando", u_drv.last_resp == RESP_OKAY);

    // A write with no byte enabled must not change anything.
    u_drv.write(ACCEL_BASE + ACCEL_OFF_CTRL, 32'h0000_0000, 4'h0);
    repeat (2) @(negedge clk);
    u_drv.read(ACCEL_BASE + ACCEL_OFF_CTRL);
    check("escrever CTRL sem byte habilitado nao muda o modo",
          u_drv.last_rdata == 32'h0000_0001);
    check("escrever CTRL sem byte habilitado nao gera pulso", n_load == 1 && n_start == 1);

    status = 32'h0000_0006;
    u_drv.read(ACCEL_BASE + ACCEL_OFF_STATUS);
    check("ler STATUS espelha o acelerador", u_drv.last_rdata == 32'h0000_0006);
    u_drv.write(ACCEL_BASE + ACCEL_OFF_STATUS, 32'hFFFF_FFFF, 4'hF);
    check("escrever STATUS e recusado", u_drv.last_resp == RESP_SLVERR);

    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN + 4, 32'h0A0B_0C0D, 4'hF);
    check("escrever no buffer de entrada e aceito", u_drv.last_resp == RESP_OKAY);
    check("o dado chega ao acelerador", din_mem[1] == 32'h0A0B_0C0D);
    u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_IN);
    check("ler o buffer de entrada e recusado", u_drv.last_resp == RESP_SLVERR);

    u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_OUT + 8);
    check("ler o buffer de saida e aceito", u_drv.last_resp == RESP_OKAY);
    check("o buffer de saida devolve o valor do acelerador",
          u_drv.last_rdata == (32'hD0_00_00_00 + 2));
    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_OUT, 32'h1234_5678, 4'hF);
    check("escrever no buffer de saida e recusado", u_drv.last_resp == RESP_SLVERR);

    /* Past the end of a buffer there is no element, even though the address is still inside the
       region of the accelerator. */
    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN + DIN_BYTES, 32'hDEAD_BEEF, 4'hF);
    check("escrever depois do fim do buffer de entrada e recusado",
          u_drv.last_resp == RESP_SLVERR);
    u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_OUT + DOUT_BYTES);
    check("ler depois do fim do buffer de saida e recusado", u_drv.last_resp == RESP_SLVERR);

    u_drv.read(ACCEL_BASE + 32'h0008);
    check("offset sem registrador e recusado", u_drv.last_resp == RESP_SLVERR);
    u_drv.write(ACCEL_BASE + 32'h3000, 32'h1111_1111, 4'hF);
    check("offset no vazio da regiao e recusado", u_drv.last_resp == RESP_SLVERR);

    // A shell that takes its time: the adapter has to wait, and the bus waits with it.
    shell_latency = 5;
    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN + 8, 32'h5566_7788, 4'hF);
    check("acelerador lento: a escrita e aceita", u_drv.last_resp == RESP_OKAY);
    check("acelerador lento: o dado chega", din_mem[2] == 32'h5566_7788);
    u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_OUT + 12);
    check("acelerador lento: a leitura devolve o valor certo",
          u_drv.last_rdata == (32'hD0_00_00_00 + 3));
    shell_latency = 1;

    // An invalid access reported by the shell comes back as a slave error.
    shell_force_error = 1'b1;
    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN, 32'hBAD0_BAD0, 4'hF);
    check("erro vindo do acelerador vira erro do escravo", u_drv.last_resp == RESP_SLVERR);
    check("o acesso recusado nao gravou nada", din_mem[0] == 32'h0000_0000);
    shell_force_error = 1'b0;

    u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN, 32'h0000_00FF, 4'hF);
    check("depois do erro o adaptador continua servindo", u_drv.last_resp == RESP_OKAY);

    for (int i = 0; i < DIN_BYTES / 4; i++) begin
      u_drv.write(ACCEL_BASE + ACCEL_OFF_DATA_IN + i * 4, 32'hE000_0000 + i, 4'hF);
      check($sformatf("varredura do buffer de entrada: elemento %0d", i),
            din_mem[i] == (32'hE000_0000 + i));
    end

    for (int i = 0; i < DOUT_BYTES / 4; i++) begin
      u_drv.read(ACCEL_BASE + ACCEL_OFF_DATA_OUT + i * 4);
      check($sformatf("varredura do buffer de saida: elemento %0d", i),
            u_drv.last_rdata == (32'hD0_00_00_00 + i));
    end

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

  initial begin
    #(5000 * CLK_PERIOD);
    $fatal(1, "tb_accel_adapter nao terminou no tempo previsto");
  end

endmodule
