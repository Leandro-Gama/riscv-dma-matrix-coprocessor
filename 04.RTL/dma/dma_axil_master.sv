// One transaction at a time: req_i is taken only in IDLE and done_o pulses with the response.
module dma_axil_master (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    input  logic        we_i,
    input  logic [31:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,
    output logic        done_o,
    output logic        err_o,
    output logic [31:0] rdata_o,

    output logic [31:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    typedef enum logic [2:0] {
        IDLE,
        WRITE,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t      state_q, state_d;
    logic [31:0] addr_q, wdata_q;
    logic [3:0]  wstrb_q;
    logic        aw_done_q, w_done_q;
    logic        aw_fire, w_fire;

    assign aw_fire = m_axi_awvalid && m_axi_awready;
    assign w_fire  = m_axi_wvalid && m_axi_wready;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= IDLE;
        else state_q <= state_d;
    end

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE:       if (req_i) state_d = we_i ? WRITE : READ_ADDR;
            WRITE:      if ((aw_done_q || aw_fire) && (w_done_q || w_fire)) state_d = WRITE_RESP;
            WRITE_RESP: if (m_axi_bvalid) state_d = IDLE;
            READ_ADDR:  if (m_axi_arready) state_d = READ_DATA;
            READ_DATA:  if (m_axi_rvalid) state_d = IDLE;
            default:    state_d = IDLE;
        endcase
    end

    always_comb begin
        m_axi_awvalid = state_q == WRITE && !aw_done_q;
        m_axi_wvalid  = state_q == WRITE && !w_done_q;
        m_axi_bready  = state_q == WRITE_RESP;
        m_axi_arvalid = state_q == READ_ADDR;
        m_axi_rready  = state_q == READ_DATA;
        done_o = (state_q == WRITE_RESP && m_axi_bvalid) || (state_q == READ_DATA && m_axi_rvalid);
        err_o  = (state_q == WRITE_RESP && m_axi_bresp != 2'b00) ||
                 (state_q == READ_DATA && m_axi_rresp != 2'b00);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            addr_q    <= '0;
            wdata_q   <= '0;
            wstrb_q   <= '0;
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
        end else begin
            if (state_q == IDLE && req_i) begin
                addr_q    <= addr_i;
                wdata_q   <= wdata_i;
                wstrb_q   <= wstrb_i;
                aw_done_q <= 1'b0;
                w_done_q  <= 1'b0;
            end
            if (aw_fire) aw_done_q <= 1'b1;
            if (w_fire) w_done_q <= 1'b1;
        end
    end

    assign m_axi_awaddr = addr_q;
    assign m_axi_araddr = addr_q;
    assign m_axi_wdata  = wdata_q;
    assign m_axi_wstrb  = wstrb_q;
    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;
    assign rdata_o      = m_axi_rdata;

endmodule
