module nova_cpu (
    input  logic       clk,
    input  logic       reset,
    output logic [7:0] r0,
    output logic [7:0] r1,
    output logic [7:0] r2,
    output logic [7:0] r3,
    output logic       carry_flag,
    output logic       zero_flag,
    output logic       overflow_flag,
    output logic       halted
);
    // Nova v0.3 educational 8-bit CPU.
    // 16-bit instruction: opcode [15:12], operands depend on opcode.
    logic [3:0] pc;
    logic [15:0] rom [0:15];
    logic [7:0] data_mem [0:15];
    logic [15:0] instruction;
    logic [7:0] regs [0:3];
    logic [1:0] rd, rs, rt;
    logic [3:0] address;
    logic [3:0] data_sp;
    logic [3:0] call_sp;
    logic [3:0] call_stack [0:15];
    logic [7:0] value_a, value_b;
    logic [8:0] add_result;
    logic [7:0] sub_result;
    logic signed [8:0] signed_a, signed_b, signed_result;

    assign instruction = rom[pc];
    assign rd = instruction[11:10];
    assign rs = instruction[9:8];
    assign rt = instruction[7:6];
    assign address = instruction[3:0];
    assign value_a = regs[rs];
    assign value_b = regs[rt];
    assign add_result = {1'b0, value_a} + {1'b0, value_b};
    assign sub_result = value_a - value_b;
    assign signed_a = {value_a[7], value_a};
    assign signed_b = {value_b[7], value_b};
    assign signed_result = signed_a + signed_b;

    assign r0 = regs[0];
    assign r1 = regs[1];
    assign r2 = regs[2];
    assign r3 = regs[3];

    initial begin
        // Demonstration: arithmetic, memory, branch, carry, PUSH/POP.
        rom[0]  = 16'h1005; // LI r0, 5
        rom[1]  = 16'h1403; // LI r1, 3
        rom[2]  = 16'h2840; // ADD r2, r0, r1 => 8
        rom[3]  = 16'h5801; // STORE r2, [1]
        rom[4]  = 16'h4C01; // LOAD r3, [1] => 8
        rom[5]  = 16'h6C80; // CMP r3, r2
        rom[6]  = 16'h7008; // BEQ 8
        rom[7]  = 16'h1000; // skipped LI r0, 0
        rom[8]  = 16'h3F40; // SUB r3, r3, r1 => 5
        rom[9]  = 16'h10FA; // LI r0, 250
        rom[10] = 16'h140A; // LI r1, 10
        rom[11] = 16'h2840; // ADD r2, r0, r1 => 4, carry set
        rom[12] = 16'hB800; // PUSH r2
        rom[13] = 16'h1800; // LI r2, 0
        rom[14] = 16'hC800; // POP r2 => 4
        rom[15] = 16'hF000; // HALT
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 4'd0;
            data_sp <= 4'd0;
            call_sp <= 4'd0;
            halted <= 1'b0;
            carry_flag <= 1'b0;
            zero_flag <= 1'b0;
            overflow_flag <= 1'b0;
            for (integer i = 0; i < 4; i = i + 1)
                regs[i] <= 8'd0;
            for (integer j = 0; j < 16; j = j + 1) begin
                data_mem[j] <= 8'd0;
                call_stack[j] <= 4'd0;
            end
        end else if (!halted) begin
            case (instruction[15:12])
                4'h0: begin // NOP/XOR/NOT extension
                    case (instruction[11:10])
                        2'b00: pc <= pc + 1'b1;
                        2'b01: begin
                            regs[instruction[9:8]] <= regs[instruction[7:6]] ^ regs[instruction[5:4]];
                            zero_flag <= ((regs[instruction[7:6]] ^ regs[instruction[5:4]]) == 8'd0);
                            pc <= pc + 1'b1;
                        end
                        2'b10: begin
                            regs[instruction[9:8]] <= ~regs[instruction[7:6]];
                            zero_flag <= (~regs[instruction[7:6]] == 8'd0);
                            pc <= pc + 1'b1;
                        end
                        default: halted <= 1'b1;
                    endcase
                end
                4'h1: begin // LI Rd, imm8
                    regs[rd] <= instruction[7:0];
                    zero_flag <= (instruction[7:0] == 8'd0);
                    pc <= pc + 1'b1;
                end
                4'h2: begin // ADD Rd, Rs, Rt
                    regs[rd] <= add_result[7:0];
                    carry_flag <= add_result[8];
                    zero_flag <= (add_result[7:0] == 8'd0);
                    overflow_flag <= (signed_result > 9'sd127) || (signed_result < -9'sd128);
                    pc <= pc + 1'b1;
                end
                4'h3: begin // SUB Rd, Rs, Rt
                    regs[rd] <= sub_result;
                    carry_flag <= (value_a >= value_b); // 1 means no borrow
                    zero_flag <= (sub_result == 8'd0);
                    overflow_flag <= ((value_a[7] != value_b[7]) && (sub_result[7] != value_a[7]));
                    pc <= pc + 1'b1;
                end
                4'h4: begin // LOAD Rd, [addr]
                    regs[rd] <= data_mem[address];
                    zero_flag <= (data_mem[address] == 8'd0);
                    pc <= pc + 1'b1;
                end
                4'h5: begin // STORE Rd, [addr]
                    data_mem[address] <= regs[rd];
                    pc <= pc + 1'b1;
                end
                4'h6: begin // CMP Rd, Rt
                    zero_flag <= (regs[rd] == regs[rt]);
                    carry_flag <= (regs[rd] >= regs[rt]);
                    overflow_flag <= 1'b0;
                    pc <= pc + 1'b1;
                end
                4'h7: begin // BEQ absolute address if zero flag
                    if (zero_flag) pc <= instruction[3:0];
                    else pc <= pc + 1'b1;
                end
                4'h8: pc <= instruction[3:0]; // JMP
                4'h9: begin // CALL absolute 4-bit address
                    if (call_sp != 4'hF) begin
                        call_stack[call_sp] <= pc + 1'b1;
                        call_sp <= call_sp + 1'b1;
                        pc <= instruction[3:0];
                    end else halted <= 1'b1;
                end
                4'hA: begin // RET
                    if (call_sp != 0) begin
                        call_sp <= call_sp - 1'b1;
                        pc <= call_stack[call_sp - 1'b1];
                    end else begin
                        halted <= 1'b1; // empty return stack is an error-stop
                    end
                end
                4'hB: begin // PUSH Rd to independent data stack
                    if (data_sp != 4'hF) begin
                        data_mem[data_sp] <= regs[rd];
                        data_sp <= data_sp + 1'b1;
                        pc <= pc + 1'b1;
                    end else halted <= 1'b1; // stack overflow protection
                end
                4'hD: begin // AND Rd, Rs, Rt
                    regs[rd] <= regs[rs] & regs[rt];
                    zero_flag <= ((regs[rs] & regs[rt]) == 8'd0);
                    pc <= pc + 1'b1;
                end
                4'hE: begin // OR Rd, Rs, Rt
                    regs[rd] <= regs[rs] | regs[rt];
                    zero_flag <= ((regs[rs] | regs[rt]) == 8'd0);
                    pc <= pc + 1'b1;
                end
                4'hC: begin // POP into Rd
                    if (data_sp != 0) begin
                        regs[rd] <= data_mem[data_sp - 1'b1];
                        data_sp <= data_sp - 1'b1;
                        pc <= pc + 1'b1;
                    end else halted <= 1'b1; // stack underflow protection
                end
                4'hF: halted <= 1'b1; // HALT
                default: halted <= 1'b1; // illegal opcode stops safely
            endcase
        end
    end
endmodule
