`timescale 1ns/1ps
// Focused Nova32 load/store and illegal-encoding regression tests.
// Kept separate from the original smoke test so memory edge cases are easy to audit.
module tb_nova32_memory_edges;
    logic clk = 0, reset = 1;
    logic [31:0] instr_addr, instr_rdata, data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    always #5 clk = ~clk;
    assign instr_rdata = imem[instr_addr[7:2]];
    assign data_rdata = dmem[data_addr[7:2]];

    always_ff @(posedge clk) begin
        if (data_we)
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (data_wstrb[lane])
                    dmem[data_addr[7:2]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];
    end

    nova32_cpu dut (
        .clk(clk), .reset(reset), .instr_addr(instr_addr), .instr_rdata(instr_rdata),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_wstrb(data_wstrb),
        .data_we(data_we), .data_rdata(data_rdata), .halted(halted),
        .illegal_instruction(illegal_instruction)
    );

    function automatic [31:0] enc_i(input integer imm, input integer rs1, input integer f3,
                                     input integer rd, input logic [6:0] op);
        enc_i = {imm[11:0], rs1[4:0], f3[2:0], rd[4:0], op};
    endfunction
    function automatic [31:0] enc_s(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:0], 7'b0100011};
    endfunction

    task automatic clear_mem;
        begin
            for (integer i = 0; i < 64; i = i + 1) begin
                imem[i] = 32'h0000000B;
                dmem[i] = 32'd0;
            end
        end
    endtask
    task automatic start_cpu;
        begin
            reset = 1;
            repeat (2) @(negedge clk);
            reset = 0;
        end
    endtask
    task automatic await_halt;
        integer cycles;
        begin
            cycles = 0;
            while (!halted && cycles < 30) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!halted) $fatal(1, "Nova32 memory-edge test timeout");
            #1;
        end
    endtask

    initial begin
        $display("Nova32 memory-edge regressions started");

        // Exercise sign extension, zero extension and byte selection from all
        // four lanes of the word returned by the simple data-memory interface.
        clear_mem();
        dmem[0] = 32'h80FF_7F01;
        imem[0] = enc_i(3,0,0,1,7'b0000011); // lb  x1,3(x0) -> ffffff80
        imem[1] = enc_i(3,0,4,2,7'b0000011); // lbu x2,3(x0) -> 00000080
        imem[2] = enc_i(2,0,1,3,7'b0000011); // lh  x3,2(x0) -> ffff80ff
        imem[3] = enc_i(2,0,5,4,7'b0000011); // lhu x4,2(x0) -> 000080ff
        imem[4] = enc_i(0,0,1,5,7'b0000011); // lh  x5,0(x0) -> 00007f01
        imem[5] = enc_i(0,0,5,6,7'b0000011); // lhu x6,0(x0) -> 00007f01
        imem[6] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction ||
            dut.regs[1] !== 32'hFFFF_FF80 || dut.regs[2] !== 32'h0000_0080 ||
            dut.regs[3] !== 32'hFFFF_80FF || dut.regs[4] !== 32'h0000_80FF ||
            dut.regs[5] !== 32'h0000_7F01 || dut.regs[6] !== 32'h0000_7F01)
            $fatal(1, "FAIL: signed/unsigned byte and halfword loads");
        $display("PASS: LB/LBU/LH/LHU extension and lane selection");

        // Check SB and SH data placement and byte enables for nonzero lanes.
        clear_mem();
        dmem[0] = 32'h1122_3344;
        imem[0] = enc_i(-1365,0,0,1,7'b0010011); // x1 = 0xfffffabb (overwritten below)
        imem[0] = enc_i(-1,0,0,1,7'b0010011);    // x1 = 0xffffffff
        imem[1] = enc_s(1,1,0,0);                // sb x1,1(x0)
        imem[2] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dmem[0] !== 32'h1122_FF44)
            $fatal(1, "FAIL: SB must update only selected byte lane");
        $display("PASS: SB preserves untouched byte lanes");

        clear_mem();
        dmem[0] = 32'h1122_3344;
        imem[0] = enc_i(-1,0,0,1,7'b0010011); // x1 = 0xffffffff
        imem[1] = enc_s(2,1,0,1);             // sh x1,2(x0)
        imem[2] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dmem[0] !== 32'hFFFF_3344)
            $fatal(1, "FAIL: SH must update only selected halfword");
        $display("PASS: SH lane placement and preservation");

        // SLLI with nonzero funct7 is not a supported encoding and must not
        // commit a destination register write before entering illegal halt.
        clear_mem();
        imem[0] = enc_i(32'h401,0,1,7,7'b0010011);
        start_cpu(); await_halt();
        if (!illegal_instruction || dut.regs[7] !== 32'd0)
            $fatal(1, "FAIL: unsupported SLLI encoding must trap without write");
        $display("PASS: unsupported shift-immediate encoding rejected");

        $display("Nova32 memory-edge regressions passed");
        $finish;
    end
endmodule
