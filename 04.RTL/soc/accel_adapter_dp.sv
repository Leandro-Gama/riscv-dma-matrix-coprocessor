module accel_adapter_dp
  import soc_pkg::*;
#(
    parameter logic [AXIL_ADDR_WIDTH-1:0] BASE_ADDR = ACCEL_BASE,
    parameter int ARRAY_SIZE = 4,
    parameter int DATA_WIDTH = 8,
    parameter int RESULT_WIDTH = 32
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic req_i,
    input  logic we_i,
    input  logic [AXIL_ADDR_WIDTH-1:0] addr_i,
    input  logic [AXIL_STRB_WIDTH-1:0] be_i,
    input  logic [AXIL_DATA_WIDTH-1:0] wdata_i,
    input  logic ack_i,
    output logic [AXIL_DATA_WIDTH-1:0] rdata_o,
    output logic err_o,

    input  logic [AXIL_DATA_WIDTH-1:0] status_i,
    input  logic [AXIL_DATA_WIDTH-1:0] shell_rdata_i,
    input  logic shell_error_i,

    output logic mode_o,
    output logic load_o,
    output logic start_o,
    output logic clr_error_o,
    output logic [15:0] data_addr_o,
    output logic [AXIL_DATA_WIDTH-1:0] data_wdata_o,

    output logic is_buf_o,
    output logic bad_o
);

  // One element every DATA_WIDTH/8 bytes going in, and the accumulator width coming out.
  localparam int DIN_BYTES = ARRAY_SIZE * ARRAY_SIZE * (DATA_WIDTH / 8);
  localparam int DOUT_BYTES = ARRAY_SIZE * ARRAY_SIZE * (RESULT_WIDTH / 8);

  logic [AXIL_ADDR_WIDTH-1:0] off;
  logic sel_ctrl, sel_status, in_din, in_dout;
  logic mode_q;
  logic [2:0] pulse_q;

  assign off = addr_i - BASE_ADDR;

  assign sel_ctrl = (off[15:0] == ACCEL_OFF_CTRL);
  assign sel_status = (off[15:0] == ACCEL_OFF_STATUS);
  assign in_din = (off[15:0] >= ACCEL_OFF_DATA_IN) && (off[15:0] < (ACCEL_OFF_DATA_IN + DIN_BYTES));
  assign in_dout =
      (off[15:0] >= ACCEL_OFF_DATA_OUT) && (off[15:0] < (ACCEL_OFF_DATA_OUT + DOUT_BYTES));

  /* The input buffer only takes writes and the output buffer only gives reads, so the direction
     is part of what makes an access valid. Everything else inside the region is refused. */
  assign is_buf_o = (in_din && we_i) || (in_dout && !we_i);
  assign bad_o = !(sel_ctrl || (sel_status && !we_i) || is_buf_o);

  /* The pulse is raised one cycle after the write is answered, together with the new MODE, which
     is what the interface contract asks for: the mode of a command is the mode written with it. */
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mode_q <= 1'b0;
      pulse_q <= '0;
    end else begin
      pulse_q <= '0;
      if (ack_i && req_i && we_i && sel_ctrl && be_i[0]) begin
        mode_q <= wdata_i[ACCEL_CTRL_MODE_BIT];
        pulse_q <= wdata_i[ACCEL_CTRL_CLR_ERROR_BIT:ACCEL_CTRL_LOAD_BIT];
      end
    end
  end

  assign mode_o = mode_q;
  assign load_o = pulse_q[0];
  assign start_o = pulse_q[1];
  assign clr_error_o = pulse_q[2];

  assign data_addr_o = off[15:0];
  assign data_wdata_o = wdata_i;

  // The command bits are write only, so reading CTRL shows the stored mode and nothing else.
  always_comb begin
    rdata_o = '0;
    if (sel_ctrl) begin
      rdata_o[ACCEL_CTRL_MODE_BIT] = mode_q;
    end else if (sel_status) begin
      rdata_o = status_i;
    end else if (in_dout) begin
      rdata_o = shell_rdata_i;
    end
  end

  assign err_o = bad_o || (is_buf_o && shell_error_i);

endmodule
