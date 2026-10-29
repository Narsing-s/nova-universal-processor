`timescale 1ns/1ps
module tb_nova_cpu;
    logic clk = 0;
    logic reset = 1;
    logic [7:0] r0, r1, r2, r3;
    logic carry_flag, zero_flag, overflow_flag, halted;
    always #5 clk = ~clk;
    nova_cpu dut (.clk(clk), .reset(reset), .r0(r0), .r1(r1), .r2(r2), .r3(r3),
        .carry_flag(carry_flag), .zero_flag(zero_flag), .overflow_flag(overflow_flag), .halted(halted));

    initial begin
        $display("Nova CPU v0.4 regression tests started");
        repeat (2) @(negedge clk);
        reset = 0;
        wait (halted); #1;
        if (r0 !== 8'd250 || r1 !== 8'd10 || r2 !== 8'd4 || r3 !== 8'd5)
            $fatal(1, "FAIL: default demo register results");
        if (dut.data_mem[1] !== 8'd8 || carry_flag !== 1'b1 || overflow_flag !== 1'b0)
            $fatal(1, "FAIL: default demo memory/flags");
        $display("PASS: existing 8-bit demo");

        reset = 1; @(negedge clk);
        dut.rom[0] = 16'h1007; dut.rom[1] = 16'h9004; dut.rom[2] = 16'hF000;
        dut.rom[3] = 16'hF000; dut.rom[4] = 16'h1409; dut.rom[5] = 16'hA000;
        for (integer k = 6; k < 16; k = k + 1) dut.rom[k] = 16'hF000;
        repeat (2) @(negedge clk); reset = 0; wait (halted); #1;
        if (r0 !== 8'd7 || r1 !== 8'd9 || dut.call_sp !== 5'd0)
            $fatal(1, "FAIL: CALL/RET round trip");
        $display("PASS: CALL/RET round trip");

        reset = 1; @(negedge clk);
        dut.rom[0] = 16'h10F0; dut.rom[1] = 16'h140F; dut.rom[2] = 16'hD840;
        dut.rom[3] = 16'hE840; dut.rom[4] = 16'h0610; dut.rom[5] = 16'h0A00;
        dut.rom[6] = 16'hF000;
        for (integer m = 7; m < 16; m = m + 1) dut.rom[m] = 16'hF000;
        repeat (2) @(negedge clk); reset = 0; wait (halted); #1;
        if (r0 !== 8'd240 || r1 !== 8'd15 || r2 !== 8'd15)
            $fatal(1, "FAIL: AND/OR/XOR/NOT");
        $display("PASS: AND/OR/XOR/NOT");

        // Fill all 16 data-stack slots. Normal RAM must remain untouched.
        reset = 1; @(negedge clk);
        dut.rom[0] = 16'h105A; dut.rom[1] = 16'hB000; dut.rom[2] = 16'h8001;
        for (integer n = 3; n < 16; n = n + 1) dut.rom[n] = 16'hF000;
        repeat (2) @(negedge clk); reset = 0; wait (halted); #1;
        if (dut.data_sp !== 5'd16 || dut.data_stack[15] !== 8'h5A)
            $fatal(1, "FAIL: all 16 data-stack entries must be usable");
        for (integer q = 0; q < 16; q = q + 1)
            if (dut.data_mem[q] !== 8'd0) $fatal(1, "FAIL: stack corrupted RAM[%0d]", q);
        $display("PASS: data stack isolated from RAM; all 16 entries usable");

        // Recursive CALL fills all 16 return-address entries, then stops safely.
        reset = 1; @(negedge clk);
        dut.rom[0] = 16'h9000;
        for (integer p = 1; p < 16; p = p + 1) dut.rom[p] = 16'hF000;
        repeat (2) @(negedge clk); reset = 0; wait (halted); #1;
        if (dut.call_sp !== 5'd16) $fatal(1, "FAIL: all 16 call-stack entries must be usable");
        $display("PASS: call stack capacity and overflow guard");
        $display("Nova CPU regression suite passed");
        $finish;
    end
    initial begin
        #5000;
        $fatal(1, "FAIL: CPU timed out");
    end
endmodule
