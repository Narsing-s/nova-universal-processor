module nova_cpu (
    input  logic       clk,
    input  logic       reset,
    output logic [7:0] r0,
    output logic [7:0] r1,
    output logic [7:0] r2,
    output logic [7:0] r3,
    output logic       halted
);

    // Nova v0.2: 4 x 8-bit registers, 16-byte data RAM, 16-word ROM.
    // Instruction format: [15:12] opcode, remaining fields depend on opcode.
    logic [3:0] pc;
    logic [15:0] rom [0:15];
    logic [7:0] data_mem [0:15];
    logic [15:0] instruction;
    logic zero_flag;

    logic [7:0] regs [0:3];
    logic [1:0] rd, rs, rt;
    logic [3:0] address;

    assign instruction = rom[pc];
    assign rd = instruction[11:10];
    assign rs = instruction[9:8];
    assign rt = instruction[7:6];
    assign address = instruction[3:0];

    assign r0 = regs[0];
    assign r1 = regs[1];
    assign r2 = regs[2];
    assign r3 = regs[3];

    initial begin
        // LI Rd, imm8; ADD Rd, Rs, Rt; STORE Rs, addr;
        // LOAD Rd, addr; CMP Rs, Rt; BEQ addr; SUB Rd, Rs, Rt; HALT
        rom[0]  = 16'h1005; // LI r0, 5
        rom[1]  = 16'h1403; // LI r1, 3
        rom[2]  = 16'h2840; // ADD r2, r0, r1 => 8
        rom[3]  = 16'h5801; // STORE r2, [1]
        rom[4]  = 16'h4C01; // LOAD r3, [1] => 8
        rom[5]  = 16'h6C80; // CMP r3, r2 => zero flag set
        rom[6]  = 16'h7008; // BEQ 8 (skip next instruction)
        rom[7]  = 16'h1000; // LI r0, 0 (must be skipped)
        rom[8]  = 16'h3F40; // SUB r3, r3, r1 => 5
        rom[9]  = 16'hF000; // HALT
        for (integer i = 10; i < 16; i = i + 1)
            rom[i] = 16'hF000;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 4'd0;
            halted <= 1'b0;
            zero_flag <= 1'b0;
            for (integer i = 0; i < 4; i = i + 1)
                regs[i] <= 8'd0;
            for (integer j = 0; j < 16; j = j + 1)
                data_mem[j] <= 8'd0;
        end else if (!halted) begin
            case (instruction[15:12])
                4'h0: pc <= pc + 1'b1; // NOP

                4'h1: begin // LI Rd, imm8
                    regs[rd] <= instruction[7:0];
                    pc <= pc + 1'b1;
                end

                4'h2: begin // ADD Rd, Rs, Rt
                    regs[rd] <= regs[rs] + regs[rt];
                    zero_flag <= ((regs[rs] + regs[rt]) == 8'd0);
                    pc <= pc + 1'b1;
                end

                4'h3: begin // SUB Rd, Rs, Rt
                    regs[rd] <= regs[rs] - regs[rt];
                    zero_flag <= ((regs[rs] - regs[rt]) == 8'd0);
                    pc <= pc + 1'b1;
                end

                4'h4: begin // LOAD Rd, [addr]
                    regs[rd] <= data_mem[address];
                    pc <= pc + 1'b1;
                end

                4'h5: begin // STORE Rs, [addr]
                    data_mem[address] <= regs[rd];
                    pc <= pc + 1'b1;
                end

                4'h6: begin // CMP Rs, Rt
                    zero_flag <= (regs[rd] == regs[rt]);
                    pc <= pc + 1'b1;
                end

                4'h7: begin // BEQ absolute address when zero_flag is set
                    if (zero_flag)
                        pc <= instruction[3:0];
                    else
                        pc <= pc + 1'b1;
                end

                4'h8: pc <= instruction[3:0]; // JMP absolute address

                4'hF: halted <= 1'b1; // HALT

                default: halted <= 1'b1;
            endcase
        end
    end

endmodule
