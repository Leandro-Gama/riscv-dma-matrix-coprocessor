module axil_slave_port_dp
  import soc_pkg::*;
#(
    parameter logic [1:0] ERR_RESP = RESP_SLVERR
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic cap_aw_i,
    input  logic cap_w_i,
    input  logic cap_ar_i,
    input  logic cap_rsp_i,

    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [AXIL_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0] s_axi_wstrb,
    input  logic [AXIL_ADDR_WIDTH-1:0] s_axi_araddr,
    output logic [AXIL_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0] resp_o,

    output logic [AXIL_ADDR_WIDTH-1:0] addr_o,
    output logic [AXIL_STRB_WIDTH-1:0] be_o,
    output logic [AXIL_DATA_WIDTH-1:0] wdata_o,
    input  logic [AXIL_DATA_WIDTH-1:0] rdata_i,
    input  logic err_i
);

  logic [AXIL_DATA_WIDTH-1:0] rdata_q;
  logic err_q;

  // Reads and writes never overlap in this port, so one address register serves both.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_o <= '0;
    end else if (cap_aw_i) begin
      addr_o <= s_axi_awaddr;
    end else if (cap_ar_i) begin
      addr_o <= s_axi_araddr;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wdata_o <= '0;
      be_o <= '0;
    end else if (cap_w_i) begin
      wdata_o <= s_axi_wdata;
      be_o <= s_axi_wstrb;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_q <= '0;
      err_q <= 1'b0;
    end else if (cap_rsp_i) begin
      rdata_q <= rdata_i;
      err_q <= err_i;
    end
  end

  assign s_axi_rdata = rdata_q;
  /* A real slave reports SLVERR. The interconnect reuses this port with DECERR to answer an
     address that belongs to no slave at all. */
  assign resp_o = err_q ? ERR_RESP : RESP_OKAY;

endmodule
