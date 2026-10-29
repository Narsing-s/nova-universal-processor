`timescale 1ns/1ps
// Directed architectural regression spanning memory lanes, branches and jumps.
module tb_nova32_memory_control;
    logic clk = 0, reset = 1;
    logic [31:0] instr_addr, instr_rdata, data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];
    integer cycles;

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
    function automatic [31:0] enc_s(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] enc_b(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], f3[2:0],
                 imm[4:1], imm[11], 7'b1100011};
    endfunction
    function automatic [31:0] enc_j(input integer imm, input integer rd);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], 7'b1101111};
    endfunction

    always @(negedge clk) begin
        if (!reset) begin
            if (dut.regs[0] !== 32'd0)
                $fatal(1, "Assertion failed: x0 must remain zero");
            if (data_we && data_wstrb == 4'b0000)
                $fatal(1, "Assertion failed: write enable without byte lanes");
            if (!data_we && data_wstrb != 4'b0000)
                $fatal(1, "Assertion failed: byte lanes asserted without write enable");
        end
    end

    initial begin
        for (integer i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h0000000B;
            dmem[i] = 32'd0;
        end
        // Seed word, then exercise LW, SB, signed/unsigned loads and halfword loads.
        imem[0]  = enc_i(16'h123, 0, 0, 1, 7'b0010011); // x1=0x123
        imem[1]  = enc_s(0, 1, 0, 2);                  // sw x1,0(x0)
        imem[2]  = enc_i(0, 0, 2, 2, 7'b0000011);     // lw x2,0(x0)
        imem[3]  = enc_i(127, 0, 0, 3, 7'b0010011);   // x3=127
        imem[4]  = enc_s(1, 3, 0, 0);                  // sb x3,1(x0)
        imem[5]  = enc_i(1, 0, 4, 4, 7'b0000011);     // lbu x4,1(x0)
        imem[6]  = enc_i(1, 0, 0, 5, 7'b0000011);     // lb x5,1(x0)
        imem[7]  = enc_i(-1, 0, 0, 6, 7'b0010011);    // x6=-1
        imem[8]  = enc_s(2, 6, 0, 0);                  // sb x6,2(x0)
        imem[9]  = enc_i(2, 0, 0, 7, 7'b0000011);     // lb x7,2(x0)
        imem[10] = enc_i(2, 0, 4, 8, 7'b0000011);     // lbu x8,2(x0)
        imem[11] = enc_i(0, 0, 1, 9, 7'b0000011);     // lh x9,0(x0)
        imem[12] = enc_i(2, 0, 5, 10, 7'b0000011);    // lhu x10,2(x0)
        imem[13] = enc_b(8, 4, 4, 0);                  // beq x4,x4,+8
        imem[14] = enc_i(1, 0, 0, 11, 7'b0010011);    // skipped
        imem[15] = enc_i(2, 0, 0, 11, 7'b0010011);    // x11=2
        imem[16] = enc_j(8, 12);                       // jal x12,+8
        imem[17] = enc_i(99, 0, 0, 13, 7'b0010011);   // skipped
        imem[18] = enc_i(7, 0, 0, 13, 7'b0010011);    // x13=7
        imem[19] = enc_i(88, 0, 0, 14, 7'b0010011);   // x14=target PC 88
        imem[20] = enc_i(0, 14, 0, 15, 7'b1100111);   // jalr x15,0(x14)
        imem[21] = enc_i(99, 0, 0, 16, 7'b0010011);   // skipped
        imem[22] = enc_i(42, 0, 0, 16, 7'b0010011);   // x16=42
        imem[23] = 32'h0000000B;                       // custom HALT

        repeat (2) @(negedge clk);
        reset = 0;
        cycles = 0;
        while (!halted && cycles < 80) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        #1;
        if (!halted) $fatal(1, "Timeout waiting for HALT");
        if (illegal_instruction) $fatal(1, "Unexpected illegal instruction");
        if (dmem[0] !== 32'h00FF7F23) $fatal(1, "Memory lane preservation mismatch: %h", dmem[0]);
        if (dut.regs[1] !== 32'h00000123 || dut.regs[2] !== 32'h00000123)
            $fatal(1, "SW/LW architectural mismatch");
        if (dut.regs[4] !== 127 || dut.regs[5] !== 127 || dut.regs[7] !== 32'hFFFF_FFFF ||
            dut.regs[8] !== 255 || dut.regs[9] !== 32'h00007F23 || dut.regs[10] !== 255)
            $fatal(1, "Signed/unsigned load mismatch");
        if (dut.regs[11] !== 2 || dut.regs[12] !== 68 || dut.regs[13] !== 7 ||
            dut.regs[14] !== 88 || dut.regs[15] !== 80 || dut.regs[16] !== 42)
            $fatal(1, "Branch/JAL/JALR mismatch x11=%h x12=%h x13=%h x14=%h x15=%h x16=%h", dut.regs[11], dut.regs[12], dut.regs[13], dut.regs[14], dut.regs[15], dut.regs[16]);
        $display("PASS: memory loads/stores, x0/write-lane assertions, BEQ, JAL, JALR");
        $finish;
    end
endmodule
