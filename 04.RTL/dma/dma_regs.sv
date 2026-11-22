module dma_regs (
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
    input  logic        s_axi_rready,

    input  logic        busy_i,
    input  logic        finish_i,
    input  logic        error_i,
    output logic        start_o,
    output logic [31:0] addr_a_o,
    output logic [31:0] addr_b_o,
    output logic [31:0] addr_c_o,
    output logic [31:0] dim_m_o,
    output logic [31:0] dim_k_o,
    output logic [31:0] dim_n_o,
    output logic        irq_o
);
    import dma_pkg::*;

    logic        aw_pending_q, w_pending_q;
    logic [11:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        write_commit, write_ok, accept_start, busy;
    logic [1:0]  write_resp, read_resp;
    logic [31:0] read_data;
    logic [31:0] addr_a_q, addr_b_q, addr_c_q, dim_m_q, dim_k_q, dim_n_q;
    logic        irq_en_q, done_q, error_q, start_q;

    function automatic logic [31:0] merge(input logic [31:0] old, data, input logic [3:0] strb);
        for (int lane = 0; lane < 4; lane++)
            merge[8*lane +: 8] = strb[lane] ? data[8*lane +: 8] : old[8*lane +: 8];
    endfunction

    // start_q covers the cycle between the START write and the FSM leaving IDLE.
    assign busy = busy_i || start_q;

    assign s_axi_awready = !aw_pending_q && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending_q && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    assign write_commit = aw_pending_q && w_pending_q;
    assign write_ok     = write_commit && write_resp == RESP_OKAY;
    assign accept_start = write_ok && awaddr_q == REG_CONTROL && wstrb_q[0] && wdata_q[0] && !busy;

    always_comb begin
        write_resp = RESP_OKAY;
        if (awaddr_q[1:0] != 2'b00) begin
            write_resp = RESP_SLVERR;
        end else begin
            unique case (awaddr_q)
                REG_ADDR_A, REG_ADDR_B, REG_ADDR_C,
                REG_DIM_M, REG_DIM_K, REG_DIM_N: if (busy) write_resp = RESP_SLVERR;
                REG_CONTROL: write_resp = RESP_OKAY;
                default: write_resp = RESP_SLVERR;
            endcase
        end
    end

    always_comb begin
        read_data = '0;
        read_resp = RESP_OKAY;
        if (s_axi_araddr[1:0] != 2'b00) begin
            read_resp = RESP_SLVERR;
        end else begin
            unique case (s_axi_araddr[11:0])
                REG_ADDR_A:  read_data = addr_a_q;
                REG_ADDR_B:  read_data = addr_b_q;
                REG_ADDR_C:  read_data = addr_c_q;
                REG_DIM_M:   read_data = dim_m_q;
                REG_DIM_K:   read_data = dim_k_q;
                REG_DIM_N:   read_data = dim_n_q;
                REG_CONTROL: read_data = {30'b0, irq_en_q, 1'b0};
                REG_STATUS:  read_data = {29'b0, error_q, done_q, busy};
                default:     read_resp = RESP_SLVERR;
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q <= 1'b0;
            w_pending_q  <= 1'b0;
            awaddr_q     <= '0;
            wdata_q      <= '0;
            wstrb_q      <= '0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending_q <= 1'b1;
                awaddr_q     <= s_axi_awaddr[11:0];
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
                s_axi_bresp  <= write_resp;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            addr_a_q <= '0;
            addr_b_q <= '0;
            addr_c_q <= '0;
            dim_m_q  <= '0;
            dim_k_q  <= '0;
            dim_n_q  <= '0;
            irq_en_q <= 1'b0;
        end else if (write_ok) begin
            unique case (awaddr_q)
                REG_ADDR_A:  addr_a_q <= merge(addr_a_q, wdata_q, wstrb_q);
                REG_ADDR_B:  addr_b_q <= merge(addr_b_q, wdata_q, wstrb_q);
                REG_ADDR_C:  addr_c_q <= merge(addr_c_q, wdata_q, wstrb_q);
                REG_DIM_M:   dim_m_q  <= merge(dim_m_q, wdata_q, wstrb_q);
                REG_DIM_K:   dim_k_q  <= merge(dim_k_q, wdata_q, wstrb_q);
                REG_DIM_N:   dim_n_q  <= merge(dim_n_q, wdata_q, wstrb_q);
                REG_CONTROL: if (wstrb_q[0]) irq_en_q <= wdata_q[1];
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            start_q <= 1'b0;
            done_q  <= 1'b0;
            error_q <= 1'b0;
        end else begin
            start_q <= accept_start;
            if (accept_start) begin
                done_q  <= 1'b0;
                error_q <= 1'b0;
            end else if (finish_i) begin
                done_q  <= 1'b1;
                error_q <= error_i;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
            s_axi_rresp  <= RESP_OKAY;
        end else begin
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= read_data;
                s_axi_rresp  <= read_resp;
            end
        end
    end

    assign start_o  = start_q;
    assign addr_a_o = addr_a_q;
    assign addr_b_o = addr_b_q;
    assign addr_c_o = addr_c_q;
    assign dim_m_o  = dim_m_q;
    assign dim_k_o  = dim_k_q;
    assign dim_n_o  = dim_n_q;
    assign irq_o    = done_q && irq_en_q;

endmodule
