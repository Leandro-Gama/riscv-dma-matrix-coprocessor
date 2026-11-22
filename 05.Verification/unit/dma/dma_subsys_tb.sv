`timescale 1ns/1ps

/* E3: DMA + shared memory + accelerator, without the CPU. The testbench plays the CPU through
   write/read tasks on the DMA registers (BFM), loads A and B in the memory by backdoor and
   compares C with the golden model. */
module dma_subsys_case #(
    parameter int N = 2,
    parameter int DATA_WIDTH = 8
) (
    output logic finished_o = 1'b0,
    output int   ok_o = 0,
    output int   err_o = 0
);
    localparam logic [31:0] DMEM_BASE  = 32'h1000_0000;
    localparam logic [31:0] REGION_A   = 32'h1000_1000;
    localparam logic [31:0] REGION_B   = 32'h1000_2000;
    localparam logic [31:0] REGION_C   = 32'h1000_3000;
    localparam int          REGION_LEN = 4096;
    localparam logic [31:0] DMA_BASE   = 32'h2000_0000;
    localparam logic [31:0] ADDR_A     = DMA_BASE + 32'h00;
    localparam logic [31:0] ADDR_B     = DMA_BASE + 32'h04;
    localparam logic [31:0] ADDR_C     = DMA_BASE + 32'h08;
    localparam logic [31:0] DIM_M      = DMA_BASE + 32'h0C;
    localparam logic [31:0] DIM_K      = DMA_BASE + 32'h10;
    localparam logic [31:0] DIM_N      = DMA_BASE + 32'h14;
    localparam logic [31:0] CONTROL    = DMA_BASE + 32'h18;
    localparam logic [31:0] STATUS     = DMA_BASE + 32'h1C;
    localparam logic [1:0]  OKAY       = 2'b00;
    localparam logic [1:0]  SLVERR     = 2'b10;
    localparam int          BYTES      = DATA_WIDTH / 8;
    localparam logic [31:0] FILL       = 32'hDEAD_BEEF;
    localparam int          TIMEOUT    = 400000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic irq;
    int   cycle = 0;

    always #5 clk = ~clk;
    always @(posedge clk) cycle++;

    // CPU side: BFM on the DMA registers.
    logic [31:0] cpu_awaddr = '0, cpu_wdata = '0, cpu_araddr = '0;
    logic [3:0]  cpu_wstrb = '0;
    logic        cpu_awvalid = 1'b0, cpu_wvalid = 1'b0, cpu_bready = 1'b0;
    logic        cpu_arvalid = 1'b0, cpu_rready = 1'b0;
    logic        cpu_awready, cpu_wready, cpu_bvalid, cpu_arready, cpu_rvalid;
    logic [1:0]  cpu_bresp, cpu_rresp;
    logic [31:0] cpu_rdata;

    // DMA master port.
    logic [31:0] dma_awaddr, dma_wdata, dma_araddr, dma_rdata;
    logic [2:0]  dma_awprot, dma_arprot;
    logic [3:0]  dma_wstrb;
    logic        dma_awvalid, dma_awready, dma_wvalid, dma_wready, dma_bvalid, dma_bready;
    logic        dma_arvalid, dma_arready, dma_rvalid, dma_rready;
    logic [1:0]  dma_bresp, dma_rresp;

    // Decoder ports: 0 = data memory, 1 = accelerator CSR, 2 = accelerator buffers.
    logic [2:0][31:0] dec_awaddr, dec_wdata, dec_araddr, dec_rdata;
    logic [2:0][2:0]  dec_awprot, dec_arprot;
    logic [2:0][3:0]  dec_wstrb;
    logic [2:0][1:0]  dec_bresp, dec_rresp;
    logic [2:0]       dec_awvalid, dec_awready, dec_wvalid, dec_wready, dec_bvalid, dec_bready;
    logic [2:0]       dec_arvalid, dec_arready, dec_rvalid, dec_rready;

    logic        acc_mode, acc_load, acc_start, acc_clr_error;
    wire  [31:0] acc_status;
    axil_if acc_bus(clk, rst_n);

    logic [31:0] a_q[], b_q[], c_q[];
    string       case_name;
    int          vectors_fd, case_count, dim_m_v, dim_k_v, dim_n_v;
    int          ok_count = 0, err_count = 0;

    dma_top #(.ARRAY_SIZE(N), .DATA_WIDTH(DATA_WIDTH)) u_dma (
        .clk_i(clk), .rst_ni(rst_n),
        .s_axi_awaddr(cpu_awaddr), .s_axi_awprot(3'b000), .s_axi_awvalid(cpu_awvalid),
        .s_axi_awready(cpu_awready), .s_axi_wdata(cpu_wdata), .s_axi_wstrb(cpu_wstrb),
        .s_axi_wvalid(cpu_wvalid), .s_axi_wready(cpu_wready), .s_axi_bresp(cpu_bresp),
        .s_axi_bvalid(cpu_bvalid), .s_axi_bready(cpu_bready), .s_axi_araddr(cpu_araddr),
        .s_axi_arprot(3'b000), .s_axi_arvalid(cpu_arvalid), .s_axi_arready(cpu_arready),
        .s_axi_rdata(cpu_rdata), .s_axi_rresp(cpu_rresp), .s_axi_rvalid(cpu_rvalid),
        .s_axi_rready(cpu_rready),
        .m_axi_awaddr(dma_awaddr), .m_axi_awprot(dma_awprot), .m_axi_awvalid(dma_awvalid),
        .m_axi_awready(dma_awready), .m_axi_wdata(dma_wdata), .m_axi_wstrb(dma_wstrb),
        .m_axi_wvalid(dma_wvalid), .m_axi_wready(dma_wready), .m_axi_bresp(dma_bresp),
        .m_axi_bvalid(dma_bvalid), .m_axi_bready(dma_bready), .m_axi_araddr(dma_araddr),
        .m_axi_arprot(dma_arprot), .m_axi_arvalid(dma_arvalid), .m_axi_arready(dma_arready),
        .m_axi_rdata(dma_rdata), .m_axi_rresp(dma_rresp), .m_axi_rvalid(dma_rvalid),
        .m_axi_rready(dma_rready),
        .irq_o(irq)
    );

    soc_axil_decoder #(
        .NUM_SLAVES(3),
        .SLAVE_BASE({32'h4000_1000, 32'h4000_0000, DMEM_BASE}),
        .SLAVE_SIZE({32'h0000_2000, 32'h0000_1000, 32'h0000_4000})
    ) u_dec (
        .clk_i(clk), .rst_ni(rst_n),
        .s_axi_awaddr(dma_awaddr), .s_axi_awprot(dma_awprot), .s_axi_awvalid(dma_awvalid),
        .s_axi_awready(dma_awready), .s_axi_wdata(dma_wdata), .s_axi_wstrb(dma_wstrb),
        .s_axi_wvalid(dma_wvalid), .s_axi_wready(dma_wready), .s_axi_bresp(dma_bresp),
        .s_axi_bvalid(dma_bvalid), .s_axi_bready(dma_bready), .s_axi_araddr(dma_araddr),
        .s_axi_arprot(dma_arprot), .s_axi_arvalid(dma_arvalid), .s_axi_arready(dma_arready),
        .s_axi_rdata(dma_rdata), .s_axi_rresp(dma_rresp), .s_axi_rvalid(dma_rvalid),
        .s_axi_rready(dma_rready),
        .m_axi_awaddr(dec_awaddr), .m_axi_awprot(dec_awprot), .m_axi_awvalid(dec_awvalid),
        .m_axi_awready(dec_awready), .m_axi_wdata(dec_wdata), .m_axi_wstrb(dec_wstrb),
        .m_axi_wvalid(dec_wvalid), .m_axi_wready(dec_wready), .m_axi_bresp(dec_bresp),
        .m_axi_bvalid(dec_bvalid), .m_axi_bready(dec_bready), .m_axi_araddr(dec_araddr),
        .m_axi_arprot(dec_arprot), .m_axi_arvalid(dec_arvalid), .m_axi_arready(dec_arready),
        .m_axi_rdata(dec_rdata), .m_axi_rresp(dec_rresp), .m_axi_rvalid(dec_rvalid),
        .m_axi_rready(dec_rready)
    );

    soc_dmem #(.BASE(DMEM_BASE), .BYTES(16384)) u_mem (
        .clk_i(clk), .rst_ni(rst_n),
        .s_axi_awaddr(dec_awaddr[0]), .s_axi_awprot(dec_awprot[0]),
        .s_axi_awvalid(dec_awvalid[0]), .s_axi_awready(dec_awready[0]),
        .s_axi_wdata(dec_wdata[0]), .s_axi_wstrb(dec_wstrb[0]), .s_axi_wvalid(dec_wvalid[0]),
        .s_axi_wready(dec_wready[0]), .s_axi_bresp(dec_bresp[0]), .s_axi_bvalid(dec_bvalid[0]),
        .s_axi_bready(dec_bready[0]), .s_axi_araddr(dec_araddr[0]),
        .s_axi_arprot(dec_arprot[0]), .s_axi_arvalid(dec_arvalid[0]),
        .s_axi_arready(dec_arready[0]), .s_axi_rdata(dec_rdata[0]), .s_axi_rresp(dec_rresp[0]),
        .s_axi_rvalid(dec_rvalid[0]), .s_axi_rready(dec_rready[0])
    );

    soc_accel_csr u_csr (
        .clk_i(clk), .rst_ni(rst_n),
        .s_axi_awaddr(dec_awaddr[1]), .s_axi_awprot(dec_awprot[1]),
        .s_axi_awvalid(dec_awvalid[1]), .s_axi_awready(dec_awready[1]),
        .s_axi_wdata(dec_wdata[1]), .s_axi_wstrb(dec_wstrb[1]), .s_axi_wvalid(dec_wvalid[1]),
        .s_axi_wready(dec_wready[1]), .s_axi_bresp(dec_bresp[1]), .s_axi_bvalid(dec_bvalid[1]),
        .s_axi_bready(dec_bready[1]), .s_axi_araddr(dec_araddr[1]),
        .s_axi_arprot(dec_arprot[1]), .s_axi_arvalid(dec_arvalid[1]),
        .s_axi_arready(dec_arready[1]), .s_axi_rdata(dec_rdata[1]), .s_axi_rresp(dec_rresp[1]),
        .s_axi_rvalid(dec_rvalid[1]), .s_axi_rready(dec_rready[1]),
        .mode_o(acc_mode), .load_o(acc_load), .start_o(acc_start),
        .clr_error_o(acc_clr_error), .status_i(acc_status)
    );

    assign acc_bus.awaddr  = dec_awaddr[2];
    assign acc_bus.awprot  = dec_awprot[2];
    assign acc_bus.awvalid = dec_awvalid[2];
    assign acc_bus.wdata   = dec_wdata[2];
    assign acc_bus.wstrb   = dec_wstrb[2];
    assign acc_bus.wvalid  = dec_wvalid[2];
    assign acc_bus.bready  = dec_bready[2];
    assign acc_bus.araddr  = dec_araddr[2];
    assign acc_bus.arprot  = dec_arprot[2];
    assign acc_bus.arvalid = dec_arvalid[2];
    assign acc_bus.rready  = dec_rready[2];
    assign dec_awready[2]  = acc_bus.awready;
    assign dec_wready[2]   = acc_bus.wready;
    assign dec_bresp[2]    = acc_bus.bresp;
    assign dec_bvalid[2]   = acc_bus.bvalid;
    assign dec_arready[2]  = acc_bus.arready;
    assign dec_rdata[2]    = acc_bus.rdata;
    assign dec_rresp[2]    = acc_bus.rresp;
    assign dec_rvalid[2]   = acc_bus.rvalid;

    accel_top #(.N(N), .DATA_WIDTH(DATA_WIDTH)) u_acc (
        .clk_i(clk), .rst_ni(rst_n), .mode_i(acc_mode), .load_i(acc_load),
        .start_i(acc_start), .clr_error_i(acc_clr_error), .status_o(acc_status), .s_axi(acc_bus)
    );

    task automatic check(input bit condition, input string message);
        if (condition) begin
            ok_count++;
        end else begin
            err_count++;
            $display("ERRO N=%0d DW=%0d: %s", N, DATA_WIDTH, message);
        end
    endtask

    task automatic cpu_write(input logic [31:0] address, data, output logic [1:0] response);
        @(negedge clk);
        cpu_awaddr  = address;
        cpu_awvalid = 1'b1;
        cpu_wdata   = data;
        cpu_wstrb   = 4'hF;
        cpu_wvalid  = 1'b1;
        cpu_bready  = 1'b1;
        fork
            begin
                do @(posedge clk); while (!cpu_awready);
                @(negedge clk) cpu_awvalid = 1'b0;
            end
            begin
                do @(posedge clk); while (!cpu_wready);
                @(negedge clk) cpu_wvalid = 1'b0;
            end
        join
        while (!cpu_bvalid) @(negedge clk);
        response = cpu_bresp;
        @(negedge clk) cpu_bready = 1'b0;
    endtask

    task automatic cpu_read(input logic [31:0] address, output logic [31:0] data,
                            output logic [1:0] response);
        @(negedge clk);
        cpu_araddr  = address;
        cpu_arvalid = 1'b1;
        cpu_rready  = 1'b1;
        do @(posedge clk); while (!cpu_arready);
        @(negedge clk) cpu_arvalid = 1'b0;
        while (!cpu_rvalid) @(negedge clk);
        data     = cpu_rdata;
        response = cpu_rresp;
        @(negedge clk) cpu_rready = 1'b0;
    endtask

    task automatic write_reg(input logic [31:0] address, data);
        logic [1:0] response;
        cpu_write(address, data, response);
        check(response == OKAY, $sformatf("write %h: resp %b", address, response));
    endtask

    task automatic expect_status(input logic [31:0] expected, input string message);
        logic [31:0] value;
        logic [1:0]  response;
        cpu_read(STATUS, value, response);
        check(response == OKAY && value == expected,
              $sformatf("%s: STATUS=%h, esperado %h", message, value, expected));
    endtask

    function automatic int word_index(input logic [31:0] address);
        return int'((address - DMEM_BASE) >> 2);
    endfunction

    task automatic poke(input logic [31:0] address, input logic [31:0] value);
        logic [31:0] word;
        word = u_mem.mem_q[word_index(address)];
        word[8*address[1:0] +: DATA_WIDTH] = value[DATA_WIDTH-1:0];
        u_mem.mem_q[word_index(address)] = word;
    endtask

    function automatic logic [31:0] peek(input logic [31:0] address);
        logic [31:0] word;
        word = u_mem.mem_q[word_index(address)];
        return 32'(word[8*address[1:0] +: DATA_WIDTH]);
    endfunction

    task automatic fill_regions;
        for (int i = 0; i < 3 * REGION_LEN / 4; i++) u_mem.mem_q[REGION_LEN / 4 + i] = FILL;
    endtask

    task automatic wait_done(output int cycles, output bit timed_out);
        int start;
        start = cycle;
        timed_out = 1'b0;
        while (!irq) begin
            @(negedge clk);
            if (cycle - start > TIMEOUT) begin
                timed_out = 1'b1;
                break;
            end
        end
        cycles = cycle - start;
    endtask

    task automatic start_dma(input logic [31:0] a, b, c, input int m, k, n);
        write_reg(ADDR_A, a);
        write_reg(ADDR_B, b);
        write_reg(ADDR_C, c);
        write_reg(DIM_M, m);
        write_reg(DIM_K, k);
        write_reg(DIM_N, n);
        write_reg(CONTROL, 32'h3);
    endtask

    task automatic read_matrix(ref logic [31:0] matrix[], input int rows, cols);
        matrix = new[rows * cols];
        for (int i = 0; i < rows * cols; i++)
            check($fscanf(vectors_fd, "%h", matrix[i]) == 1, "leitura do vetor");
    endtask

    task automatic run_case(input bit first);
        int         cycles, wrong;
        bit         timed_out;
        logic [1:0] response;
        logic [31:0] value;

        check($fscanf(vectors_fd, "%s %d %d %d", case_name, dim_m_v, dim_k_v, dim_n_v) == 4,
              "cabecalho do caso");
        read_matrix(a_q, dim_m_v, dim_k_v);
        read_matrix(b_q, dim_k_v, dim_n_v);
        read_matrix(c_q, dim_m_v, dim_n_v);

        fill_regions();
        for (int i = 0; i < dim_m_v * dim_k_v; i++) poke(REGION_A + i * BYTES, a_q[i]);
        for (int i = 0; i < dim_k_v * dim_n_v; i++) poke(REGION_B + i * BYTES, b_q[i]);

        start_dma(REGION_A, REGION_B, REGION_C, dim_m_v, dim_k_v, dim_n_v);
        if (first) begin
            cpu_write(DIM_M, 32'd5, response);
            check(response == SLVERR, "escrita em DIM_M com BUSY deve dar SLVERR");
            cpu_read(DIM_M, value, response);
            check(value == 32'(dim_m_v), "DIM_M preservado durante a operacao");
            expect_status(32'h1, "BUSY durante a operacao");
            cpu_write(CONTROL, 32'h3, response);
            check(response == OKAY, "START com BUSY responde OKAY e e ignorado");
        end
        wait_done(cycles, timed_out);
        check(!timed_out, $sformatf("%s: timeout", case_name));
        expect_status(32'h2, $sformatf("%s: DONE sem erro", case_name));

        wrong = 0;
        for (int i = 0; i < dim_m_v * dim_n_v; i++) begin
            value = peek(REGION_C + i * BYTES);
            if (value[DATA_WIDTH-1:0] !== c_q[i][DATA_WIDTH-1:0]) begin
                if (wrong < 4)
                    $display("ERRO N=%0d DW=%0d %s C[%0d][%0d]: golden=%h DUT=%h", N, DATA_WIDTH,
                             case_name, i / dim_n_v, i % dim_n_v, c_q[i][DATA_WIDTH-1:0],
                             value[DATA_WIDTH-1:0]);
                wrong++;
            end
        end
        check(wrong == 0, $sformatf("%s: %0d elementos de C diferentes do golden", case_name, wrong));

        // Nothing written past the end of C.
        wrong = 0;
        for (int b = dim_m_v * dim_n_v * BYTES; b < REGION_LEN; b++) begin
            value = u_mem.mem_q[word_index(REGION_C + b)];
            if (value[8*(b % 4) +: 8] != FILL[8*(b % 4) +: 8]) wrong++;
        end
        check(wrong == 0, $sformatf("%s: %0d bytes alterados fora de C", case_name, wrong));

        write_reg(CONTROL, 32'h0);
        @(negedge clk);
        check(!irq, "IRQ_EN=0 derruba irq_o");

        if (wrong == 0)
            $display("OK N=%0d DW=%0d %-14s M=%0d K=%0d N=%0d: %0d ciclos", N, DATA_WIDTH,
                     case_name, dim_m_v, dim_k_v, dim_n_v, cycles);
    endtask

    task automatic directed_tests;
        logic [31:0] value;
        logic [1:0]  response;
        int          cycles;
        bit          timed_out;

        expect_status(32'h0, "STATUS no reset");
        check(!irq, "irq_o no reset");
        cpu_read(ADDR_A, value, response);
        check(response == OKAY && value == 0, "ADDR_A no reset");

        write_reg(ADDR_A, 32'h1234_5678);
        cpu_read(ADDR_A, value, response);
        check(value == 32'h1234_5678, "ADDR_A le o valor escrito");
        cpu_read(DMA_BASE + 32'h20, value, response);
        check(response == SLVERR, "leitura de offset sem registrador");
        cpu_write(STATUS, 32'hFFFF_FFFF, response);
        check(response == SLVERR, "escrita em STATUS");
        cpu_write(DIM_M + 2, 32'h1, response);
        check(response == SLVERR, "escrita desalinhada");
        cpu_read(CONTROL, value, response);
        check(value == 0, "START sempre le 0");

        // Zero dimension: ends at once with DONE and ERROR.
        start_dma(REGION_A, REGION_B, REGION_C, 0, 3, 3);
        wait_done(cycles, timed_out);
        check(!timed_out, "dimensao zero termina");
        expect_status(32'h6, "dimensao zero: DONE e ERROR");

        // C outside every region: DECERR stops the DMA with ERROR.
        fill_regions();
        start_dma(REGION_A, REGION_B, 32'h3000_0000, 1, 1, 1);
        wait_done(cycles, timed_out);
        check(!timed_out, "DECERR termina");
        expect_status(32'h6, "DECERR: DONE e ERROR");

        // Accelerator stuck in ERROR: the DMA must stop instead of waiting forever.
        force u_acc.u_systolic.error_q = 1'b1;
        start_dma(REGION_A, REGION_B, REGION_C, 1, 1, 1);
        wait_done(cycles, timed_out);
        check(!timed_out, "erro do acelerador termina");
        expect_status(32'h6, "erro do acelerador: DONE e ERROR");
        release u_acc.u_systolic.error_q;
        write_reg(CONTROL, 32'h0);
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        directed_tests();

        vectors_fd = $fopen($sformatf("vectors/n%0d_w%0d.txt", N, DATA_WIDTH), "r");
        check(vectors_fd != 0, "abrir vetores do golden");
        check($fscanf(vectors_fd, "%d", case_count) == 1, "numero de casos");
        for (int i = 0; i < case_count; i++) run_case(i == 0);
        $fclose(vectors_fd);

        ok_o  = ok_count;
        err_o = err_count;
        finished_o = 1'b1;
    end
endmodule

module dma_subsys_tb;
    wire [8:0] finished;
    int ok [9];
    int err [9];

    for (genvar size_index = 0; size_index < 3; size_index++) begin : gen_size
        for (genvar width_index = 0; width_index < 3; width_index++) begin : gen_width
            dma_subsys_case #(.N(2 << size_index), .DATA_WIDTH(8 << width_index)) u_case (
                .finished_o(finished[3*size_index+width_index]),
                .ok_o(ok[3*size_index+width_index]),
                .err_o(err[3*size_index+width_index])
            );
        end
    end

    // Waveform of the smallest configuration only (ARRAY_SIZE=2, DATA_WIDTH=8): run with +waves.
    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("dma_waves.vcd");
            $dumpvars(0, gen_size[0].gen_width[0].u_case);
        end
    end

    initial begin
        int total_ok, total_err;
        wait (&finished);
        total_ok = 0;
        total_err = 0;
        for (int i = 0; i < 9; i++) begin
            total_ok += ok[i];
            total_err += err[i];
        end
        $display("RESUMO: %0d OK, %0d ERRO", total_ok, total_err);
        $finish;
    end

    initial begin
        #200ms;
        $fatal(1, "ERRO: timeout global");
    end
endmodule
