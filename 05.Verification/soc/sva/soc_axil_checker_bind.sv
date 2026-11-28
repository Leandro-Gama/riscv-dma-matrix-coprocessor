/* The AXI4-Lite rule checker on the ports of the subsystem that no protocol front end of the
   System covers: the two masters (data port of the CPU, master port of the DMA), the registers of
   the DMA, the accelerator slot of the interconnect and the buffer side of the local decoder. On
   the masters it also checks one transaction at a time, which the interconnect relies on. */
`define SOC_AXIL_CHK(LABEL, INST, PFX, IDX) \
  bind soc_subsys axil_checker #( \
      .NAME(LABEL) \
  ) INST ( \
      .clk_i, \
      .rst_ni, \
      .awaddr(PFX``awaddr[IDX]), \
      .awvalid(PFX``awvalid[IDX]), \
      .awready(PFX``awready[IDX]), \
      .wdata(PFX``wdata[IDX]), \
      .wstrb(PFX``wstrb[IDX]), \
      .wvalid(PFX``wvalid[IDX]), \
      .wready(PFX``wready[IDX]), \
      .bresp(PFX``bresp[IDX]), \
      .bvalid(PFX``bvalid[IDX]), \
      .bready(PFX``bready[IDX]), \
      .araddr(PFX``araddr[IDX]), \
      .arvalid(PFX``arvalid[IDX]), \
      .arready(PFX``arready[IDX]), \
      .rdata(PFX``rdata[IDX]), \
      .rresp(PFX``rresp[IDX]), \
      .rvalid(PFX``rvalid[IDX]), \
      .rready(PFX``rready[IDX]) \
  );

`SOC_AXIL_CHK("cpu", u_chk_cpu, mst_, MST_CPU)
`SOC_AXIL_CHK("dma", u_chk_dma, mst_, MST_DMA)
`SOC_AXIL_CHK("dmareg", u_chk_dmareg, slv_, SLV_DMAREG)
`SOC_AXIL_CHK("accel", u_chk_accel, slv_, SLV_ACCEL)
`SOC_AXIL_CHK("accel_buffers", u_chk_buffers, acc_, 1)
