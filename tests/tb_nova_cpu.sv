`timescale 1ns/1ps
module tb_nova_cpu;
    logic clk = 0;
    logic reset = 1;
    logic [7:0] r0, r1, r2, r3;
    logic carry_flag, zero_flag, overflow_flag, halted;

    always #5 clk = ~clk;

    nova_cpu dut (
        .clk(clk), .reset(reset), .r0(r0), .r1(r1), .r2(r2), .r3(r3),
        .carry_flag(carry_flag), .zero_flag(zero_flag),
        .overflow_flag(overflow_flag), .halted(halted)
    );

    task automatic reset_cpu;
        begin
            @(negedge clk); reset = 1;
            repeat (2) @(negedge clk);
            reset = 0;
        end
    endtask

    initial begin
        $display("Nova CPU v0.3 tests started");
        reset_cpu();
        wait (halted);
        #1;
        if (r0 !== 8'd250) $fatal(1, "FAIL: branch path/r0 expected 250, got %0d", r0);
        if (r1 !== 8'd10) $fatal(1, "FAIL: r1 expected 10, got %0d", r1);
        if (r2 !== 8'd4) $fatal(1, "FAIL: ADD wrap/PUSH/POP expected r2=4, got %0d", r2);
        if (r3 !== 8'd5) $fatal(1, "FAIL: LOAD/CMP/BEQ/SUB expected r3=5, got %0d", r3);
        if (dut.data_mem[1] !== 8'd8) $fatal(1, "FAIL: STORE expected RAM[1]=8");
        if (carry_flag !== 1'b1) $fatal(1, "FAIL: carry flag should be set after 250+10");
        if (overflow_flag !== 1'b0) $fatal(1, "FAIL: unsigned carry must not imply signed overflow");
        $display("PASS: arithmetic, memory, branch, carry, PUSH and POP");

        // Replace the demo ROM with a tiny subroutine test:
        // 0 LI r0, 7; 1 CALL 4; 2 HALT; 4 LI r1, 9; 5 RET.
        reset = 1;
        @(negedge clk);
        dut.rom[0] = 16'h1007;
        dut.rom[1] = 16'h9004;
        dut.rom[2] = 16'hF000;
        dut.rom[3] = 16'hF000;
        dut.rom[4] = 16'h1409;
        dut.rom[5] = 16'hA000;
        for (integer k = 6; k < 16; k = k + 1) dut.rom[k] = 16'hF000;
        repeat (2) @(negedge clk);
        reset = 0;
        wait (halted);
        #1;
        if (r0 !== 8'd7 || r1 !== 8'd9)
            $fatal(1, "FAIL: CALL/RET expected r0=7,r1=9; got r0=%0d r1=%0d", r0, r1);
        $display("PASS: CALL and RET subroutine");
        $display("Nova CPU v0.3 all tests passed");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: CPU timed out");
    end
endmodule
