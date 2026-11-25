module axil_master_port_ctrl (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic req_i,
    input  logic we_i,
    output logic ack_o,

    output logic s_axi_awvalid,
    input  logic s_axi_awready,
    output logic s_axi_wvalid,
    input  logic s_axi_wready,
    input  logic s_axi_bvalid,
    output logic s_axi_bready,
    output logic s_axi_arvalid,
    input  logic s_axi_arready,
    input  logic s_axi_rvalid,
    output logic s_axi_rready,

    output logic cap_req_o,
    output logic resp_sel_wr_o
);

  typedef enum logic [2:0] {
    IDLE,
    W_ADDR_DATA,
    W_RESP,
    R_ADDR,
    R_DATA
  } state_e;

  state_e state_q, state_d;

  logic aw_done_q, w_done_q;
  logic aw_fire, w_fire, aw_ok, w_ok;

  assign aw_fire = s_axi_awvalid && s_axi_awready;
  assign w_fire = s_axi_wvalid && s_axi_wready;
  assign aw_ok = aw_done_q || aw_fire;
  assign w_ok = w_done_q || w_fire;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  /* The address and data channels of a write are independent, so each one is remembered until
     both have been accepted. */
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_done_q <= 1'b0;
      w_done_q <= 1'b0;
    end else if (state_q != W_ADDR_DATA) begin
      aw_done_q <= 1'b0;
      w_done_q <= 1'b0;
    end else begin
      aw_done_q <= aw_ok;
      w_done_q <= w_ok;
    end
  end

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      IDLE: begin
        if (req_i) state_d = we_i ? W_ADDR_DATA : R_ADDR;
      end
      W_ADDR_DATA: if (aw_ok && w_ok) state_d = W_RESP;
      W_RESP: if (s_axi_bvalid) state_d = IDLE;
      R_ADDR: if (s_axi_arready) state_d = R_DATA;
      R_DATA: if (s_axi_rvalid) state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

  always_comb begin
    s_axi_awvalid = 1'b0;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b0;
    s_axi_arvalid = 1'b0;
    s_axi_rready = 1'b0;
    cap_req_o = 1'b0;
    resp_sel_wr_o = 1'b0;
    ack_o = 1'b0;

    unique case (state_q)
      IDLE: cap_req_o = req_i;
      W_ADDR_DATA: begin
        // VALID never waits for READY: it drops only once its own channel has been accepted.
        s_axi_awvalid = !aw_done_q;
        s_axi_wvalid = !w_done_q;
      end
      W_RESP: begin
        s_axi_bready = 1'b1;
        resp_sel_wr_o = 1'b1;
        ack_o = s_axi_bvalid;
      end
      R_ADDR: s_axi_arvalid = 1'b1;
      R_DATA: begin
        s_axi_rready = 1'b1;
        ack_o = s_axi_rvalid;
      end
      default: ;
    endcase
  end

endmodule
