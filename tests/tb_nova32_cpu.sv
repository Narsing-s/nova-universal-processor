\`timescale 1ns/1ps
module tb_nova32_cpu;
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
        if (data_we) begin
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (data_wstrb[lane])
                    dmem[data_addr[7:2]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];
        end
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
    function automatic [31:0] enc_r(input integer f7, input integer rs2, input integer rs1,
                                     input integer f3, input integer rd);
        enc_r = {f7[6:0], rs2[4:0], rs1[4:0], f3[2:0], rd[4:0], 7'b0110011};
    endfunction
    function automatic [31:0] enc_s(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] enc_b(input integer imm, input integer rs2, input integer rs1,
                                     input integer f3);
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:1], imm[11], 7'b1100011};
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
        begin
            fork
                begin wait (halted); end
                begin repeat (60) @(negedge clk); $fatal(1, "Nova32 test timeout"); end
            join_any
            disable fork;
            #1;
        end
    endtask

    initial begin
        $display("Nova32 reference core tests started");
        clear_mem();
        imem[0] = enc_i(10,0,0,1,7'b0010011); // addi x1,x0,10
        imem[1] = enc_i(20,0,0,2,7'b0010011); // addi x2,x0,20
        imem[2] = enc_r(0,2,1,0,3);           // add x3,x1,x2
        imem[3] = enc_s(0,3,0,2);             // sw x3,0(x0)
        imem[4] = enc_i(0,0,2,4,7'b0000011);// lw x4,0(x0)
        imem[5] = enc_b(8,4,3,0);             // beq x3,x4,+8
        imem[6] = enc_i(99,0,0,5,7'b0010011);// skipped
        imem[7] = enc_i(-1,0,0,6,7'b0010011);// addi x6,x0,-1
        imem[8] = enc_i(1,6,0,7,7'b0010011);// x7 = 0
        imem[9] = 32'h0000000B;               // HALT
        start_cpu(); await_halt();
        if (dut.regs[1] !== 32'd10 || dut.regs[2] !== 32'd20 || dut.regs[3] !== 32'd30)
            $fatal(1, "FAIL: Nova32 ADDI/ADD results");
        if (dut.regs[4] !== 32'd30 || dmem[0] !== 32'd30)
            $fatal(1, "FAIL: Nova32 SW/LW round trip");
        if (dut.regs[5] !== 32'd0 || dut.regs[6] !== 32'hFFFF_FFFF || dut.regs[7] !== 32'd0)
            $fatal(1, "FAIL: Nova32 branch or signed immediate behavior");
        if (illegal_instruction !== 1'b0) $fatal(1, "FAIL: legal program marked illegal");
        $display("PASS: ADDI/ADD, SW/LW, BEQ, sign extension");

        clear_mem();
        imem[0] = enc_i(7,0,0,0,7'b0010011); // attempt write x0
        imem[1] = enc_i(4,0,0,1,7'b0010011);
        imem[2] = enc_r(0,1,1,0,2);          // x2 = 8
        imem[3] = 32'h0000000B;
        start_cpu(); await_halt();
        if (dut.regs[0] !== 32'd0 || dut.regs[1] !== 32'd4 || dut.regs[2] !== 32'd8)
            $fatal(1, "FAIL: x0 hardwired zero / register writes");
        $display("PASS: x0 invariant");

        clear_mem();
        imem[0] = 32'hFFFFFFFF; // unsupported opcode
        start_cpu(); await_halt();
        if (illegal_instruction !== 1'b1 || halted !== 1'b1)
            $fatal(1, "FAIL: illegal instruction must halt and flag");
        $display("PASS: illegal instruction trap-to-halt");

        clear_mem();
        imem[0] = enc_i(3,0,0,1,7'b0010011); // x1=3
        imem[1] = enc_s(1,1,0,0);            // sb x1,1(x0)
        imem[2] = enc_i(1,0,0,2,7'b0010011); // x2=1
        imem[3] = enc_i(1,2,0,3,7'b0010011); // x3=2
        imem[4] = enc_i(0,0,2,4,7'b0000011);// lw x4,0(x0)
        imem[5] = 32'h0000000B;
        start_cpu(); await_halt();
        if (dmem[0] !== 32'h00000300) $fatal(1, "FAIL: SB lane/strobe behavior");
        $display("PASS: byte store lane handling");

        $display("Nova32 reference core tests passed");
        $finish;
    end
endmodule
