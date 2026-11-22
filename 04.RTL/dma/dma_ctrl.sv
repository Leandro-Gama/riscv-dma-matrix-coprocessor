module dma_ctrl (
    input  logic          clk_i,
    input  logic          rst_ni,

    input  logic          start_i,
    output logic          busy_o,
    output logic          finish_o,
    output logic          error_o,

    input  logic          dims_zero_i,
    input  logic          src_b_i,
    input  logic          elem_valid_i,
    input  logic          lane_last_i,
    input  logic          elem_last_i,
    input  logic          m_last_i,
    input  logic          k_last_i,
    input  logic          n_last_i,
    input  logic          k_first_i,
    input  logic          acc_done_i,
    input  logic          acc_error_i,

    output logic          op_init_o,
    output logic          setup_o,
    output dma_pkg::src_e src_o,
    output logic          elem_next_o,
    output logic          word_capture_o,
    output logic          word_clear_o,
    output logic          out_capture_o,
    output logic          c_capture_o,
    output logic          m_next_o,
    output logic          k_next_o,
    output logic          n_next_o,
    output dma_pkg::op_e  op_o,

    output logic          bus_req_o,
    input  logic          bus_done_i,
    input  logic          bus_err_i
);
    import dma_pkg::*;

    typedef enum logic [4:0] {
        IDLE,
        INIT,
        CLEAR,
        SETUP_B,
        SETUP_A,
        GATHER,
        IN_WRITE,
        LOAD,
        START,
        POLL,
        SETUP_C,
        OUT_READ,
        C_READ,
        C_WRITE,
        NEXT_TILE,
        FINISH,
        FAIL
    } state_t;

    state_t state_q, state_d;
    logic   ok, gather_step;

    assign ok = bus_done_i && !bus_err_i;
    // Padding elements are not read: their lane stays zero in the word being built.
    assign gather_step = elem_valid_i ? ok : 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= IDLE;
        else state_q <= state_d;
    end

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE: if (start_i) state_d = INIT;
            INIT: state_d = dims_zero_i ? FAIL : CLEAR;
            CLEAR: if (bus_done_i) state_d = bus_err_i ? FAIL : SETUP_B;
            SETUP_B, SETUP_A: state_d = GATHER;
            GATHER: begin
                if (elem_valid_i && bus_done_i && bus_err_i) state_d = FAIL;
                else if (gather_step && lane_last_i) state_d = IN_WRITE;
            end
            IN_WRITE: begin
                if (bus_done_i) begin
                    if (bus_err_i) state_d = FAIL;
                    else if (!elem_last_i) state_d = GATHER;
                    else state_d = src_b_i ? LOAD : START;
                end
            end
            LOAD, START: if (bus_done_i) state_d = bus_err_i ? FAIL : POLL;
            POLL: begin
                if (bus_done_i) begin
                    if (bus_err_i || acc_error_i) state_d = FAIL;
                    else if (acc_done_i) state_d = src_b_i ? SETUP_A : SETUP_C;
                end
            end
            SETUP_C: state_d = OUT_READ;
            OUT_READ: begin
                if (!elem_valid_i) begin
                    if (elem_last_i) state_d = NEXT_TILE;
                end else if (bus_done_i) begin
                    if (bus_err_i) state_d = FAIL;
                    else state_d = k_first_i ? C_WRITE : C_READ;
                end
            end
            C_READ: if (bus_done_i) state_d = bus_err_i ? FAIL : C_WRITE;
            C_WRITE: begin
                if (bus_done_i) begin
                    if (bus_err_i) state_d = FAIL;
                    else state_d = elem_last_i ? NEXT_TILE : OUT_READ;
                end
            end
            NEXT_TILE: begin
                if (!m_last_i) state_d = SETUP_A;
                else if (!k_last_i || !n_last_i) state_d = SETUP_B;
                else state_d = FINISH;
            end
            FINISH, FAIL: state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end

    always_comb begin
        op_init_o      = 1'b0;
        setup_o        = 1'b0;
        src_o          = SRC_A;
        elem_next_o    = 1'b0;
        word_capture_o = 1'b0;
        word_clear_o   = 1'b0;
        out_capture_o  = 1'b0;
        c_capture_o    = 1'b0;
        m_next_o       = 1'b0;
        k_next_o       = 1'b0;
        n_next_o       = 1'b0;
        op_o           = OP_SRC_READ;
        bus_req_o      = 1'b0;
        finish_o       = 1'b0;
        error_o        = 1'b0;
        unique case (state_q)
            INIT: op_init_o = 1'b1;
            CLEAR: begin
                op_o      = OP_CMD_CLEAR;
                bus_req_o = 1'b1;
            end
            SETUP_B: begin
                setup_o = 1'b1;
                src_o   = SRC_B;
            end
            SETUP_A: begin
                setup_o = 1'b1;
                src_o   = SRC_A;
            end
            SETUP_C: begin
                setup_o = 1'b1;
                src_o   = SRC_C;
            end
            GATHER: begin
                op_o           = OP_SRC_READ;
                bus_req_o      = elem_valid_i;
                word_capture_o = elem_valid_i && ok;
                elem_next_o    = gather_step && !lane_last_i;
            end
            IN_WRITE: begin
                op_o         = OP_IN_WRITE;
                bus_req_o    = 1'b1;
                word_clear_o = ok;
                elem_next_o  = ok && !elem_last_i;
            end
            LOAD: begin
                op_o      = OP_CMD_LOAD;
                bus_req_o = 1'b1;
            end
            START: begin
                op_o      = OP_CMD_START;
                bus_req_o = 1'b1;
            end
            POLL: begin
                op_o      = OP_STATUS_READ;
                bus_req_o = 1'b1;
            end
            OUT_READ: begin
                op_o          = OP_OUT_READ;
                bus_req_o     = elem_valid_i;
                out_capture_o = elem_valid_i && ok;
                elem_next_o   = !elem_valid_i && !elem_last_i;
            end
            C_READ: begin
                op_o        = OP_C_READ;
                bus_req_o   = 1'b1;
                c_capture_o = ok;
            end
            C_WRITE: begin
                op_o        = OP_C_WRITE;
                bus_req_o   = 1'b1;
                elem_next_o = ok && !elem_last_i;
            end
            NEXT_TILE: begin
                if (!m_last_i) m_next_o = 1'b1;
                else if (!k_last_i) k_next_o = 1'b1;
                else if (!n_last_i) n_next_o = 1'b1;
            end
            FINISH: finish_o = 1'b1;
            FAIL: begin
                finish_o = 1'b1;
                error_o  = 1'b1;
            end
            default: ;
        endcase
    end

    assign busy_o = state_q != IDLE;

endmodule
