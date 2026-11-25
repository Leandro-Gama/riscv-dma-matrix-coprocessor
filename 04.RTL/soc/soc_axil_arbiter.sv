/* Grants the bus for a whole transaction. Every master has a single transaction in flight, so
   locking the grant from the first address until the response costs nothing and removes per
   channel routing and response reordering from the interconnect. */
module soc_axil_arbiter
  import soc_pkg::*;
#(
    parameter logic [0:0] ARB_POLICY = ARB_DMA_PRIORITY
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [NUM_MASTERS-1:0] req_i,
    input  logic start_i,
    input  logic done_i,

    output logic [NUM_MASTERS-1:0] grant_o,
    output logic hold_o
);

  typedef enum logic [0:0] {
    IDLE,
    BUSY
  } state_e;

  state_e state_q, state_d;

  logic [NUM_MASTERS-1:0] win, grant_q;
  logic served_dma_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      // A slave that answers in the same cycle needs no hold at all.
      IDLE: if (start_i && !done_i) state_d = BUSY;
      BUSY: if (done_i) state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

  always_comb begin
    grant_o = (state_q == IDLE) ? win : grant_q;
    hold_o  = (state_q != IDLE);
  end

  always_comb begin
    win = '0;
    if (ARB_POLICY == ARB_ROUND_ROBIN) begin
      /* The master that was not served last goes first, so neither of them can be held off while
         the other keeps asking. */
      if (req_i[MST_CPU] && req_i[MST_DMA]) begin
        if (served_dma_q) win[MST_CPU] = 1'b1;
        else win[MST_DMA] = 1'b1;
      end else if (req_i[MST_DMA]) begin
        win[MST_DMA] = 1'b1;
      end else if (req_i[MST_CPU]) begin
        win[MST_CPU] = 1'b1;
      end
    end else begin
      /* Fixed priority to the data mover: the status polling of the CPU never takes bandwidth
         from a transfer, and the CPU is only ever delayed, because the transfers of the DMA have
         gaps while the accelerator works and the operation ends. */
      if (req_i[MST_DMA]) begin
        win[MST_DMA] = 1'b1;
      end else if (req_i[MST_CPU]) begin
        win[MST_CPU] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      grant_q <= '0;
      served_dma_q <= 1'b0;
    end else if (state_q == IDLE && start_i) begin
      grant_q <= win;
      served_dma_q <= win[MST_DMA];
    end
  end

endmodule
