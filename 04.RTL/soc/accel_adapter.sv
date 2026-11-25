/* AXI4-Lite to accelerator shell. The adapter owns CTRL, turns a write to it into one cycle
   pulses, mirrors STATUS, and translates buffer accesses into the simple request the shell
   speaks. The accelerator therefore keeps the small interface its owner specified and never sees
   the bus protocol. */
module accel_adapter
  import soc_pkg::*;
#(
    parameter logic [AXIL_ADDR_WIDTH-1:0] BASE_ADDR = ACCEL_BASE,
    parameter int ARRAY_SIZE = 4,
    parameter int DATA_WIDTH = 8,
    parameter int RESULT_WIDTH = 32
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [AXIL_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [AXIL_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready,

    output logic mode_o,
    output logic load_o,
    output logic start_o,
    output logic clr_error_o,
    input  logic [AXIL_DATA_WIDTH-1:0] status_i,
    output logic data_req_o,
    output logic data_we_o,
    output logic [15:0] data_addr_o,
    output logic [AXIL_DATA_WIDTH-1:0] data_wdata_o,
    input  logic [AXIL_DATA_WIDTH-1:0] data_rdata_i,
    input  logic data_ready_i,
    input  logic data_error_i
);

  logic req, we, ack, err;
  logic [AXIL_ADDR_WIDTH-1:0] addr;
  logic [AXIL_STRB_WIDTH-1:0] be;
  logic [AXIL_DATA_WIDTH-1:0] wdata, rdata;
  logic is_buf, bad;

  axil_slave_port u_port (
      .clk_i,
      .rst_ni,
      .s_axi_awaddr,
      .s_axi_awvalid,
      .s_axi_awready,
      .s_axi_wdata,
      .s_axi_wstrb,
      .s_axi_wvalid,
      .s_axi_wready,
      .s_axi_bresp,
      .s_axi_bvalid,
      .s_axi_bready,
      .s_axi_araddr,
      .s_axi_arvalid,
      .s_axi_arready,
      .s_axi_rdata,
      .s_axi_rresp,
      .s_axi_rvalid,
      .s_axi_rready,
      .req_o(req),
      .we_o(we),
      .addr_o(addr),
      .be_o(be),
      .wdata_o(wdata),
      .ack_i(ack),
      .rdata_i(rdata),
      .err_i(err)
  );

  accel_adapter_ctrl u_ctrl (
      .clk_i,
      .rst_ni,
      .req_i(req),
      .is_buf_i(is_buf),
      .bad_i(bad),
      .shell_ready_i(data_ready_i),
      .ack_o(ack),
      .data_req_o
  );

  accel_adapter_dp #(
      .BASE_ADDR(BASE_ADDR),
      .ARRAY_SIZE(ARRAY_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .RESULT_WIDTH(RESULT_WIDTH)
  ) u_dp (
      .clk_i,
      .rst_ni,
      .req_i(req),
      .we_i(we),
      .addr_i(addr),
      .be_i(be),
      .wdata_i(wdata),
      .ack_i(ack),
      .rdata_o(rdata),
      .err_o(err),
      .status_i,
      .shell_rdata_i(data_rdata_i),
      .shell_error_i(data_error_i),
      .mode_o,
      .load_o,
      .start_o,
      .clr_error_o,
      .data_addr_o,
      .data_wdata_o,
      .is_buf_o(is_buf),
      .bad_o(bad)
  );

  assign data_we_o = we;

endmodule
