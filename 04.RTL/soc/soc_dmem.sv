// Shared data memory, AXI4-Lite target. No initial contents: the testbench loads mem_q.
module soc_dmem #(
    parameter logic [31:0] BASE  = 32'h1000_0000,
    parameter int          BYTES = 16384
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);
    localparam int WORDS  = BYTES / 4;
    localparam int INDEX_W = $clog2(WORDS);

    logic [31:0] mem_q [WORDS];

    logic              aw_pending_q, w_pending_q;
    logic [31:0]       awaddr_q, wdata_q;
    logic [3:0]        wstrb_q;
    logic              write_commit, write_hit, read_hit;
    logic [31:0]       write_offset, read_offset;
    logic [INDEX_W-1:0] write_index, read_index;

    assign write_offset = awaddr_q - BASE;
    assign read_offset  = s_axi_araddr - BASE;
    assign write_hit    = awaddr_q >= BASE && write_offset < BYTES;
    assign read_hit     = s_axi_araddr >= BASE && read_offset < BYTES;
    assign write_index  = write_offset[INDEX_W+1:2];
    assign read_index   = read_offset[INDEX_W+1:2];
    assign write_commit = aw_pending_q && w_pending_q;

    assign s_axi_awready = !aw_pending_q && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending_q && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q <= 1'b0;
            w_pending_q  <= 1'b0;
            awaddr_q     <= '0;
            wdata_q      <= '0;
            wstrb_q      <= '0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending_q <= 1'b1;
                awaddr_q     <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending_q <= 1'b1;
                wdata_q     <= s_axi_wdata;
                wstrb_q     <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (write_commit) begin
                aw_pending_q <= 1'b0;
                w_pending_q  <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= write_hit ? 2'b00 : 2'b10;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (write_commit && write_hit) begin
            for (int lane = 0; lane < 4; lane++)
                if (wstrb_q[lane]) mem_q[write_index][8*lane +: 8] <= wdata_q[8*lane +: 8];
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
            s_axi_rresp  <= 2'b00;
        end else begin
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= read_hit ? mem_q[read_index] : '0;
                s_axi_rresp  <= read_hit ? 2'b00 : 2'b10;
            end
        end
    end

endmodule
