/* Driver for the harness without CPU. It does, over the bus and in the same order, what the test
   firmware does: read the parameter block, program the DMA, start it, poll STATUS until DONE,
   store STATUS, clear CMD and only then count the operation. The monitor therefore sees the same
   memory traffic with or without the CPU. */
class mm_driver_bfm extends mm_driver_base;
  `uvm_component_utils(mm_driver_bfm)

  virtual axil_bfm_if bfm;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    bfm = cfg.bfm_vif;
    if (bfm == null) `uvm_fatal("MM_BFM", "cfg.bfm_vif is null: this harness has no bus master")
  endfunction

  task play_firmware(mm_item it);
    bit [31:0] pb[PB_WORDS];
    bit [31:0] dim_k, control, status, done;

    do bus_read(pb_addr(PB_CMD), pb[PB_CMD]); while (pb[PB_CMD] == 0);
    for (int w = PB_ADDR_A; w <= PB_FLAGS; w++) bus_read(pb_addr(w), pb[w]);

    dim_k = pb[PB_DIM_K];
    if (pb[PB_FLAGS][FLAG_FAULT_DIM_K]) dim_k = dim_k - 1;
    bus_write(DMAREG_BASE + DMA_REG_ADDR_A, pb[PB_ADDR_A]);
    bus_write(DMAREG_BASE + DMA_REG_ADDR_B, pb[PB_ADDR_B]);
    bus_write(DMAREG_BASE + DMA_REG_ADDR_C, pb[PB_ADDR_C]);
    bus_write(DMAREG_BASE + DMA_REG_DIM_M, pb[PB_DIM_M]);
    bus_write(DMAREG_BASE + DMA_REG_DIM_K, dim_k);
    bus_write(DMAREG_BASE + DMA_REG_DIM_N, pb[PB_DIM_N]);
    control = 32'h1 << DMA_CONTROL_START_BIT;
    control[DMA_CONTROL_IRQ_EN_BIT] = pb[PB_FLAGS][FLAG_IRQ_EN];
    bus_write(DMAREG_BASE + DMA_REG_CONTROL, control);

    do bus_read(DMAREG_BASE + DMA_REG_STATUS, status); while (!status[DMA_STATUS_DONE_BIT]);
    if (pb[PB_FLAGS][FLAG_FAULT_HANG]) begin
      wait (0);
    end

    bus_write(pb_addr(PB_STATUS), status);
    bus_write(pb_addr(PB_CMD), 32'h0);
    bus_read(pb_addr(PB_DONE_COUNT), done);
    bus_write(pb_addr(PB_DONE_COUNT), done + 1);
  endtask

  task recover();
    bfm.idle();
  endtask

  task bus_write(input logic [31:0] addr, input logic [31:0] data);
    logic [1:0] resp;
    bit ok;
    bfm.write(addr, data, 4'hF, cfg.bus_timeout_cycles, resp, ok);
    if (!ok) begin
      `uvm_error("MM_BFM_TIMEOUT", $sformatf("write 0x%08h got no answer in %0d cycles", addr,
                                             cfg.bus_timeout_cycles))
    end else if (resp != RESP_OKAY) begin
      `uvm_error("MM_BFM_RESP", $sformatf("write 0x%08h answered 0x%0h", addr, resp))
    end
  endtask

  task bus_read(input logic [31:0] addr, output bit [31:0] data);
    logic [31:0] value;
    logic [1:0] resp;
    bit ok;
    bfm.read(addr, cfg.bus_timeout_cycles, value, resp, ok);
    data = value;
    if (!ok) begin
      `uvm_error("MM_BFM_TIMEOUT", $sformatf("read 0x%08h got no answer in %0d cycles", addr,
                                             cfg.bus_timeout_cycles))
    end else if (resp != RESP_OKAY) begin
      `uvm_error("MM_BFM_RESP", $sformatf("read 0x%08h answered 0x%0h", addr, resp))
    end else if ($isunknown(value)) begin
      `uvm_error("MM_BFM_X", $sformatf("read 0x%08h returned 0x%08h", addr, value))
    end
  endtask

endclass
