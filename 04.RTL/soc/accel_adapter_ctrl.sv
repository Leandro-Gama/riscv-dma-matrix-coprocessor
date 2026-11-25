/* A register access is answered in the cycle it is seen; a buffer access is handed to the
   accelerator shell and waits for it. The shell may take as long as it wants, so there is no
   timeout here: the master waits on the bus. */
module accel_adapter_ctrl (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic req_i,
    input  logic is_buf_i,
    input  logic bad_i,
    input  logic shell_ready_i,

    output logic ack_o,
    output logic data_req_o
);

  typedef enum logic [0:0] {
    IDLE,
    BUF
  } state_e;

  state_e state_q, state_d;

  logic to_shell;

  assign to_shell = req_i && is_buf_i && !bad_i;

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
      IDLE: if (to_shell && !shell_ready_i) state_d = BUF;
      BUF: if (shell_ready_i) state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

  always_comb begin
    ack_o = 1'b0;
    data_req_o = 1'b0;

    unique case (state_q)
      IDLE: begin
        if (to_shell) begin
          /* The request goes out in the same cycle the access is seen, so the shell does not pay
             an extra cycle just to be asked. */
          data_req_o = 1'b1;
          ack_o = shell_ready_i;
        end else if (req_i) begin
          ack_o = 1'b1;
        end
      end
      BUF: begin
        data_req_o = 1'b1;
        ack_o = shell_ready_i;
      end
      default: ;
    endcase
  end

endmodule
