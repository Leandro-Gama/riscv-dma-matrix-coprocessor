module axil_master_port_dp
  import soc_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,

    input  logic cap_req_i,
    input  logic [AXIL_ADDR_WIDTH-1:0] addr_i,
    input  logic [AXIL_STRB_WIDTH-1:0] be_i,
    input  logic [AXIL_DATA_WIDTH-1:0] wdata_i,

    output logic [AXIL_ADDR_WIDTH-1:0] s_axi_awaddr,
    output logic [AXIL_DATA_WIDTH-1:0] s_axi_wdata,
    output logic [AXIL_STRB_WIDTH-1:0] s_axi_wstrb,
    output logic [AXIL_ADDR_WIDTH-1:0] s_axi_araddr
);

  logic [AXIL_ADDR_WIDTH-1:0] addr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_q <= '0;
      s_axi_wdata <= '0;
      s_axi_wstrb <= '0;
    end else if (cap_req_i) begin
      addr_q <= addr_i;
      s_axi_wdata <= wdata_i;
      s_axi_wstrb <= be_i;
    end
  end

  // One transaction at a time, so the same address register drives both address channels.
  assign s_axi_awaddr = addr_q;
  assign s_axi_araddr = addr_q;

endmodule
