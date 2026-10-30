interface env_smoke_if #(
    parameter int WIDTH = 4
) (
    input logic clk
);

  logic             rst_n;
  logic             en;
  logic [WIDTH-1:0] count;

  clocking cb @(posedge clk);
    default input #1step output #1;
    output rst_n, en;
    input count;
  endclocking

endinterface
