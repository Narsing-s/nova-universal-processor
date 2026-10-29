module nova32_cpu (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] instr_addr,
    input  logic [31:0] instr_rdata,

    output logic [31:0] data_addr,
    output logic [31:0] data_wdata,
    output logic [3:0]  data_wstrb,
    output logic        data_we,
    input  logic [31:0] data_rdata,

    output logic        halted,
    output logic        illegal_instruction
);
    // Nova32 reference core: single-cycle, RV32I-inspired subset.
    // This is an educational reference implementation, not a complete RV32I core.
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_REG    = 7'b0110011;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_HALT   = 7'b0001011; // Nova custom HALT

    logic [31:0] regs [0:31];
    logic [31:0] pc;
    logic [31:0] next_pc;
    logic [31:0] instruction;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rd, rs1, rs2;
    logic [31:0] rs1_value, rs2_value;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] alu_result;
    logic [31:0] effective_addr;
    logic [31:0] load_value;
    logic reg_write;
    logic branch_taken;
    logic valid_instruction;
    logic [3:0] store_strobe;
    logic [31:0] store_data;
    logic [4:0] shift_amount;

    assign instruction = instr_rdata;
    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign funct7 = instruction[31:25];
    assign rs1_value = (rs1 == 0) ? 32'd0 : regs[rs1];
    assign rs2_value = (rs2 == 0) ? 32'd0 : regs[rs2];
    assign shift_amount = instruction[24:20];

    assign imm_i = {{20{instruction[31]}}, instruction[31:20]};
    assign imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    assign imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                    instruction[30:25], instruction[11:8], 1'b0};
    assign imm_u = {instruction[31:12], 12'b0};
    assign imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                    instruction[20], instruction[30:21], 1'b0};

    assign instr_addr = pc;
    assign data_addr = effective_addr;
    assign data_wdata = store_data;
    assign data_wstrb = store_strobe;
    assign data_we = store_strobe != 4'b0000 && !halted && !reset;

    always_comb begin
        next_pc = pc + 32'd4;
        alu_result = 32'd0;
        effective_addr = rs1_value + ((opcode == OP_STORE) ? imm_s : imm_i);
        load_value = data_rdata;
        reg_write = 1'b0;
        branch_taken = 1'b0;
        valid_instruction = 1'b1;
        store_strobe = 4'b0000;
        store_data = rs2_value;

        case (opcode)
            OP_HALT: begin
                if (instruction == 32'h0000000B) begin
                    // HALT changes state in the sequential block.
                end else valid_instruction = 1'b0;
            end
            OP_LUI: begin
                alu_result = imm_u;
                reg_write = 1'b1;
            end
            OP_AUIPC: begin
                alu_result = pc + imm_u;
                reg_write = 1'b1;
            end
            OP_IMM: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: alu_result = rs1_value + imm_i; // ADDI
                    3'b010: alu_result = ($signed(rs1_value) < $signed(imm_i)) ? 32'd1 : 32'd0; // SLTI
                    3'b011: alu_result = (rs1_value < imm_i) ? 32'd1 : 32'd0; // SLTIU
                    3'b100: alu_result = rs1_value ^ imm_i; // XORI
                    3'b110: alu_result = rs1_value | imm_i; // ORI
                    3'b111: alu_result = rs1_value & imm_i; // ANDI
                    3'b001: begin
                        if (funct7 == 7'b0000000) alu_result = rs1_value << shift_amount;
                        else begin valid_instruction = 1'b0; reg_write = 1'b0; end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_result = rs1_value >> shift_amount;
                        else if (funct7 == 7'b0100000) alu_result = $signed(rs1_value) >>> shift_amount;
                        else begin valid_instruction = 1'b0; reg_write = 1'b0; end
                    end
                    default: begin valid_instruction = 1'b0; reg_write = 1'b0; end
                endcase
            end
            OP_REG: begin
                reg_write = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000,3'b000}: alu_result = rs1_value + rs2_value; // ADD
                    {7'b0100000,3'b000}: alu_result = rs1_value - rs2_value; // SUB
                    {7'b0000000,3'b001}: alu_result = rs1_value << rs2_value[4:0];
                    {7'b0000000,3'b010}: alu_result = ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0;
                    {7'b0000000,3'b011}: alu_result = (rs1_value < rs2_value) ? 32'd1 : 32'd0;
                    {7'b0000000,3'b100}: alu_result = rs1_value ^ rs2_value;
                    {7'b0000000,3'b101}: alu_result = rs1_value >> rs2_value[4:0];
                    {7'b0100000,3'b101}: alu_result = $signed(rs1_value) >>> rs2_value[4:0];
                    {7'b0000000,3'b110}: alu_result = rs1_value | rs2_value;
                    {7'b0000000,3'b111}: alu_result = rs1_value & rs2_value;
                    default: begin valid_instruction = 1'b0; reg_write = 1'b0; end
                endcase
            end
            OP_LOAD: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: begin // LB
                        case (effective_addr[1:0])
                            2'd0: load_value = {{24{data_rdata[7]}}, data_rdata[7:0]};
                            2'd1: load_value = {{24{data_rdata[15]}}, data_rdata[15:8]};
                            2'd2: load_value = {{24{data_rdata[23]}}, data_rdata[23:16]};
                            2'd3: load_value = {{24{data_rdata[31]}}, data_rdata[31:24]};
                        endcase
                    end
                    3'b100: begin // LBU
                        case (effective_addr[1:0])
                            2'd0: load_value = {24'd0, data_rdata[7:0]};
                            2'd1: load_value = {24'd0, data_rdata[15:8]};
                            2'd2: load_value = {24'd0, data_rdata[23:16]};
                            2'd3: load_value = {24'd0, data_rdata[31:24]};
                        endcase
                    end
                    3'b001: begin // LH, require halfword alignment
                        if (effective_addr[0]) begin valid_instruction = 1'b0; reg_write = 1'b0; end
                        else if (effective_addr[1]) load_value = {{16{data_rdata[31]}}, data_rdata[31:16]};
                        else load_value = {{16{data_rdata[15]}}, data_rdata[15:0]};
                    end
                    3'b101: begin // LHU
                        if (effective_addr[0]) begin valid_instruction = 1'b0; reg_write = 1'b0; end
                        else if (effective_addr[1]) load_value = {16'd0, data_rdata[31:16]};
                        else load_value = {16'd0, data_rdata[15:0]};
                    end
                    3'b010: begin // LW
                        if (effective_addr[1:0] != 2'b00) begin valid_instruction = 1'b0; reg_write = 1'b0; end
                    end
                    default: begin valid_instruction = 1'b0; reg_write = 1'b0; end
                endcase
            end
            OP_STORE: begin
                case (funct3)
                    3'b000: begin
                        store_strobe = 4'b0001 << effective_addr[1:0];
                        store_data = rs2_value << (8 * effective_addr[1:0]);
                    end
                    3'b001: begin
                        if (effective_addr[0]) valid_instruction = 1'b0;
                        else begin
                            store_strobe = effective_addr[1] ? 4'b1100 : 4'b0011;
                            store_data = rs2_value << (16 * effective_addr[1]);
                        end
                    end
                    3'b010: begin
                        if (effective_addr[1:0] != 2'b00) valid_instruction = 1'b0;
                        else store_strobe = 4'b1111;
                    end
                    default: valid_instruction = 1'b0;
                endcase
            end
            OP_BRANCH: begin
                case (funct3)
                    3'b000: branch_taken = (rs1_value == rs2_value); // BEQ
                    3'b001: branch_taken = (rs1_value != rs2_value); // BNE
                    3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value)); // BLT
                    3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value)); // BGE
                    3'b110: branch_taken = (rs1_value < rs2_value); // BLTU
                    3'b111: branch_taken = (rs1_value >= rs2_value); // BGEU
                    default: valid_instruction = 1'b0;
                endcase
                if (branch_taken) begin
                    next_pc = pc + imm_b;
                    if (next_pc[1:0] != 2'b00) valid_instruction = 1'b0;
                end
            end
            OP_JAL: begin
                alu_result = pc + 32'd4;
                reg_write = 1'b1;
                next_pc = pc + imm_j;
                if (next_pc[1:0] != 2'b00) valid_instruction = 1'b0;
            end
            OP_JALR: begin
                if (funct3 != 3'b000) valid_instruction = 1'b0;
                else begin
                    alu_result = pc + 32'd4;
                    reg_write = 1'b1;
                    next_pc = (rs1_value + imm_i) & 32'hFFFF_FFFE;
                    if (next_pc[1:0] != 2'b00) valid_instruction = 1'b0;
                end
            end
            default: valid_instruction = 1'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 32'd0;
            halted <= 1'b0;
            illegal_instruction <= 1'b0;
            for (integer i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (!halted) begin
            if (!valid_instruction) begin
                halted <= 1'b1;
                illegal_instruction <= 1'b1;
            end else if (opcode == OP_HALT) begin
                halted <= 1'b1;
            end else begin
                if (reg_write && rd != 0)
                    regs[rd] <= (opcode == OP_LOAD) ? load_value : alu_result;
                regs[0] <= 32'd0;
                pc <= next_pc;
            end
        end
    end
endmodule
