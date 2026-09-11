// multiplier_tb.sv
// Testbench para a unidade de multiplicacao (Figuras 3.3 e 3.4 - Patterson & Hennessy)

`timescale 1ns/1ps

module multiplier_tb;

    // -----------------------------------------------------------------------
    // Sinais
    // -----------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic        start;
    logic [31:0] multiplicand_in;
    logic [31:0] multiplier_in;
    logic [63:0] product;
    logic        done;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    multiplier_top dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .multiplicand_in (multiplicand_in),
        .multiplier_in   (multiplier_in),
        .product         (product),
        .done            (done)
    );

    // -----------------------------------------------------------------------
    // Clock: periodo de 10 ns
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Tarefa auxiliar: executa uma multiplicação e verifica o resultado
    // -----------------------------------------------------------------------
    task automatic run_test (
        input logic [31:0] a,
        input logic [31:0] b,
        input string       test_name
    );
        logic [63:0] expected;
        begin
            expected = 64'(a) * 64'(b);

            @(negedge clk);
            multiplicand_in = a;
            multiplier_in   = b;
            start           = 1'b1;

            // Aguarda 'done'
            @(posedge done);
            @(negedge clk);

            if (product === expected)
                $display("[PASS] %s: %0d x %0d = %0d", test_name, a, b, product);
            else
                $display("[FAIL] %s: %0d x %0d = %0d (esperado %0d)",
                         test_name, a, b, product, expected);

            // Desassertar start para voltar ao IDLE
            start = 1'b0;
            @(negedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Sequencia de testes
    // -----------------------------------------------------------------------
    initial begin
        // Inicialização
        rst_n           = 1'b0;
        start           = 1'b0;
        multiplicand_in = '0;
        multiplier_in   = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // --- Casos de teste ---
        run_test(32'd0,          32'd0,          "zero x zero");
        run_test(32'd1,          32'd1,          "1 x 1");
        run_test(32'd6,          32'd7,          "6 x 7");
        run_test(32'd255,        32'd255,        "255 x 255");
        run_test(32'd1000,       32'd1000,       "1000 x 1000");
        run_test(32'hFFFFFFFF,   32'd1,          "MAX x 1");
        run_test(32'hFFFFFFFF,   32'hFFFFFFFF,   "MAX x MAX");
        run_test(32'hAAAAAAAA,   32'h55555555,   "0xAAAAAAAA x 0x55555555");
        run_test(32'd123456789,  32'd987654321,  "123456789 x 987654321");

        $display("Simulacao concluida.");
        $finish;
    end

    // Timeout de seguranca
    initial begin
      #200000;
        $display("[TIMEOUT] Simulacao excedeu o limite de tempo.");
        $finish;
    end

endmodule
