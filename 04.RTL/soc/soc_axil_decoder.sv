/* One AXI4-Lite initiator to NUM_SLAVES targets. The initiator keeps one transaction at a time
   (spec E1, section 3). Addresses outside every region get DECERR from the decoder itself. */
module soc_axil_decoder #(
    parameter int                         NUM_SLAVES = 3,
    parameter logic [NUM_SLAVES-1:0][31:0] SLAVE_BASE = '0,
    parameter logic [NUM_SLAVES-1:0][31:0] SLAVE_SIZE = '0
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    input  logic [31:0]                  s_axi_awaddr,
    input  logic [2:0]                   s_axi_awprot,
    input  logic                         s_axi_awvalid,
    output logic                         s_axi_awready,
    input  logic [31:0]                  s_axi_wdata,
    input  logic [3:0]                   s_axi_wstrb,
    input  logic                         s_axi_wvalid,
    output logic                         s_axi_wready,
    output logic [1:0]                   s_axi_bresp,
    output logic                         s_axi_bvalid,
    input  logic                         s_axi_bready,
    input  logic [31:0]                  s_axi_araddr,
    input  logic [2:0]                   s_axi_arprot,
    input  logic                         s_axi_arvalid,
    output logic                         s_axi_arready,
    output logic [31:0]                  s_axi_rdata,
    output logic [1:0]                   s_axi_rresp,
    output logic                         s_axi_rvalid,
    input  logic                         s_axi_rready,

    output logic [NUM_SLAVES-1:0][31:0]  m_axi_awaddr,
    output logic [NUM_SLAVES-1:0][2:0]   m_axi_awprot,
    output logic [NUM_SLAVES-1:0]        m_axi_awvalid,
    input  logic [NUM_SLAVES-1:0]        m_axi_awready,
    output logic [NUM_SLAVES-1:0][31:0]  m_axi_wdata,
    output logic [NUM_SLAVES-1:0][3:0]   m_axi_wstrb,
    output logic [NUM_SLAVES-1:0]        m_axi_wvalid,
    input  logic [NUM_SLAVES-1:0]        m_axi_wready,
    input  logic [NUM_SLAVES-1:0][1:0]   m_axi_bresp,
    input  logic [NUM_SLAVES-1:0]        m_axi_bvalid,
    output logic [NUM_SLAVES-1:0]        m_axi_bready,
    output logic [NUM_SLAVES-1:0][31:0]  m_axi_araddr,
    output logic [NUM_SLAVES-1:0][2:0]   m_axi_arprot,
    output logic [NUM_SLAVES-1:0]        m_axi_arvalid,
    input  logic [NUM_SLAVES-1:0]        m_axi_arready,
    input  logic [NUM_SLAVES-1:0][31:0]  m_axi_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]   m_axi_rresp,
    input  logic [NUM_SLAVES-1:0]        m_axi_rvalid,
    output logic [NUM_SLAVES-1:0]        m_axi_rready
);
    localparam int SEL_W = $clog2(NUM_SLAVES + 1);
    localparam logic [SEL_W-1:0] NONE = SEL_W'(NUM_SLAVES);
    localparam logic [1:0] DECERR = 2'b11;

    logic             wr_active_q, rd_active_q, err_w_done_q, err_r_q;
    logic [SEL_W-1:0] wr_sel_q, rd_sel_q, aw_sel, ar_sel, wr_sel, rd_sel;
    logic             w_open;

    function automatic logic [SEL_W-1:0] decode(input logic [31:0] addr);
        decode = NONE;
        for (int i = NUM_SLAVES - 1; i >= 0; i--)
            if (addr >= SLAVE_BASE[i] && addr - SLAVE_BASE[i] < SLAVE_SIZE[i]) decode = SEL_W'(i);
    endfunction

    assign aw_sel = decode(s_axi_awaddr);
    assign ar_sel = decode(s_axi_araddr);
    assign wr_sel = wr_active_q ? wr_sel_q : aw_sel;
    assign rd_sel = rd_active_q ? rd_sel_q : ar_sel;
    // W is only forwarded once its address is known.
    assign w_open = wr_active_q || s_axi_awvalid;

    always_comb begin
        for (int i = 0; i < NUM_SLAVES; i++) begin
            m_axi_awaddr[i]  = s_axi_awaddr;
            m_axi_awprot[i]  = s_axi_awprot;
            m_axi_awvalid[i] = s_axi_awvalid && !wr_active_q && aw_sel == SEL_W'(i);
            m_axi_wdata[i]   = s_axi_wdata;
            m_axi_wstrb[i]   = s_axi_wstrb;
            m_axi_wvalid[i]  = s_axi_wvalid && w_open && wr_sel == SEL_W'(i);
            m_axi_bready[i]  = s_axi_bready && wr_active_q && wr_sel_q == SEL_W'(i);
            m_axi_araddr[i]  = s_axi_araddr;
            m_axi_arprot[i]  = s_axi_arprot;
            m_axi_arvalid[i] = s_axi_arvalid && !rd_active_q && ar_sel == SEL_W'(i);
            m_axi_rready[i]  = s_axi_rready && rd_active_q && rd_sel_q == SEL_W'(i);
        end

        if (aw_sel == NONE) s_axi_awready = !wr_active_q;
        else s_axi_awready = !wr_active_q && m_axi_awready[aw_sel];

        if (wr_sel == NONE) s_axi_wready = w_open && !err_w_done_q;
        else s_axi_wready = w_open && m_axi_wready[wr_sel];

        s_axi_bvalid = 1'b0;
        s_axi_bresp  = DECERR;
        if (wr_active_q) begin
            if (wr_sel_q == NONE) begin
                s_axi_bvalid = err_w_done_q;
            end else begin
                s_axi_bvalid = m_axi_bvalid[wr_sel_q];
                s_axi_bresp  = m_axi_bresp[wr_sel_q];
            end
        end

        if (ar_sel == NONE) s_axi_arready = !rd_active_q;
        else s_axi_arready = !rd_active_q && m_axi_arready[ar_sel];

        s_axi_rvalid = 1'b0;
        s_axi_rdata  = '0;
        s_axi_rresp  = DECERR;
        if (rd_active_q) begin
            if (rd_sel_q == NONE) begin
                s_axi_rvalid = err_r_q;
            end else begin
                s_axi_rvalid = m_axi_rvalid[rd_sel_q];
                s_axi_rdata  = m_axi_rdata[rd_sel_q];
                s_axi_rresp  = m_axi_rresp[rd_sel_q];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_active_q  <= 1'b0;
            wr_sel_q     <= NONE;
            err_w_done_q <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                wr_active_q <= 1'b1;
                wr_sel_q    <= aw_sel;
            end
            if (s_axi_wvalid && s_axi_wready && wr_sel == NONE) err_w_done_q <= 1'b1;
            if (s_axi_bvalid && s_axi_bready) begin
                wr_active_q  <= 1'b0;
                err_w_done_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_active_q <= 1'b0;
            rd_sel_q    <= NONE;
            err_r_q     <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_active_q <= 1'b1;
                rd_sel_q    <= ar_sel;
                err_r_q     <= ar_sel == NONE;
            end
            if (s_axi_rvalid && s_axi_rready) begin
                rd_active_q <= 1'b0;
                err_r_q     <= 1'b0;
            end
        end
    end

endmodule
