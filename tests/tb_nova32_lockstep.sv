`timescale 1ns/1ps
// Instruction-by-instruction architectural comparison against an independent
// testbench model. Covers seeded register setup and randomized legal R-type ALU ops.
module tb_nova32_lockstep;
    logic clk = 0, reset = 1;
    logic [31:0] instr_addr, instr_rdata, data_addr, data_wdata, data_rdata;
    logic [3:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];
    logic [31:0] model_regs [0:31];
    logic [31:0] insn, a, b, expected;
    logic [6:0] op, f7;
    logic [2:0] f3;
    logic [4:0] rd, rs1, rs2;
    integer seed, idx, operation, cycles;

    always #5 clk = ~clk;
    assign instr_rdata = imem[instr_addr[9:2]];
    assign data_rdata = dmem[data_addr[9:2]];
    always_ff @(posedge clk)
        if (data_we)
            for (integer lane = 0; lane < 4; lane = lane + 1)
                if (data_wstrb[lane])
                    dmem[data_addr[9:2]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];

    nova32_cpu dut (
        .clk(clk), .reset(reset), .instr_addr(instr_addr), .instr_rdata(instr_rdata),
        .data_addr(data_addr), .data_wdata(data_wdata), .data_wstrb(data_wstrb),
        .data_we(data_we), .data_rdata(data_rdata), .halted(halted),
        .illegal_instruction(illegal_instruction)
    );

    function automatic [31:0] enc_i(input integer imm, input integer src1,
                                     input integer funct3, input integer dest,
                                     input logic [6:0] opcode);
        enc_i = {imm[11:0], src1[4:0], funct3[2:0], dest[4:0], opcode};
    endfunction

    function automatic [31:0] enc_r(input logic [6:0] funct7,
                                     input integer src2, input integer src1,
                                     input logic [2:0] funct3, input integer dest);
        enc_r = {funct7, src2[4:0], src1[4:0], funct3, dest[4:0], 7'b0110011};
    endfunction

    function automatic [31:0] reference_r(input logic [6:0] funct7,
                                           input logic [2:0] funct3,
                                           input logic [31:0] lhs,
                                           input logic [31:0] rhs);
        begin
            case ({funct7, funct3})
                {7'b0000000,3'b000}: reference_r = lhs + rhs;
                {7'b0100000,3'b000}: reference_r = lhs - rhs;
                {7'b0000000,3'b001}: reference_r = lhs << rhs[4:0];
                {7'b0000000,3'b010}: reference_r = ($signed(lhs) < $signed(rhs));
                {7'b0000000,3'b011}: reference_r = (lhs < rhs);
                {7'b0000000,3'b100}: reference_r = lhs ^ rhs;
                {7'b0000000,3'b101}: reference_r = lhs >> rhs[4:0];
                {7'b0100000,3'b101}: reference_r = $signed(lhs) >>> rhs[4:0];
                {7'b0000000,3'b110}: reference_r = lhs | rhs;
                {7'b0000000,3'b111}: reference_r = lhs & rhs;
                default: reference_r = 32'hDEAD_BEEF;
            endcase
        end
    endfunction

    initial begin
        seed = 32'h32C0_FFEE;
        for (idx = 0; idx < 256; idx = idx + 1) begin
            imem[idx] = 32'h0000000B;
            dmem[idx] = 32'd0;
        end
        for (idx = 0; idx < 32; idx = idx + 1) model_regs[idx] = 32'd0;

        // Initialize eight independent source registers with varied signed values.
        for (idx = 0; idx < 8; idx = idx + 1)
            imem[idx] = enc_i((idx * 317) - 1000, 0, 0, idx + 1, 7'b0010011);

        // Deterministic pseudo-random stream of valid R-type operations.
        for (idx = 8; idx < 72; idx = idx + 1) begin
            operation = $urandom(seed) % 10;
            case (operation)
                0: begin f3 = 3'b000; f7 = 7'b0000000; end
                1: begin f3 = 3'b000; f7 = 7'b0100000; end
                2: begin f3 = 3'b001; f7 = 7'b0000000; end
                3: begin f3 = 3'b010; f7 = 7'b0000000; end
                4: begin f3 = 3'b011; f7 = 7'b0000000; end
                5: begin f3 = 3'b100; f7 = 7'b0000000; end
                6: begin f3 = 3'b101; f7 = 7'b0000000; end
                7: begin f3 = 3'b101; f7 = 7'b0100000; end
                8: begin f3 = 3'b110; f7 = 7'b0000000; end
                default: begin f3 = 3'b111; f7 = 7'b0000000; end
            endcase
            rd = $urandom(seed) % 31 + 1;
            rs1 = $urandom(seed) % 32;
            rs2 = $urandom(seed) % 32;
            imem[idx] = enc_r(f7, rs2, rs1, f3, rd);
        end
        imem[72] = 32'h0000000B;

        reset = 1;
        repeat (2) @(negedge clk);
        reset = 0;

        for (idx = 0; idx < 72; idx = idx + 1) begin
            insn = imem[idx];
            op = insn[6:0];
            rd = insn[11:7];
            f3 = insn[14:12];
            rs1 = insn[19:15];
            rs2 = insn[24:20];
            f7 = insn[31:25];
            a = model_regs[rs1];
            b = model_regs[rs2];
            if (op == 7'b0010011) begin
                expected = a + {{20{insn[31]}}, insn[31:20]};
                if (rd != 0) model_regs[rd] = expected;
            end else if (op == 7'b0110011) begin
                expected = reference_r(f7, f3, a, b);
                if (rd != 0) model_regs[rd] = expected;
            end else begin
                $fatal(1, "Testbench generated unexpected opcode at instruction %0d", idx);
            end
            model_regs[0] = 0;

            @(posedge clk);
            #1;
            if (illegal_instruction || halted)
                $fatal(1, "Unexpected trap/halt at instruction %0d", idx);
            if (instr_addr !== ((idx + 1) * 4))
                $fatal(1, "PC mismatch at instruction %0d: got %h expected %h",
                       idx, instr_addr, ((idx + 1) * 4));
            for (integer reg_idx = 0; reg_idx < 32; reg_idx = reg_idx + 1)
                if (dut.regs[reg_idx] !== model_regs[reg_idx])
                    $fatal(1, "Lockstep mismatch after instruction %0d: x%0d got %h expected %h",
                           idx, reg_idx, dut.regs[reg_idx], model_regs[reg_idx]);
        end

        @(posedge clk);
        #1;
        if (!halted || illegal_instruction)
            $fatal(1, "Expected clean HALT after randomized instruction stream");
        $display("PASS: 72 instruction-by-instruction lockstep steps (8 ADDI + 64 randomized R-type)");
        $finish;
    end
endmodule
