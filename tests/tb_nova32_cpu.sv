`timescale 1ns/1ps
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
    function automatic [31:0] enc_j(input integer imm, input integer rd);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], 7'b1101111};
    endfunction

    // Independent behavioral oracle for the implemented R-type ALU subset.
    function automatic [31:0] reference_r(input integer f7, input integer f3,
                                           input logic [31:0] a, input logic [31:0] b);
        begin
            case ({f7[6:0], f3[2:0]})
                {7'b0000000,3'b000}: reference_r = a + b;
                {7'b0100000,3'b000}: reference_r = a - b;
                {7'b0000000,3'b001}: reference_r = a << b[4:0];
                {7'b0000000,3'b010}: reference_r = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
                {7'b0000000,3'b011}: reference_r = (a < b) ? 32'd1 : 32'd0;
                {7'b0000000,3'b100}: reference_r = a ^ b;
                {7'b0000000,3'b101}: reference_r = a >> b[4:0];
                {7'b0100000,3'b101}: reference_r = $signed(a) >>> b[4:0];
                {7'b0000000,3'b110}: reference_r = a | b;
                {7'b0000000,3'b111}: reference_r = a & b;
                default: reference_r = 32'hDEAD_BEEF;
            endcase
        end
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
            while (!halted && cycles < 60) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!halted) $fatal(1, "Nova32 test timeout");
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

        // JAL must save PC+4 and skip the sequential instruction.
        clear_mem();
        imem[0] = enc_j(8,1);                 // jal x1,+8
        imem[1] = enc_i(99,0,0,2,7'b0010011);// skipped
        imem[2] = enc_i(9,0,0,3,7'b0010011);// reached at PC=8
        imem[3] = 32'h0000000B;
        start_cpu(); await_halt();
        if (dut.regs[1] !== 32'd4 || dut.regs[2] !== 32'd0 || dut.regs[3] !== 32'd9)
            $fatal(1, "FAIL: JAL target/link behavior");
        $display("PASS: JAL target and link address");

        // JALR clears bit 0, then Nova32 enforces 4-byte instruction alignment.
        clear_mem();
        imem[0] = enc_i(12,0,0,1,7'b0010011);// x1=12
        imem[1] = enc_i(0,1,0,5,7'b1100111); // jalr x5,0(x1)
        imem[2] = enc_i(99,0,0,2,7'b0010011);// skipped
        imem[3] = enc_i(42,0,0,6,7'b0010011);// target
        imem[4] = 32'h0000000B;
        start_cpu(); await_halt();
        if (dut.regs[5] !== 32'd8 || dut.regs[2] !== 32'd0 || dut.regs[6] !== 32'd42)
            $fatal(1, "FAIL: JALR target/link behavior");
        $display("PASS: JALR target and link address");

        // Misaligned halfword load must halt without modifying rd.
        clear_mem();
        imem[0] = enc_i(7,0,0,1,7'b0010011);// sentinel
        imem[1] = enc_i(1,0,1,1,7'b0000011);// lh x1,1(x0): misaligned
        start_cpu(); await_halt();
        if (!illegal_instruction || dut.regs[1] !== 32'd7)
            $fatal(1, "FAIL: misaligned LH must trap without register write");
        $display("PASS: misaligned halfword load rejected");

        // Misaligned word store must not assert a write strobe or alter memory.
        clear_mem();
        imem[0] = enc_i(55,0,0,1,7'b0010011);// x1=55
        imem[1] = enc_s(2,1,0,2);             // sw x1,2(x0): misaligned
        start_cpu(); await_halt();
        if (!illegal_instruction || dmem[0] !== 32'd0)
            $fatal(1, "FAIL: misaligned SW must trap without modifying memory");
        $display("PASS: misaligned word store rejected");

        // JAL target with only 2-byte alignment is illegal because Nova32 has no C extension.
        clear_mem();
        imem[0] = enc_j(2,1);                 // jal x1,+2
        start_cpu(); await_halt();
        if (!illegal_instruction || dut.regs[1] !== 32'd0)
            $fatal(1, "FAIL: misaligned JAL target must trap without link write");
        $display("PASS: misaligned jump target rejected");

        // Differential-style ALU check: compare the RTL register file against
        // a separate behavioral oracle for each supported R-type operation.
        clear_mem();
        imem[0] = enc_i(-15,0,0,1,7'b0010011); // x1 = 0xfffffff1
        imem[1] = enc_i(7,0,0,2,7'b0010011);   // x2 = 7
        imem[2] = enc_r(0,2,1,0,3);            // ADD
        imem[3] = enc_r(32,2,1,0,4);           // SUB
        imem[4] = enc_r(0,2,1,1,5);            // SLL
        imem[5] = enc_r(0,2,1,2,6);            // SLT
        imem[6] = enc_r(0,2,1,3,7);            // SLTU
        imem[7] = enc_r(0,2,1,4,8);            // XOR
        imem[8] = enc_r(0,2,1,5,9);            // SRL
        imem[9] = enc_r(32,2,1,5,10);          // SRA
        imem[10] = enc_r(0,2,1,6,11);          // OR
        imem[11] = enc_r(0,2,1,7,12);          // AND
        imem[12] = 32'h0000000B;
        start_cpu(); await_halt();
        if (dut.regs[3] !== reference_r(0,0,32'hFFFF_FFF1,32'd7) ||
            dut.regs[4] !== reference_r(32,0,32'hFFFF_FFF1,32'd7) ||
            dut.regs[5] !== reference_r(0,1,32'hFFFF_FFF1,32'd7) ||
            dut.regs[6] !== reference_r(0,2,32'hFFFF_FFF1,32'd7) ||
            dut.regs[7] !== reference_r(0,3,32'hFFFF_FFF1,32'd7) ||
            dut.regs[8] !== reference_r(0,4,32'hFFFF_FFF1,32'd7) ||
            dut.regs[9] !== reference_r(0,5,32'hFFFF_FFF1,32'd7) ||
            dut.regs[10] !== reference_r(32,5,32'hFFFF_FFF1,32'd7) ||
            dut.regs[11] !== reference_r(0,6,32'hFFFF_FFF1,32'd7) ||
            dut.regs[12] !== reference_r(0,7,32'hFFFF_FFF1,32'd7))
            $fatal(1, "FAIL: Nova32 R-type ALU disagrees with behavioral reference");
        $display("PASS: R-type ALU differential oracle (10 operations)");

        $display("Nova32 reference core tests passed");
        $finish;
    end
endmodule
