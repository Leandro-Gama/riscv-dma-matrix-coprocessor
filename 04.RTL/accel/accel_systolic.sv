module accel_systolic #(
    parameter int N = 2,
    parameter int DATA_WIDTH = 8
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic mode_i,
    input  logic load_i,
    input  logic start_i,
    input  logic clr_error_i,
    input  logic [N*N-1:0][DATA_WIDTH-1:0] data_i,
    output wire  [N*N-1:0][DATA_WIDTH-1:0] data_o,
    output logic [31:0] status_o
);
    localparam int ACC_WIDTH = 2 * DATA_WIDTH + $clog2(N);
    localparam int CYCLE_WIDTH = $clog2(3 * N - 2);
    localparam int LAST_CYCLE = 3 * N - 3;

    typedef enum logic [1:0] {IDLE, LOADING, PROCESSING} state_t;
    state_t state_q, state_d;
    logic [CYCLE_WIDTH-1:0] cycle_q;
    logic done_q, error_q;
    logic accept_load, accept_start, invalid_command, finish;
    logic signed [DATA_WIDTH-1:0] weight_q [N][N];
    logic signed [DATA_WIDTH-1:0] activation_q [N][N];
    logic signed [ACC_WIDTH-1:0] partial_q [N][N];
    wire signed [ACC_WIDTH-1:0] mac [N][N];
    logic valid_q [N][N];
    wire valid [N][N];

    if (!(N == 2 || N == 4 || N == 8)) begin : gen_invalid_n
        ACCEL_N_MUST_BE_2_4_OR_8 invalid_parameter();
    end
    if (!(DATA_WIDTH == 8 || DATA_WIDTH == 16 || DATA_WIDTH == 32)) begin : gen_invalid_width
        ACCEL_DATA_WIDTH_MUST_BE_8_16_OR_32 invalid_parameter();
    end

    assign accept_load = state_q == IDLE && !mode_i && load_i && !start_i;
    assign accept_start = state_q == IDLE && mode_i && start_i && !load_i;
    assign invalid_command = (load_i || start_i) && !(accept_load || accept_start);
    assign finish = (state_q == LOADING && int'(cycle_q) == N - 1) ||
                    (state_q == PROCESSING && int'(cycle_q) == LAST_CYCLE);

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE: begin
                if (accept_load) state_d = LOADING;
                if (accept_start) state_d = PROCESSING;
            end
            LOADING, PROCESSING: if (finish) state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= IDLE;
        else state_q <= state_d;
    end

    always_comb begin
        status_o = '0;
        status_o[1:0] = state_q;
        status_o[2] = done_q;
        status_o[3] = error_q;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cycle_q <= '0;
            done_q <= 1'b0;
            error_q <= 1'b0;
        end else begin
            if (state_q == IDLE || finish) cycle_q <= '0;
            else cycle_q <= cycle_q + 1'b1;
            if (accept_load || accept_start) done_q <= 1'b0;
            else if (finish) done_q <= 1'b1;
            if (clr_error_i) error_q <= 1'b0;
            if (invalid_command) error_q <= 1'b1;
        end
    end

    for (genvar row = 0; row < N; row++) begin : gen_row
        for (genvar col = 0; col < N; col++) begin : gen_col
            wire signed [DATA_WIDTH-1:0] activation;
            wire signed [2*DATA_WIDTH-1:0] product;
            wire signed [ACC_WIDTH-1:0] previous_sum;
            logic [DATA_WIDTH-1:0] result_q;

            if (col == 0) begin : gen_input
                wire inject;
                assign inject = state_q == PROCESSING && int'(cycle_q) >= row &&
                                int'(cycle_q) < row + N;
                // Row skew aligns each activation with the partial sum from the row above.
                assign activation = inject ? data_i[(int'(cycle_q) - row)*N + row] : '0;
                assign valid[row][col] = inject;
            end else begin : gen_forward
                assign activation = activation_q[row][col-1];
                assign valid[row][col] = valid_q[row][col-1];
            end

            if (row == 0) begin : gen_zero_sum
                assign previous_sum = '0;
            end else begin : gen_partial_sum
                assign previous_sum = partial_q[row-1][col];
            end

            assign product = activation * weight_q[row][col];
            assign mac[row][col] = previous_sum +
                                  {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
            assign data_o[row*N+col] = result_q;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) weight_q[row][col] <= '0;
                else if (state_q == LOADING && int'(cycle_q) == row)
                    weight_q[row][col] <= data_i[row*N+col];
            end

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    activation_q[row][col] <= '0;
                    partial_q[row][col] <= '0;
                    valid_q[row][col] <= 1'b0;
                end else if (state_q == PROCESSING) begin
                    activation_q[row][col] <= activation;
                    partial_q[row][col] <= valid[row][col] ? mac[row][col] : '0;
                    valid_q[row][col] <= valid[row][col];
                end else begin
                    activation_q[row][col] <= '0;
                    partial_q[row][col] <= '0;
                    valid_q[row][col] <= 1'b0;
                end
            end

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) result_q <= '0;
                else if (state_q == PROCESSING && int'(cycle_q) == row + N - 1 + col)
                    result_q <= mac[N-1][col][DATA_WIDTH-1:0];
            end
        end
    end
endmodule
