`timescale 1ns/1ps
// Directed control-flow and upper-immediate regression for Nova32.
module tb_nova32_control_flow;
    logic clk = 0, reset = 1;
    logic [31:0] instr_addr, instr_rdata, data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    always #5 clk = ~clk;
    assign instr_rdata = imem[instr_addr[7:2]];
    assign data_rdata = dmem[data_addr[7:2]];
    always_ff @(posedge clk)
        if (data_we)
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (data_wstrb[lane])
                    dmem[data_addr[7:2]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];

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
    function automatic [31:0] enc_b(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], f3[2:0],
                 imm[4:1], imm[11], 7'b1100011};
    endfunction
    function automatic [31:0] enc_u(input logic [6:0] op, input integer rd, input logic [19:0] value);
        enc_u = {value, rd[4:0], op};
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
            while (!halted && cycles < 40) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!halted) $fatal(1, "Nova32 control-flow test timeout");
            #1;
        end
    endtask

    initial begin
        $display("Nova32 control-flow regressions started");

        // Taken BEQ skips one instruction; not-taken BNE falls through.
        clear_mem();
        imem[0] = enc_i(5,0,0,1,7'b0010011);  // addi x1,x0,5
        imem[1] = enc_i(5,0,0,2,7'b0010011);  // addi x2,x0,5
        imem[2] = enc_b(8,2,1,0);             // beq x1,x2,+8
        imem[3] = enc_i(99,0,0,3,7'b0010011); // skipped
        imem[4] = enc_i(7,0,0,3,7'b0010011);  // reached
        imem[5] = enc_b(8,2,1,1);             // bne false: fall through
        imem[6] = enc_i(12,0,0,4,7'b0010011);
        imem[7] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dut.regs[3] !== 7 || dut.regs[4] !== 12)
            $fatal(1, "FAIL: BEQ/BNE taken and fall-through behavior");
        $display("PASS: BEQ taken and BNE not taken");

        // Signed BLT and unsigned BGEU differ for 0xffffffff and 1.
        clear_mem();
        imem[0] = enc_i(-1,0,0,1,7'b0010011);  // x1 = -1
        imem[1] = enc_i(1,0,0,2,7'b0010011);   // x2 = 1
        imem[2] = enc_b(8,2,1,4);              // blt signed(-1,1), taken
        imem[3] = enc_i(99,0,0,3,7'b0010011);  // skipped
        imem[4] = enc_i(8,0,0,3,7'b0010011);   // reached
        imem[5] = enc_b(8,2,1,7);              // bgeu 0xffffffff >= 1, taken
        imem[6] = enc_i(99,0,0,4,7'b0010011);  // skipped
        imem[7] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dut.regs[3] !== 8 || dut.regs[4] !== 0)
            $fatal(1, "FAIL: signed/unsigned branch comparison");
        $display("PASS: signed BLT and unsigned BGEU");

        // LUI builds a constant; AUIPC adds the current instruction PC.
        clear_mem();
        imem[0] = enc_u(7'b0110111,1,20'hABCDE); // lui x1,0xabcde
        imem[1] = enc_u(7'b0010111,2,20'h00001); // auipc x2,1 at PC=4
        imem[2] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dut.regs[1] !== 32'hABCDE000 ||
            dut.regs[2] !== 32'h00001004)
            $fatal(1, "FAIL: LUI/AUIPC immediate semantics");
        $display("PASS: LUI and AUIPC semantics");

        // x0 must remain zero even when an instruction targets it.
        clear_mem();
        imem[0] = enc_i(123,0,0,0,7'b0010011);
        imem[1] = enc_i(9,0,0,1,7'b0010011);
        imem[2] = 32'h0000000B;
        start_cpu(); await_halt();
        if (illegal_instruction || dut.regs[0] !== 0 || dut.regs[1] !== 9)
            $fatal(1, "FAIL: x0 hardwired-zero invariant");
        $display("PASS: x0 remains hardwired to zero");

        $display("Nova32 control-flow regressions passed");
        $finish;
    end
endmodule
