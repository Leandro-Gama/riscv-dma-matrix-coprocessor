/* Binding the checker to the two front ends covers both sides of the interconnect at once: the
   masters bring the checker to the slave side ports, the slaves bring it to the master side. */
bind axil_slave_port axil_checker #(
    .NAME("slave")
) u_chk (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .awaddr(s_axi_awaddr),
    .awvalid(s_axi_awvalid),
    .awready(s_axi_awready),
    .wdata(s_axi_wdata),
    .wstrb(s_axi_wstrb),
    .wvalid(s_axi_wvalid),
    .wready(s_axi_wready),
    .bresp(s_axi_bresp),
    .bvalid(s_axi_bvalid),
    .bready(s_axi_bready),
    .araddr(s_axi_araddr),
    .arvalid(s_axi_arvalid),
    .arready(s_axi_arready),
    .rdata(s_axi_rdata),
    .rresp(s_axi_rresp),
    .rvalid(s_axi_rvalid),
    .rready(s_axi_rready)
);

bind axil_master_port axil_checker #(
    .NAME("master")
) u_chk (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .awaddr(m_axi_awaddr),
    .awvalid(m_axi_awvalid),
    .awready(m_axi_awready),
    .wdata(m_axi_wdata),
    .wstrb(m_axi_wstrb),
    .wvalid(m_axi_wvalid),
    .wready(m_axi_wready),
    .bresp(m_axi_bresp),
    .bvalid(m_axi_bvalid),
    .bready(m_axi_bready),
    .araddr(m_axi_araddr),
    .arvalid(m_axi_arvalid),
    .arready(m_axi_arready),
    .rdata(m_axi_rdata),
    .rresp(m_axi_rresp),
    .rvalid(m_axi_rvalid),
    .rready(m_axi_rready)
);

bind accel_adapter accel_shell_checker u_shell_chk (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .data_req(data_req_o),
    .data_we(data_we_o),
    .data_addr(data_addr_o),
    .data_wdata(data_wdata_o),
    .data_ready(data_ready_i),
    .load(load_o),
    .start(start_o),
    .clr_error(clr_error_o)
);
