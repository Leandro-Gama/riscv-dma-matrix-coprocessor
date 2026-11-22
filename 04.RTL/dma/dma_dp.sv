module dma_dp #(
    parameter int          ARRAY_SIZE = 2,
    parameter int          DATA_WIDTH = 8,
    parameter logic [31:0] ACCEL_BASE = 32'h4000_0000
) (
    input  logic            clk_i,
    input  logic            rst_ni,

    input  logic [31:0]     addr_a_i,
    input  logic [31:0]     addr_b_i,
    input  logic [31:0]     addr_c_i,
    input  logic [31:0]     dim_m_i,
    input  logic [31:0]     dim_k_i,
    input  logic [31:0]     dim_n_i,

    input  logic            op_init_i,
    input  logic            setup_i,
    input  dma_pkg::src_e   src_i,
    input  logic            elem_next_i,
    input  logic            word_capture_i,
    input  logic            word_clear_i,
    input  logic            out_capture_i,
    input  logic            c_capture_i,
    input  logic            m_next_i,
    input  logic            k_next_i,
    input  logic            n_next_i,
    input  dma_pkg::op_e    op_i,

    output logic            dims_zero_o,
    output logic            src_b_o,
    output logic            elem_valid_o,
    output logic            lane_last_o,
    output logic            elem_last_o,
    output logic            m_last_o,
    output logic            k_last_o,
    output logic            n_last_o,
    output logic            k_first_o,
    output logic            acc_done_o,
    output logic            acc_error_o,

    output logic            bus_we_o,
    output logic [31:0]     bus_addr_o,
    output logic [31:0]     bus_wdata_o,
    output logic [3:0]      bus_wstrb_o,
    input  logic [31:0]     bus_rdata_i
);
    import dma_pkg::*;

    localparam int BYTES    = DATA_WIDTH / 8;
    localparam int EPW      = 32 / DATA_WIDTH;
    localparam int LOG_N    = $clog2(ARRAY_SIZE);
    localparam int LOG_B    = $clog2(BYTES);
    localparam int LOG_EPW  = $clog2(EPW);
    localparam int ELEM_W   = 2 * LOG_N;
    localparam int TILE_LEN = ARRAY_SIZE * ARRAY_SIZE;
    localparam logic [3:0] ELEM_STRB = 4'((1 << BYTES) - 1);

    if (!(ARRAY_SIZE == 2 || ARRAY_SIZE == 4 || ARRAY_SIZE == 8)) begin : gen_invalid_size
        DMA_ARRAY_SIZE_MUST_BE_2_4_OR_8 invalid_parameter();
    end
    if (!(DATA_WIDTH == 8 || DATA_WIDTH == 16 || DATA_WIDTH == 32)) begin : gen_invalid_width
        DMA_DATA_WIDTH_MUST_BE_8_16_OR_32 invalid_parameter();
    end

    logic [31:0]           m0_q, k0_q, n0_q;
    logic [31:0]           a_row_q, b_row_q, c_row_q;
    logic [31:0]           row_ptr_q, stride_q, rows_left_q, cols_left_q;
    src_e                  src_q;
    logic [ELEM_W-1:0]     elem_q;
    logic [31:0]           word_q;
    logic [DATA_WIDTH-1:0] out_q;

    logic [31:0]           stride_a, stride_c;
    logic [31:0]           setup_base, setup_stride, setup_rows, setup_cols;
    logic [LOG_N-1:0]      row, col;
    logic [31:0]           elem_addr, word_offset;
    logic [1:0]            lane_byte;

    function automatic logic [DATA_WIDTH-1:0] pick(input logic [31:0] word, input logic [1:0] byte_off);
        logic [31:0] shifted;
        shifted = word >> {byte_off, 3'b000};
        return shifted[DATA_WIDTH-1:0];
    endfunction

    // Rows of A have K elements; rows of B and C have N elements.
    assign stride_a = dim_k_i << LOG_B;
    assign stride_c = dim_n_i << LOG_B;

    assign row         = elem_q[ELEM_W-1:LOG_N];
    assign col         = elem_q[LOG_N-1:0];
    assign elem_addr   = row_ptr_q + (32'(col) << LOG_B);
    assign word_offset = (32'(elem_q) >> LOG_EPW) << 2;
    assign lane_byte   = 2'((int'(elem_q) % EPW) * BYTES);

    always_comb begin
        unique case (src_i)
            SRC_A: begin
                setup_base   = a_row_q + (k0_q << LOG_B);
                setup_stride = stride_a;
                setup_rows   = dim_m_i - m0_q;
                setup_cols   = dim_k_i - k0_q;
            end
            SRC_B: begin
                setup_base   = b_row_q + (n0_q << LOG_B);
                setup_stride = stride_c;
                setup_rows   = dim_k_i - k0_q;
                setup_cols   = dim_n_i - n0_q;
            end
            default: begin
                setup_base   = c_row_q + (n0_q << LOG_B);
                setup_stride = stride_c;
                setup_rows   = dim_m_i - m0_q;
                setup_cols   = dim_n_i - n0_q;
            end
        endcase
    end

    // Tile loop: n outer, k middle, m inner, so a B tile stays loaded while the A tiles pass.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            m0_q    <= '0;
            k0_q    <= '0;
            n0_q    <= '0;
            a_row_q <= '0;
            b_row_q <= '0;
            c_row_q <= '0;
        end else if (op_init_i) begin
            m0_q    <= '0;
            k0_q    <= '0;
            n0_q    <= '0;
            a_row_q <= addr_a_i;
            b_row_q <= addr_b_i;
            c_row_q <= addr_c_i;
        end else if (m_next_i) begin
            m0_q    <= m0_q + ARRAY_SIZE;
            a_row_q <= a_row_q + (stride_a << LOG_N);
            c_row_q <= c_row_q + (stride_c << LOG_N);
        end else if (k_next_i) begin
            m0_q    <= '0;
            k0_q    <= k0_q + ARRAY_SIZE;
            a_row_q <= addr_a_i;
            c_row_q <= addr_c_i;
            b_row_q <= b_row_q + (stride_c << LOG_N);
        end else if (n_next_i) begin
            m0_q    <= '0;
            k0_q    <= '0;
            n0_q    <= n0_q + ARRAY_SIZE;
            a_row_q <= addr_a_i;
            b_row_q <= addr_b_i;
            c_row_q <= addr_c_i;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            src_q       <= SRC_A;
            elem_q      <= '0;
            row_ptr_q   <= '0;
            stride_q    <= '0;
            rows_left_q <= '0;
            cols_left_q <= '0;
        end else if (setup_i) begin
            src_q       <= src_i;
            elem_q      <= '0;
            row_ptr_q   <= setup_base;
            stride_q    <= setup_stride;
            rows_left_q <= setup_rows;
            cols_left_q <= setup_cols;
        end else if (elem_next_i) begin
            elem_q <= elem_q + 1'b1;
            if (col == LOG_N'(ARRAY_SIZE - 1)) row_ptr_q <= row_ptr_q + stride_q;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            word_q <= '0;
            out_q  <= '0;
        end else begin
            if (setup_i || word_clear_i) word_q <= '0;
            else if (word_capture_i)
                word_q[(int'(elem_q) % EPW)*DATA_WIDTH +: DATA_WIDTH] <= pick(bus_rdata_i, elem_addr[1:0]);
            if (out_capture_i) out_q <= pick(bus_rdata_i, lane_byte);
            else if (c_capture_i) out_q <= out_q + pick(bus_rdata_i, elem_addr[1:0]);
        end
    end

    always_comb begin
        bus_we_o    = 1'b0;
        bus_addr_o  = elem_addr;
        bus_wdata_o = '0;
        bus_wstrb_o = 4'hF;
        unique case (op_i)
            OP_SRC_READ, OP_C_READ: bus_addr_o = elem_addr;
            OP_IN_WRITE: begin
                bus_we_o    = 1'b1;
                bus_addr_o  = ACCEL_BASE + ACC_DATA_IN + word_offset;
                bus_wdata_o = word_q;
            end
            OP_CMD_CLEAR, OP_CMD_LOAD, OP_CMD_START: begin
                bus_we_o    = 1'b1;
                bus_addr_o  = ACCEL_BASE + ACC_CTRL;
                bus_wdata_o = op_i == OP_CMD_CLEAR ? ACC_CMD_CLEAR :
                              op_i == OP_CMD_LOAD  ? ACC_CMD_LOAD : ACC_CMD_START;
            end
            OP_STATUS_READ: bus_addr_o = ACCEL_BASE + ACC_STATUS;
            OP_OUT_READ:    bus_addr_o = ACCEL_BASE + ACC_DATA_OUT + word_offset;
            OP_C_WRITE: begin
                // The element is replicated on every lane and WSTRB picks the right bytes.
                bus_we_o    = 1'b1;
                bus_addr_o  = elem_addr;
                bus_wdata_o = {EPW{out_q}};
                bus_wstrb_o = ELEM_STRB << elem_addr[1:0];
            end
            default: ;
        endcase
    end

    assign dims_zero_o  = dim_m_i == 0 || dim_k_i == 0 || dim_n_i == 0;
    assign src_b_o      = src_q == SRC_B;
    assign elem_valid_o = 32'(row) < rows_left_q && 32'(col) < cols_left_q;
    assign lane_last_o  = (int'(elem_q) % EPW) == EPW - 1;
    assign elem_last_o  = int'(elem_q) == TILE_LEN - 1;
    assign m_last_o     = dim_m_i - m0_q <= ARRAY_SIZE;
    assign k_last_o     = dim_k_i - k0_q <= ARRAY_SIZE;
    assign n_last_o     = dim_n_i - n0_q <= ARRAY_SIZE;
    assign k_first_o    = k0_q == 0;
    assign acc_done_o   = bus_rdata_i[2] && bus_rdata_i[1:0] == 2'b00;
    assign acc_error_o  = bus_rdata_i[3];

endmodule
