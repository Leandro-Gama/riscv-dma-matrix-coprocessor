package soc_pkg;

  localparam int AXIL_ADDR_WIDTH = 32;
  localparam int AXIL_DATA_WIDTH = 32;
  localparam int AXIL_STRB_WIDTH = AXIL_DATA_WIDTH / 8;

  localparam logic [1:0] RESP_OKAY = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  localparam logic [AXIL_ADDR_WIDTH-1:0] IMEM_BASE = 32'h0000_0000;
  localparam logic [AXIL_ADDR_WIDTH-1:0] DMEM_BASE = 32'h1000_0000;
  localparam logic [AXIL_ADDR_WIDTH-1:0] DMAREG_BASE = 32'h2000_0000;
  localparam logic [AXIL_ADDR_WIDTH-1:0] ACCEL_BASE = 32'h4000_0000;

  localparam int IMEM_BYTES_DEFAULT = 4 * 1024;
  localparam int DMEM_BYTES_DEFAULT = 16 * 1024;
  localparam int DMAREG_BYTES = 4 * 1024;
  localparam int ACCEL_BYTES = 64 * 1024;

  localparam int NUM_MASTERS = 2;
  localparam int NUM_SLAVES = 3;

  localparam int MST_CPU = 0;
  localparam int MST_DMA = 1;

  localparam int SLV_DMEM = 0;
  localparam int SLV_DMAREG = 1;
  localparam int SLV_ACCEL = 2;

  localparam logic [0:0] ARB_DMA_PRIORITY = 1'b0;
  localparam logic [0:0] ARB_ROUND_ROBIN = 1'b1;

  localparam logic [11:0] DMA_REG_ADDR_A = 12'h000;
  localparam logic [11:0] DMA_REG_ADDR_B = 12'h004;
  localparam logic [11:0] DMA_REG_ADDR_C = 12'h008;
  localparam logic [11:0] DMA_REG_DIM_M = 12'h00C;
  localparam logic [11:0] DMA_REG_DIM_K = 12'h010;
  localparam logic [11:0] DMA_REG_DIM_N = 12'h014;
  localparam logic [11:0] DMA_REG_CONTROL = 12'h018;
  localparam logic [11:0] DMA_REG_STATUS = 12'h01C;

  localparam int DMA_CONTROL_START_BIT = 0;
  localparam int DMA_CONTROL_IRQ_EN_BIT = 1;
  localparam int DMA_STATUS_BUSY_BIT = 0;
  localparam int DMA_STATUS_DONE_BIT = 1;
  localparam int DMA_STATUS_ERROR_BIT = 2;

  localparam logic [15:0] ACCEL_OFF_CTRL = 16'h0000;
  localparam logic [15:0] ACCEL_OFF_STATUS = 16'h0004;
  localparam logic [15:0] ACCEL_OFF_DATA_IN = 16'h1000;
  localparam logic [15:0] ACCEL_OFF_DATA_OUT = 16'h2000;

  localparam int ACCEL_CTRL_MODE_BIT = 0;
  localparam int ACCEL_CTRL_LOAD_BIT = 1;
  localparam int ACCEL_CTRL_START_BIT = 2;
  localparam int ACCEL_CTRL_CLR_ERROR_BIT = 3;
  localparam int ACCEL_STATUS_DONE_BIT = 2;
  localparam int ACCEL_STATUS_ERROR_BIT = 3;

  localparam logic [1:0] ACCEL_STATE_IDLE = 2'b00;
  localparam logic [1:0] ACCEL_STATE_LOADING = 2'b01;
  localparam logic [1:0] ACCEL_STATE_PROCESSING = 2'b10;

  /* A region owns an address only if the offset also fits its size, so an access past the end of
     a region is reported instead of silently aliasing onto the start of the same region. */
  function automatic logic soc_in_region(input logic [AXIL_ADDR_WIDTH-1:0] addr,
                                         input logic [AXIL_ADDR_WIDTH-1:0] base,
                                         input int unsigned region_bytes);
    return (addr >= base) && ((addr - base) < region_bytes);
  endfunction

endpackage
