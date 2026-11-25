/* Instruction memory. It sits outside the bus, wired only to the instruction port of the CPU, so
   fetching never competes with the DMA. The read answers in the same cycle, as the interface
   contract requires of a single-cycle core. */
module mem_instr
  import soc_pkg::*;
#(
    parameter logic [AXIL_ADDR_WIDTH-1:0] BASE_ADDR = IMEM_BASE,
    parameter int IMEM_BYTES = IMEM_BYTES_DEFAULT
) (
    input  logic [AXIL_ADDR_WIDTH-1:0] addr_i,
    output logic [AXIL_DATA_WIDTH-1:0] rdata_o
);

  localparam int WORDS = IMEM_BYTES / AXIL_STRB_WIDTH;
  localparam int IDX_WIDTH = $clog2(WORDS);

  logic [AXIL_DATA_WIDTH-1:0] mem[WORDS];
  logic [AXIL_ADDR_WIDTH-1:0] off;
  logic [IDX_WIDTH-1:0] idx;

  assign off = addr_i - BASE_ADDR;
  assign idx = off[IDX_WIDTH+1:2];
  assign rdata_o = mem[idx];

endmodule
