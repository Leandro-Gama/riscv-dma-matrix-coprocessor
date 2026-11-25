/* Both arbitration policies side by side under the same stimulus: the same requests go to one
   arbiter with priority to the DMA and one with round robin, so the difference between them is
   the only thing the checks can see. */
module tb_axil_arbiter
  import soc_pkg::*;
();

  localparam int CLK_PERIOD = 10;

  logic clk, rst_n;
  logic [NUM_MASTERS-1:0] req;
  logic done;
  logic [NUM_MASTERS-1:0] grant_p, grant_r;
  logic hold_p, hold_r;
  logic start_p, start_r;

  int n_ok, n_err;
  int n_prio_dma, n_rr_cpu, n_rr_dma;
  logic [NUM_MASTERS-1:0] prev_rr;

  localparam logic [NUM_MASTERS-1:0] ONLY_CPU = 2'b01;
  localparam logic [NUM_MASTERS-1:0] ONLY_DMA = 2'b10;
  localparam logic [NUM_MASTERS-1:0] BOTH = 2'b11;
  localparam logic [NUM_MASTERS-1:0] NONE = 2'b00;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // A master only starts a transaction while it is the one holding the grant.
  assign start_p = |(grant_p & req);
  assign start_r = |(grant_r & req);

  soc_axil_arbiter #(
      .ARB_POLICY(ARB_DMA_PRIORITY)
  ) u_prio (
      .clk_i(clk),
      .rst_ni(rst_n),
      .req_i(req),
      .start_i(start_p),
      .done_i(done),
      .grant_o(grant_p),
      .hold_o(hold_p)
  );

  soc_axil_arbiter #(
      .ARB_POLICY(ARB_ROUND_ROBIN)
  ) u_rr (
      .clk_i(clk),
      .rst_ni(rst_n),
      .req_i(req),
      .start_i(start_r),
      .done_i(done),
      .grant_o(grant_r),
      .hold_o(hold_r)
  );

  task automatic check(input string what, input logic cond);
    if (cond === 1'b1) begin
      n_ok++;
    end else begin
      n_err++;
      $display("ERRO %s", what);
    end
  endtask

  // One transaction of the granted master: it is locked for a cycle and then reports completion.
  task automatic finish_txn();
    @(negedge clk);
    done = 1'b1;
    @(negedge clk);
    done = 1'b0;
  endtask

  initial begin
    n_ok  = 0;
    n_err = 0;
    n_prio_dma = 0;
    n_rr_cpu = 0;
    n_rr_dma = 0;
    prev_rr = NONE;
    req   = NONE;
    done  = 1'b0;
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    check("sem pedido nenhum ninguem recebe o barramento", grant_p == NONE && grant_r == NONE);
    check("sem pedido nenhum o barramento nao fica preso", !hold_p && !hold_r);

    req = ONLY_CPU;
    @(negedge clk);
    check("so a CPU pede, as duas politicas dao para a CPU",
          grant_p == ONLY_CPU && grant_r == ONLY_CPU);
    finish_txn();

    req = ONLY_DMA;
    @(negedge clk);
    check("so o DMA pede, as duas politicas dao para o DMA",
          grant_p == ONLY_DMA && grant_r == ONLY_DMA);
    finish_txn();

    req = NONE;
    @(negedge clk);
    check("pedido retirado libera o barramento", grant_p == NONE && grant_r == NONE);

    /* Both asking at the same time is where the two policies part: priority always answers the
       DMA, round robin changes master every transaction. Which of the two round robin starts
       with depends on who it served last, so what is checked is the alternation itself and the
       even split, not a fixed order. */
    req = BOTH;
    @(negedge clk);
    for (int t = 0; t < 4; t++) begin
      if (grant_p == ONLY_DMA) n_prio_dma++;
      if (grant_r == ONLY_CPU) n_rr_cpu++;
      if (grant_r == ONLY_DMA) n_rr_dma++;
      if (t > 0) begin
        check($sformatf("round robin troca de mestre na transacao %0d", t), grant_r != prev_rr);
      end
      prev_rr = grant_r;
      finish_txn();
    end
    check("os dois pedem: prioridade da o barramento ao DMA nas quatro vezes", n_prio_dma == 4);
    check("round robin atende a CPU na metade das transacoes", n_rr_cpu == 2);
    check("round robin atende o DMA na metade das transacoes", n_rr_dma == 2);

    // With priority, the CPU is served as soon as the DMA stops asking: it is delayed, not locked out.
    req = ONLY_CPU;
    @(negedge clk);
    check("prioridade atende a CPU quando o DMA para de pedir", grant_p == ONLY_CPU);
    finish_txn();

    /* The grant is held for the whole transaction, so a request arriving in the middle of one
       cannot take the bus away from the master that is being answered. */
    req = ONLY_DMA;
    @(negedge clk);
    check("DMA recebe o barramento", grant_p == ONLY_DMA && grant_r == ONLY_DMA);
    @(negedge clk);
    check("transacao em curso prende o barramento", hold_p && hold_r);
    req = BOTH;
    @(negedge clk);
    check("pedido novo no meio da transacao nao tira o barramento do DMA",
          grant_p == ONLY_DMA && grant_r == ONLY_DMA);
    done = 1'b1;
    @(negedge clk);
    done = 1'b0;
    req  = NONE;
    @(negedge clk);
    check("terminada a transacao o barramento e reavaliado", !hold_p && !hold_r);

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

  initial begin
    #(200 * CLK_PERIOD);
    $fatal(1, "tb_axil_arbiter nao terminou no tempo previsto");
  end

endmodule
