// AXI4-Lite rules on the DMA master port: VALID is held, with stable payload, until READY.
module dma_master_sva (
    input logic        clk_i,
    input logic        rst_ni,
    input logic [31:0] m_axi_awaddr,
    input logic        m_axi_awvalid,
    input logic        m_axi_awready,
    input logic [31:0] m_axi_wdata,
    input logic [3:0]  m_axi_wstrb,
    input logic        m_axi_wvalid,
    input logic        m_axi_wready,
    input logic [31:0] m_axi_araddr,
    input logic        m_axi_arvalid,
    input logic        m_axi_arready
);
    a_aw_hold: assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_axi_awvalid && !m_axi_awready |=> m_axi_awvalid && $stable(m_axi_awaddr))
        else $error("SVA: AWVALID dropped or AWADDR changed before AWREADY");

    a_w_hold: assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_axi_wvalid && !m_axi_wready |=> m_axi_wvalid && $stable(m_axi_wdata) && $stable(m_axi_wstrb))
        else $error("SVA: WVALID dropped or WDATA changed before WREADY");

    a_ar_hold: assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_axi_arvalid && !m_axi_arready |=> m_axi_arvalid && $stable(m_axi_araddr))
        else $error("SVA: ARVALID dropped or ARADDR changed before ARREADY");

    a_one_at_a_time: assert property (@(posedge clk_i) disable iff (!rst_ni)
        !(m_axi_awvalid && m_axi_arvalid))
        else $error("SVA: read and write issued together");
endmodule

bind dma_axil_master dma_master_sva u_dma_master_sva (.*);
