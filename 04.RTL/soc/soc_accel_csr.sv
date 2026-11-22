// CTRL/STATUS of the accelerator (02.Architecture/icd/csr_readme.md).
// MODE and the command pulses are registered together, so the new MODE is valid in the pulse cycle.
module soc_accel_csr (
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

    output logic        mode_o,
    output logic        load_o,
    output logic        start_o,
    output logic        clr_error_o,
    input  logic [31:0] status_i
);
    localparam logic [11:0] CTRL   = 12'h000;
    localparam logic [11:0] STATUS = 12'h004;

    logic        aw_pending_q, w_pending_q;
    logic [11:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        write_commit, ctrl_write;
    logic        mode_q, load_q, start_q, clr_error_q;

    assign write_commit = aw_pending_q && w_pending_q;
    assign ctrl_write   = write_commit && awaddr_q == CTRL;

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
                s_axi_bresp  <= ctrl_write ? 2'b00 : 2'b10;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mode_q      <= 1'b0;
            load_q      <= 1'b0;
            start_q     <= 1'b0;
            clr_error_q <= 1'b0;
        end else begin
            load_q      <= 1'b0;
            start_q     <= 1'b0;
            clr_error_q <= 1'b0;
            if (ctrl_write && wstrb_q[0]) begin
                mode_q      <= wdata_q[0];
                load_q      <= wdata_q[1];
                start_q     <= wdata_q[2];
                clr_error_q <= wdata_q[3];
            end
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
                s_axi_rresp  <= 2'b00;
                unique case (s_axi_araddr[11:0])
                    CTRL:   s_axi_rdata <= {31'b0, mode_q};
                    STATUS: s_axi_rdata <= status_i;
                    default: begin
                        s_axi_rdata <= '0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end
        end
    end

    assign mode_o      = mode_q;
    assign load_o      = load_q;
    assign start_o     = start_q;
    assign clr_error_o = clr_error_q;

endmodule
