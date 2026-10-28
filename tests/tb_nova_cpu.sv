`timescale 1ns/1ps

module tb_nova_cpu;

    logic clk = 0;
    logic reset = 1;
    logic [7:0] acc;
    logic halted;

    always #5 clk = ~clk;

    nova_cpu dut (
        .clk(clk),
        .reset(reset),
        .acc(acc),
        .halted(halted)
    );

    initial begin
        $display("Nova CPU v0.1 test started");

        repeat (2) @(negedge clk);
        reset = 0;

        wait (halted);
        #1;

        if (acc !== 8'd6)
            $fatal(1, "FAIL: expected 6, got %0d", acc);

        $display("PASS: 5 + 3 - 2 = %0d", acc);
        $display("Nova CPU halted correctly");
        $finish;
    end

    initial begin
        #500;
        $fatal(1, "FAIL: CPU timed out");
    end

endmodule
