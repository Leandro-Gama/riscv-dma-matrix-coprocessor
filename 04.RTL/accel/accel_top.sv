module accel_top #(
    parameter int N = 2,
    parameter int DATA_WIDTH = 8,
    parameter logic [31:0] DATA_IN_BASE = 32'h4000_1000,
    parameter logic [31:0] DATA_OUT_BASE = 32'h4000_2000
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic mode_i,
    input  logic load_i,
    input  logic start_i,
    input  logic clr_error_i,
    output wire [31:0] status_o,
    axil_if.target s_axi
);
    localparam int BUFFER_BYTES = N * N * DATA_WIDTH / 8;
    localparam int BUFFER_WORDS = BUFFER_BYTES / 4;
    localparam int WORD_INDEX_WIDTH = (BUFFER_WORDS > 1) ? $clog2(BUFFER_WORDS) : 1;
    localparam logic [1:0] RESP_OKAY = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic [BUFFER_WORDS-1:0][31:0] input_q;
    wire [N*N-1:0][DATA_WIDTH-1:0] output_data;
    wire [BUFFER_WORDS-1:0][31:0] output_words;
    logic aw_pending_q, w_pending_q;
    logic [31:0] awaddr_q, wdata_q;
    logic [3:0] wstrb_q;
    wire write_commit, write_allowed, read_allowed;
    wire [31:0] write_offset, read_offset;
    wire [WORD_INDEX_WIDTH-1:0] write_index, read_index;

    if ($bits(s_axi.wdata) != 32 || $bits(s_axi.awaddr) != 32 ||
        $bits(s_axi.araddr) != 32 || $bits(s_axi.rdata) != 32) begin : gen_invalid_axi
        ACCEL_AXI_REQUIRES_32_BIT_ADDRESS_AND_DATA invalid_parameter();
    end

    assign output_words = output_data;
    assign write_offset = awaddr_q - DATA_IN_BASE;
    assign read_offset = s_axi.araddr - DATA_OUT_BASE;
    assign write_index = WORD_INDEX_WIDTH'(write_offset >> 2);
    assign read_index = WORD_INDEX_WIDTH'(read_offset >> 2);
    assign write_commit = aw_pending_q && w_pending_q && !s_axi.bvalid;
    assign write_allowed = awaddr_q[1:0] == 2'b00 &&
                           awaddr_q >= DATA_IN_BASE && write_offset < BUFFER_BYTES &&
                           status_o[1:0] == 2'b00;
    assign read_allowed = s_axi.araddr[1:0] == 2'b00 &&
                          s_axi.araddr >= DATA_OUT_BASE && read_offset < BUFFER_BYTES;
    assign s_axi.awready = rst_ni && !aw_pending_q && !s_axi.bvalid;
    assign s_axi.wready = rst_ni && !w_pending_q && !s_axi.bvalid;
    assign s_axi.arready = rst_ni && !s_axi.rvalid;

    accel_systolic #(.N(N), .DATA_WIDTH(DATA_WIDTH)) u_systolic (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .mode_i(mode_i),
        .load_i(load_i),
        .start_i(start_i),
        .clr_error_i(clr_error_i),
        .data_i(input_q),
        .data_o(output_data),
        .status_o(status_o)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q <= 1'b0;
            w_pending_q <= 1'b0;
            awaddr_q <= '0;
            wdata_q <= '0;
            wstrb_q <= '0;
            s_axi.bvalid <= 1'b0;
            s_axi.bresp <= RESP_OKAY;
        end else begin
            if (s_axi.awvalid && s_axi.awready) begin
                aw_pending_q <= 1'b1;
                awaddr_q <= s_axi.awaddr;
            end
            if (s_axi.wvalid && s_axi.wready) begin
                w_pending_q <= 1'b1;
                wdata_q <= s_axi.wdata;
                wstrb_q <= s_axi.wstrb;
            end
            if (s_axi.bvalid && s_axi.bready) s_axi.bvalid <= 1'b0;
            if (write_commit) begin
                aw_pending_q <= 1'b0;
                w_pending_q <= 1'b0;
                s_axi.bvalid <= 1'b1;
                s_axi.bresp <= write_allowed ? RESP_OKAY : RESP_SLVERR;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) input_q <= '0;
        else if (write_commit && write_allowed) begin
            for (int lane = 0; lane < 4; lane++) begin
                if (wstrb_q[lane]) input_q[write_index][8*lane +: 8] <= wdata_q[8*lane +: 8];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi.rvalid <= 1'b0;
            s_axi.rdata <= '0;
            s_axi.rresp <= RESP_OKAY;
        end else begin
            if (s_axi.rvalid && s_axi.rready) s_axi.rvalid <= 1'b0;
            if (s_axi.arvalid && s_axi.arready) begin
                s_axi.rvalid <= 1'b1;
                s_axi.rdata <= read_allowed ? output_words[read_index] : '0;
                s_axi.rresp <= read_allowed ? RESP_OKAY : RESP_SLVERR;
            end
        end
    end
endmodule
