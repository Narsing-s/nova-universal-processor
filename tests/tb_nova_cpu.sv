`timescale 1ns/1ps

module tb_nova_cpu;

    logic clk = 0;
    logic reset = 1;
    logic [7:0] r0, r1, r2, r3;
    logic halted;

    always #5 clk = ~clk;

    nova_cpu dut (
        .clk(clk),
        .reset(reset),
        .r0(r0),
        .r1(r1),
        .r2(r2),
        .r3(r3),
        .halted(halted)
    );

    initial begin
        $display("Nova CPU v0.2 test started");

        repeat (2) @(negedge clk);
        reset = 0;

        wait (halted);
        #1;

        if (r0 !== 8'd5)
            $fatal(1, "FAIL: branch should skip LI r0,0; r0=%0d", r0);
        if (r1 !== 8'd3)
            $fatal(1, "FAIL: expected r1=3, got %0d", r1);
        if (r2 !== 8'd8)
            $fatal(1, "FAIL: ADD expected r2=8, got %0d", r2);
        if (r3 !== 8'd5)
            $fatal(1, "FAIL: LOAD/CMP/BEQ/SUB expected r3=5, got %0d", r3);
        if (dut.data_mem[1] !== 8'd8)
            $fatal(1, "FAIL: STORE expected RAM[1]=8, got %0d", dut.data_mem[1]);

        $display("PASS: general-purpose registers");
        $display("PASS: ADD, STORE, LOAD, CMP, and BEQ");
        $display("PASS: SUB result r3=%0d and RAM[1]=%0d", r3, dut.data_mem[1]);
        $display("Nova CPU v0.2 halted correctly");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: CPU timed out");
    end

endmodule
