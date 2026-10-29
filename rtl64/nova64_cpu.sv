module nova64_cpu (
    input  logic        clk,
    input  logic        reset,
    output logic [63:0] instr_addr,
    input  logic [31:0] instr_rdata,
    output logic [63:0] data_addr,
    output logic [63:0] data_wdata,
    output logic [7:0]  data_wstrb,
    output logic        data_we,
    input  logic [63:0] data_rdata,
    output logic        halted,
    output logic        illegal_instruction
);
    // Nova64 is an experimental, single-cycle RV64I-inspired reference core.
    // It is not yet a complete RV64I implementation or a physically optimized CPU.
    localparam logic [6:0] OP_LOAD=7'b0000011, OP_IMM=7'b0010011,
        OP_AUIPC=7'b0010111, OP_STORE=7'b0100011, OP_REG=7'b0110011,
        OP_LUI=7'b0110111, OP_BRANCH=7'b1100011, OP_JALR=7'b1100111,
        OP_JAL=7'b1101111, OP_HALT=7'b0001011;

    logic [63:0] regs [0:31];
    logic [63:0] pc, next_pc, rs1_value, rs2_value;
    logic [63:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [63:0] alu_result, effective_addr, load_value;
    logic [31:0] instruction;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic [4:0] rd, rs1, rs2;
    logic [5:0] shift_amount;
    logic reg_write, branch_taken, valid_instruction;
    logic [7:0] store_strobe;
    logic [63:0] store_data;
    integer lane;

    assign instruction = instr_rdata;
    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign funct7 = instruction[31:25];
    assign rs1_value = (rs1 == 0) ? 64'd0 : regs[rs1];
    assign rs2_value = (rs2 == 0) ? 64'd0 : regs[rs2];
    assign shift_amount = instruction[25:20];

    assign imm_i = {{52{instruction[31]}}, instruction[31:20]};
    assign imm_s = {{52{instruction[31]}}, instruction[31:25], instruction[11:7]};
    assign imm_b = {{51{instruction[31]}}, instruction[31], instruction[7],
                    instruction[30:25], instruction[11:8], 1'b0};
    assign imm_u = {{32{instruction[31]}}, instruction[31:12], 12'b0};
    assign imm_j = {{43{instruction[31]}}, instruction[31], instruction[19:12],
                    instruction[20], instruction[30:21], 1'b0};

    assign instr_addr = pc;
    assign data_addr = {effective_addr[63:3], 3'b000};
    assign data_wdata = store_data;
    assign data_wstrb = store_strobe;
    assign data_we = (store_strobe != 8'b0) && !halted && !reset;

    always_comb begin
        next_pc = pc + 64'd4;
        alu_result = 64'd0;
        effective_addr = rs1_value + ((opcode == OP_STORE) ? imm_s : imm_i);
        load_value = data_rdata >> (8 * effective_addr[2:0]);
        reg_write = 1'b0;
        branch_taken = 1'b0;
        valid_instruction = 1'b1;
        store_strobe = 8'b0;
        store_data = rs2_value << (8 * effective_addr[2:0]);

        case (opcode)
            OP_HALT: if (instruction != 32'h0000000B) valid_instruction = 1'b0;
            OP_LUI: begin alu_result = imm_u; reg_write = 1'b1; end
            OP_AUIPC: begin alu_result = pc + imm_u; reg_write = 1'b1; end
            OP_IMM: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: alu_result = rs1_value + imm_i;
                    3'b010: alu_result = ($signed(rs1_value) < $signed(imm_i)) ? 64'd1 : 64'd0;
                    3'b011: alu_result = (rs1_value < imm_i) ? 64'd1 : 64'd0;
                    3'b100: alu_result = rs1_value ^ imm_i;
                    3'b110: alu_result = rs1_value | imm_i;
                    3'b111: alu_result = rs1_value & imm_i;
                    3'b001: begin
                        if (instruction[31:26] == 6'b0) alu_result = rs1_value << shift_amount;
                        else begin valid_instruction=1'b0; reg_write=1'b0; end
                    end
                    3'b101: begin
                        if (instruction[31:26] == 6'b0) alu_result = rs1_value >> shift_amount;
                        else if (instruction[31:26] == 6'b010000) alu_result = $signed(rs1_value) >>> shift_amount;
                        else begin valid_instruction=1'b0; reg_write=1'b0; end
                    end
                    default: begin valid_instruction=1'b0; reg_write=1'b0; end
                endcase
            end
            OP_REG: begin
                reg_write = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000,3'b000}: alu_result = rs1_value + rs2_value;
                    {7'b0100000,3'b000}: alu_result = rs1_value - rs2_value;
                    {7'b0000000,3'b001}: alu_result = rs1_value << rs2_value[5:0];
                    {7'b0000000,3'b010}: alu_result = ($signed(rs1_value) < $signed(rs2_value)) ? 64'd1 : 64'd0;
                    {7'b0000000,3'b011}: alu_result = (rs1_value < rs2_value) ? 64'd1 : 64'd0;
                    {7'b0000000,3'b100}: alu_result = rs1_value ^ rs2_value;
                    {7'b0000000,3'b101}: alu_result = rs1_value >> rs2_value[5:0];
                    {7'b0100000,3'b101}: alu_result = $signed(rs1_value) >>> rs2_value[5:0];
                    {7'b0000000,3'b110}: alu_result = rs1_value | rs2_value;
                    {7'b0000000,3'b111}: alu_result = rs1_value & rs2_value;
                    default: begin valid_instruction=1'b0; reg_write=1'b0; end
                endcase
            end
            OP_LOAD: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: load_value = {{56{load_value[7]}}, load_value[7:0]}; // LB
                    3'b001: begin
                        if (effective_addr[0]) begin valid_instruction=1'b0; reg_write=1'b0; end
                        else load_value = {{48{load_value[15]}}, load_value[15:0]};
                    end
                    3'b010: begin
                        if (effective_addr[1:0] != 0) begin valid_instruction=1'b0; reg_write=1'b0; end
                        else load_value = {{32{load_value[31]}}, load_value[31:0]};
                    end
                    3'b011: begin
                        if (effective_addr[2:0] != 0) begin valid_instruction=1'b0; reg_write=1'b0; end
                    end
                    3'b100: load_value = {56'd0, load_value[7:0]}; // LBU
                    3'b101: begin
                        if (effective_addr[0]) begin valid_instruction=1'b0; reg_write=1'b0; end
                        else load_value = {48'd0, load_value[15:0]};
                    end
                    3'b110: begin
                        if (effective_addr[1:0] != 0) begin valid_instruction=1'b0; reg_write=1'b0; end
                        else load_value = {32'd0, load_value[31:0]};
                    end
                    default: begin valid_instruction=1'b0; reg_write=1'b0; end
                endcase
            end
            OP_STORE: begin
                case (funct3)
                    3'b000: store_strobe = 8'b00000001 << effective_addr[2:0];
                    3'b001: begin
                        if (effective_addr[0]) valid_instruction=1'b0;
                        else store_strobe = 8'b00000011 << effective_addr[2:0];
                    end
                    3'b010: begin
                        if (effective_addr[1:0] != 0) valid_instruction=1'b0;
                        else store_strobe = 8'b00001111 << effective_addr[2:0];
                    end
                    3'b011: begin
                        if (effective_addr[2:0] != 0) valid_instruction=1'b0;
                        else store_strobe = 8'hFF;
                    end
                    default: valid_instruction=1'b0;
                endcase
            end
            OP_BRANCH: begin
                case (funct3)
                    3'b000: branch_taken = (rs1_value == rs2_value);
                    3'b001: branch_taken = (rs1_value != rs2_value);
                    3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value));
                    3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));
                    3'b110: branch_taken = (rs1_value < rs2_value);
                    3'b111: branch_taken = (rs1_value >= rs2_value);
                    default: valid_instruction=1'b0;
                endcase
                if (branch_taken) begin
                    next_pc = pc + imm_b;
                    if (next_pc[1:0] != 0) valid_instruction=1'b0;
                end
            end
            OP_JAL: begin
                alu_result = pc + 64'd4; reg_write=1'b1; next_pc=pc+imm_j;
                if (next_pc[1:0] != 0) valid_instruction=1'b0;
            end
            OP_JALR: begin
                if (funct3 != 0) valid_instruction=1'b0;
                else begin
                    alu_result=pc+64'd4; reg_write=1'b1;
                    next_pc=(rs1_value+imm_i) & 64'hFFFF_FFFF_FFFF_FFFE;
                    if (next_pc[1:0] != 0) valid_instruction=1'b0;
                end
            end
            default: valid_instruction=1'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 64'd0;
            halted <= 1'b0;
            illegal_instruction <= 1'b0;
            for (integer i=0; i<32; i=i+1) regs[i] <= 64'd0;
        end else if (!halted) begin
            if (!valid_instruction) begin halted<=1'b1; illegal_instruction<=1'b1; end
            else if (opcode == OP_HALT) halted<=1'b1;
            else begin
                if (reg_write && rd != 0)
                    regs[rd] <= (opcode == OP_LOAD) ? load_value : alu_result;
                regs[0] <= 64'd0;
                pc <= next_pc;
            end
        end
    end
endmodule
