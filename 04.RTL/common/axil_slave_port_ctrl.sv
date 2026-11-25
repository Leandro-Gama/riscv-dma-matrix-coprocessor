module axil_slave_port_ctrl (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic s_axi_rvalid,
    input  logic s_axi_rready,

    output logic cap_aw_o,
    output logic cap_w_o,
    output logic cap_ar_o,
    output logic cap_rsp_o,

    output logic req_o,
    output logic we_o,
    input  logic ack_i
);

  typedef enum logic [2:0] {
    IDLE,
    W_WAIT_DATA,
    W_WAIT_ADDR,
    W_ACCESS,
    W_RESP,
    R_ACCESS,
    R_RESP
  } state_e;

  state_e state_q, state_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      IDLE: begin
        if (s_axi_awvalid && s_axi_wvalid) begin
          state_d = W_ACCESS;
        end else if (s_axi_awvalid) begin
          state_d = W_WAIT_DATA;
        end else if (s_axi_wvalid) begin
          state_d = W_WAIT_ADDR;
        end else if (s_axi_arvalid) begin
          state_d = R_ACCESS;
        end
      end
      W_WAIT_DATA: if (s_axi_wvalid) state_d = W_ACCESS;
      W_WAIT_ADDR: if (s_axi_awvalid) state_d = W_ACCESS;
      W_ACCESS: if (ack_i) state_d = W_RESP;
      W_RESP: if (s_axi_bready) state_d = IDLE;
      R_ACCESS: if (ack_i) state_d = R_RESP;
      R_RESP: if (s_axi_rready) state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

  always_comb begin
    s_axi_awready = 1'b0;
    s_axi_wready = 1'b0;
    s_axi_bvalid = 1'b0;
    s_axi_arready = 1'b0;
    s_axi_rvalid = 1'b0;
    cap_aw_o = 1'b0;
    cap_w_o = 1'b0;
    cap_ar_o = 1'b0;
    cap_rsp_o = 1'b0;
    req_o = 1'b0;
    we_o = 1'b0;

    unique case (state_q)
      IDLE: begin
        s_axi_awready = 1'b1;
        s_axi_wready = 1'b1;
        /* Only one access is held at a time, so a read is taken only when no write is starting.
           READY is allowed to depend on VALID, while VALID never waits for READY. */
        s_axi_arready = !s_axi_awvalid && !s_axi_wvalid;
        cap_aw_o = s_axi_awvalid;
        cap_w_o = s_axi_wvalid;
        cap_ar_o = s_axi_arvalid && !s_axi_awvalid && !s_axi_wvalid;
      end
      W_WAIT_DATA: begin
        s_axi_wready = 1'b1;
        cap_w_o = s_axi_wvalid;
      end
      W_WAIT_ADDR: begin
        s_axi_awready = 1'b1;
        cap_aw_o = s_axi_awvalid;
      end
      W_ACCESS: begin
        req_o = 1'b1;
        we_o = 1'b1;
        cap_rsp_o = ack_i;
      end
      W_RESP: s_axi_bvalid = 1'b1;
      R_ACCESS: begin
        req_o = 1'b1;
        cap_rsp_o = ack_i;
      end
      R_RESP: s_axi_rvalid = 1'b1;
      default: ;
    endcase
  end

endmodule
