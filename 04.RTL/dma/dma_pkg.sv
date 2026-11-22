package dma_pkg;

    localparam logic [11:0] REG_ADDR_A  = 12'h000;
    localparam logic [11:0] REG_ADDR_B  = 12'h004;
    localparam logic [11:0] REG_ADDR_C  = 12'h008;
    localparam logic [11:0] REG_DIM_M   = 12'h00C;
    localparam logic [11:0] REG_DIM_K   = 12'h010;
    localparam logic [11:0] REG_DIM_N   = 12'h014;
    localparam logic [11:0] REG_CONTROL = 12'h018;
    localparam logic [11:0] REG_STATUS  = 12'h01C;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // Accelerator map, relative to its base (spec E1, section 6).
    localparam logic [31:0] ACC_CTRL     = 32'h0000;
    localparam logic [31:0] ACC_STATUS   = 32'h0004;
    localparam logic [31:0] ACC_DATA_IN  = 32'h1000;
    localparam logic [31:0] ACC_DATA_OUT = 32'h2000;

    // CTRL values written by the DMA: {CLR_ERROR, START, LOAD, MODE}.
    localparam logic [31:0] ACC_CMD_CLEAR = 32'h8;
    localparam logic [31:0] ACC_CMD_LOAD  = 32'h2;
    localparam logic [31:0] ACC_CMD_START = 32'h5;

    typedef enum logic [1:0] {
        SRC_A,
        SRC_B,
        SRC_C
    } src_e;

    typedef enum logic [3:0] {
        OP_SRC_READ,
        OP_IN_WRITE,
        OP_CMD_CLEAR,
        OP_CMD_LOAD,
        OP_CMD_START,
        OP_STATUS_READ,
        OP_OUT_READ,
        OP_C_READ,
        OP_C_WRITE
    } op_e;

endpackage
