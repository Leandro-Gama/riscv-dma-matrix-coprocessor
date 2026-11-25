/* Instruction memory: the read must land in the same cycle as the address, with no handshake,
   because a single-cycle core has nowhere to wait. */
module tb_mem_instr
  import soc_pkg::*;
();

  localparam int WORDS = IMEM_BYTES_DEFAULT / AXIL_STRB_WIDTH;

  logic [AXIL_ADDR_WIDTH-1:0] addr;
  logic [AXIL_DATA_WIDTH-1:0] rdata;
  int unsigned n_ok, n_err;

  mem_instr u_imem (
      .addr_i (addr),
      .rdata_o(rdata)
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
    addr = IMEM_BASE;

    for (int i = 0; i < WORDS; i++) begin
      u_imem.mem[i] = 32'h0000_1000 + i;
    end
    #1ns;

    check("primeira palavra sai no mesmo instante do endereco", rdata == 32'h0000_1000);

    addr = IMEM_BASE + 4;
    #1ns;
    check("segunda palavra", rdata == 32'h0000_1001);

    // A byte address inside a word still selects that word: addr[1:0] plays no part.
    addr = IMEM_BASE + 6;
    #1ns;
    check("endereco dentro da palavra devolve a mesma palavra", rdata == 32'h0000_1001);

    addr = IMEM_BASE + IMEM_BYTES_DEFAULT - 4;
    #1ns;
    check("ultima palavra da memoria", rdata == (32'h0000_1000 + WORDS - 1));

    $display("RESUMO: %0d OK, %0d ERRO", n_ok, n_err);
    $finish;
  end

endmodule
