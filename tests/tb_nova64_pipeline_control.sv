`timescale 1ns/1ps
module tb_nova64_pipeline_control;
    logic [4:0] id_rs1, id_rs2, ex_rs1, ex_rs2, ex_rd, mem_rd, wb_rd;
    logic id_uses_rs1, id_uses_rs2, ex_regwrite, ex_memread;
    logic mem_regwrite, wb_regwrite, redirect_valid;
    logic stall_if_id, bubble_id_ex, flush_if_id, flush_id_ex;
    logic [1:0] forward_a, forward_b;

    nova64_pipeline_control dut(.*);

    task automatic check(input logic condition, input string message);
        if (!condition) $fatal(1, "FAIL: %s", message);
    endtask

    initial begin
        id_rs1=0; id_rs2=0; id_uses_rs1=0; id_uses_rs2=0;
        ex_rs1=0; ex_rs2=0; ex_rd=0; ex_regwrite=0; ex_memread=0;
        mem_rd=0; mem_regwrite=0; wb_rd=0; wb_regwrite=0; redirect_valid=0;
        #1;
        check(!stall_if_id && !bubble_id_ex, "no hazard should not stall");

        // A load in EX feeding either used source in ID must interlock.
        ex_rd=5'd7; ex_memread=1; id_rs1=5'd7; id_uses_rs1=1; #1;
        check(stall_if_id && bubble_id_ex, "load-use rs1 hazard");
        id_rs1=0; id_uses_rs1=0; id_rs2=5'd7; id_uses_rs2=1; #1;
        check(stall_if_id && bubble_id_ex, "load-use rs2 hazard");

        // An unused encoded source must not cause a false stall.
        id_uses_rs2=0; #1;
        check(!stall_if_id && !bubble_id_ex, "unused source must not stall");
        ex_rd=0; id_rs1=0; id_rs2=0; id_uses_rs1=0; id_uses_rs2=0; ex_memread=0;

        // Newest producer in EX/MEM wins over an older MEM/WB producer.
        ex_rs1=5'd3; ex_rs2=5'd4;
        mem_rd=5'd3; mem_regwrite=1; wb_rd=5'd3; wb_regwrite=1;
        mem_rd=5'd3; #1;
        check(forward_a==2'b10, "EX/MEM priority for operand A");
        mem_rd=5'd9; wb_rd=5'd3; #1;
        check(forward_a==2'b01, "MEM/WB fallback for operand A");

        // x0 never forwards; matching destination zero is ignored.
        ex_rs1=0; mem_rd=0; wb_rd=0; #1;
        check(forward_a==2'b00, "never forward x0");

        // Both operands can be forwarded independently.
        ex_rs1=5'd5; ex_rs2=5'd6; mem_rd=5'd5; wb_rd=5'd6;
        mem_regwrite=1; wb_regwrite=1; #1;
        check(forward_a==2'b10 && forward_b==2'b01, "independent A/B forwarding");

        // A taken redirect flushes wrong-path instructions and overrides a stall.
        ex_memread=1; ex_rd=5'd8; id_rs1=5'd8; id_uses_rs1=1;
        redirect_valid=1; #1;
        check(flush_if_id && flush_id_ex, "redirect flushes both younger stages");
        check(!stall_if_id && !bubble_id_ex, "redirect has priority over load-use stall");

        $display("PASS: Nova64 pipeline control hazard, forwarding, x0 and redirect tests");
        $finish;
    end
endmodule
