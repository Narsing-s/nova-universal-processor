module nova64_pipeline_cpu (
    input logic clk, reset,
    output logic [63:0] instr_addr,
    input logic [31:0] instr_rdata,
    output logic [63:0] data_addr,
    output logic [63:0] data_wdata,
    output logic [7:0] data_wstrb,
    output logic data_we,
    input logic [63:0] data_rdata,
    output logic halted,
    output logic illegal_instruction
);
    localparam logic [6:0] OP_LOAD=7'b0000011, OP_IMM=7'b0010011,
        OP_AUIPC=7'b0010111, OP_STORE=7'b0100011, OP_REG=7'b0110011,
        OP_LUI=7'b0110111, OP_BRANCH=7'b1100011, OP_JALR=7'b1100111,
        OP_JAL=7'b1101111, OP_HALT=7'b0001011;

    logic [63:0] pc, ifid_pc, idex_pc, idex_a, idex_b, idex_imm;
    logic [63:0] regs [0:31];
    logic [31:0] ifid_instr, idex_instr;
    logic ifid_valid, idex_valid, exmem_valid, memwb_valid;
    logic [4:0] idex_rs1, idex_rs2, idex_rd, exmem_rd, memwb_rd;
    logic idex_regwrite, idex_memread, idex_memwrite, idex_memtoreg;
    logic idex_branch, idex_jal, idex_jalr, idex_alu_imm;
    logic [2:0] idex_funct3;
    logic [63:0] exmem_alu, exmem_store_data, memwb_value;
    logic [7:0] exmem_wstrb, ex_store_strobe;
    logic [2:0] exmem_funct3;
    logic exmem_memwrite, exmem_memread, exmem_regwrite, exmem_memtoreg, exmem_halt, memwb_halt;
    logic memwb_regwrite;
    logic [63:0] ex_result, ex_operand_a, ex_operand_b, ex_store_data;
    logic [63:0] ex_effective_addr, ex_load_value, ex_next_pc, shifted_load_value;
    logic ex_redirect, ex_illegal;
    logic [1:0] forward_a, forward_b;
    logic stall_if_id, bubble_id_ex, flush_if_id, flush_id_ex;
    logic [63:0] wb_data;
    logic [6:0] id_opcode;
    logic [4:0] id_rs1, id_rs2, id_rd;
    logic [2:0] id_funct3;
    logic [6:0] id_funct7;
    logic [63:0] id_imm;
    logic id_regwrite, id_memread, id_memwrite, id_memtoreg;
    logic id_branch, id_jal, id_jalr, id_alu_imm, id_uses_rs1, id_uses_rs2;
    logic id_illegal;
    integer lane;

    assign instr_addr = pc;
    assign data_addr = exmem_alu & 64'hFFFF_FFFF_FFFF_FFF8;
    assign data_wdata = exmem_store_data;
    assign data_wstrb = exmem_wstrb;
    assign data_we = exmem_memwrite && exmem_valid && !reset && !halted;
    assign id_opcode = ifid_instr[6:0];
    assign id_rd = ifid_instr[11:7];
    assign id_funct3 = ifid_instr[14:12];
    assign id_rs1 = ifid_instr[19:15];
    assign id_rs2 = ifid_instr[24:20];
    assign id_funct7 = ifid_instr[31:25];
    assign wb_data = memwb_value;

    always_comb begin
        id_imm = {{52{ifid_instr[31]}},ifid_instr[31:20]};
        if (id_opcode == OP_STORE)
            id_imm = {{52{ifid_instr[31]}},ifid_instr[31:25],ifid_instr[11:7]};
        else if (id_opcode == OP_BRANCH)
            id_imm = {{51{ifid_instr[31]}},ifid_instr[31],ifid_instr[7],ifid_instr[30:25],ifid_instr[11:8],1'b0};
        else if (id_opcode == OP_LUI || id_opcode == OP_AUIPC)
            id_imm = {{32{ifid_instr[31]}},ifid_instr[31:12],12'b0};
        else if (id_opcode == OP_JAL)
            id_imm = {{43{ifid_instr[31]}},ifid_instr[31],ifid_instr[19:12],ifid_instr[20],ifid_instr[30:21],1'b0};

        id_regwrite=0; id_memread=0; id_memwrite=0; id_memtoreg=0;
        id_branch=0; id_jal=0; id_jalr=0; id_alu_imm=0;
        id_uses_rs1=0; id_uses_rs2=0; id_illegal=0;
        case (id_opcode)
            OP_IMM: begin id_regwrite=1; id_alu_imm=1; id_uses_rs1=1; end
            OP_REG: begin id_regwrite=1; id_uses_rs1=1; id_uses_rs2=1; end
            OP_LOAD: begin id_regwrite=1; id_memread=1; id_memtoreg=1; id_alu_imm=1; id_uses_rs1=1; end
            OP_STORE: begin id_memwrite=1; id_alu_imm=1; id_uses_rs1=1; id_uses_rs2=1; end
            OP_BRANCH: begin id_branch=1; id_uses_rs1=1; id_uses_rs2=1; end
            OP_JAL: begin id_jal=1; id_regwrite=1; end
            OP_JALR: begin id_jalr=1; id_regwrite=1; id_alu_imm=1; id_uses_rs1=1; if (id_funct3!=0) id_illegal=1; end
            OP_LUI, OP_AUIPC: id_regwrite=1;
            OP_HALT: if (ifid_instr != 32'h0000000B) id_illegal=1;
            default: id_illegal=1;
        endcase
        if (id_opcode == OP_BRANCH && !(id_funct3==0 || id_funct3==1 || id_funct3==4 || id_funct3==5 || id_funct3==6 || id_funct3==7)) id_illegal=1;
    end

    nova64_pipeline_control hazard_control(
        .id_rs1(id_rs1),.id_rs2(id_rs2),.id_uses_rs1(id_uses_rs1 && ifid_valid),.id_uses_rs2(id_uses_rs2 && ifid_valid),
        .ex_rs1(idex_rs1),.ex_rs2(idex_rs2),.ex_rd(idex_rd),.ex_regwrite(idex_regwrite && idex_valid),.ex_memread(idex_memread && idex_valid),
        .mem_rd(exmem_rd),.mem_regwrite(exmem_regwrite),.wb_rd(memwb_rd),.wb_regwrite(memwb_regwrite),
        .redirect_valid(ex_redirect),.stall_if_id(stall_if_id),.bubble_id_ex(bubble_id_ex),
        .flush_if_id(flush_if_id),.flush_id_ex(flush_id_ex),.forward_a(forward_a),.forward_b(forward_b)
    );

    always_comb begin
        ex_operand_a = idex_a;
        if (forward_a==2'b10) ex_operand_a=exmem_memtoreg ? ex_load_value : exmem_alu;
        else if (forward_a==2'b01) ex_operand_a=wb_data;
        ex_operand_b = idex_b;
        if (forward_b==2'b10) ex_operand_b=exmem_memtoreg ? ex_load_value : exmem_alu;
        else if (forward_b==2'b01) ex_operand_b=wb_data;
        ex_store_data = ex_operand_b;
        ex_result=0; ex_redirect=0; ex_next_pc=idex_pc+64'd4; ex_illegal=0;
        if (idex_valid) begin
            if (idex_instr[6:0]==OP_IMM || idex_instr[6:0]==OP_REG) begin
                case (idex_funct3)
                    3'b000: ex_result = (idex_instr[6:0]==OP_REG && idex_instr[31:25]==7'b0100000) ? ex_operand_a-ex_operand_b : ex_operand_a+(idex_alu_imm?idex_imm:ex_operand_b);
                    3'b001: begin if (idex_instr[31:26]==0) ex_result=ex_operand_a << (idex_alu_imm?idex_instr[25:20]:ex_operand_b[5:0]); else ex_illegal=1; end
                    3'b010: ex_result=($signed(ex_operand_a)<$signed(idex_alu_imm?idex_imm:ex_operand_b))?1:0;
                    3'b011: ex_result=(ex_operand_a<(idex_alu_imm?idex_imm:ex_operand_b))?1:0;
                    3'b100: ex_result=ex_operand_a^(idex_alu_imm?idex_imm:ex_operand_b);
                    3'b101: begin
                        if (idex_instr[31:26]==0) ex_result=ex_operand_a >> (idex_alu_imm?idex_instr[25:20]:ex_operand_b[5:0]);
                        else if (idex_instr[31:26]==6'b010000) ex_result=$signed(ex_operand_a) >>> (idex_alu_imm?idex_instr[25:20]:ex_operand_b[5:0]);
                        else ex_illegal=1;
                    end
                    3'b110: ex_result=ex_operand_a|(idex_alu_imm?idex_imm:ex_operand_b);
                    3'b111: ex_result=ex_operand_a&(idex_alu_imm?idex_imm:ex_operand_b);
                endcase
                if (idex_instr[6:0]==OP_REG && !(idex_instr[31:25]==0 || (idex_instr[31:25]==7'b0100000 && (idex_funct3==0 || idex_funct3==5)))) ex_illegal=1;
            end else if (idex_instr[6:0]==OP_LOAD || idex_instr[6:0]==OP_STORE) ex_result=ex_operand_a+idex_imm;
            else if (idex_instr[6:0]==OP_LUI) ex_result=idex_imm;
            else if (idex_instr[6:0]==OP_AUIPC) ex_result=idex_pc+idex_imm;
            else if (idex_instr[6:0]==OP_JAL || idex_instr[6:0]==OP_JALR) begin
                ex_result=idex_pc+64'd4; ex_redirect=1;
                ex_next_pc=(idex_instr[6:0]==OP_JALR)?((ex_operand_a+idex_imm)&64'hFFFF_FFFF_FFFF_FFFE):(idex_pc+idex_imm);
                if (ex_next_pc[1:0]!=0) ex_illegal=1;
            end else if (idex_instr[6:0]==OP_BRANCH) begin
                case (idex_funct3)
                    3'b000: ex_redirect=(ex_operand_a==ex_operand_b);
                    3'b001: ex_redirect=(ex_operand_a!=ex_operand_b);
                    3'b100: ex_redirect=($signed(ex_operand_a)<$signed(ex_operand_b));
                    3'b101: ex_redirect=($signed(ex_operand_a)>=$signed(ex_operand_b));
                    3'b110: ex_redirect=(ex_operand_a<ex_operand_b);
                    3'b111: ex_redirect=(ex_operand_a>=ex_operand_b);
                    default: ex_illegal=1;
                endcase
                if (ex_redirect) begin ex_next_pc=idex_pc+idex_imm; if (ex_next_pc[1:0]!=0) ex_illegal=1; end
            end
        end
    end

    always_comb begin
        ex_store_strobe=0;
        if (idex_valid && idex_memwrite && !ex_illegal) begin
            case (idex_funct3)
                3'b000: ex_store_strobe=8'b1 << ex_result[2:0];
                3'b001: if (!ex_result[0]) ex_store_strobe=8'b11 << ex_result[2:0];
                3'b010: if (ex_result[1:0]==0) ex_store_strobe=8'h0F << ex_result[2:0];
                3'b011: if (ex_result[2:0]==0) ex_store_strobe=8'hFF;
                default: ex_store_strobe=0;
            endcase
        end
        shifted_load_value=data_rdata >> (8*exmem_alu[2:0]);
        ex_load_value=shifted_load_value;
        case (exmem_funct3)
            3'b000: ex_load_value={{56{shifted_load_value[7]}},shifted_load_value[7:0]};
            3'b001: ex_load_value={{48{shifted_load_value[15]}},shifted_load_value[15:0]};
            3'b010: ex_load_value={{32{shifted_load_value[31]}},shifted_load_value[31:0]};
            3'b100: ex_load_value={56'd0,shifted_load_value[7:0]};
            3'b101: ex_load_value={48'd0,shifted_load_value[15:0]};
            3'b110: ex_load_value={32'd0,shifted_load_value[31:0]};
            default: ex_load_value=shifted_load_value;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc<=0; ifid_pc<=0; ifid_instr<=32'h0000000B; ifid_valid<=0;
            idex_pc<=0; idex_instr<=32'h0000000B; idex_valid<=0; idex_a<=0; idex_b<=0; idex_imm<=0;
            idex_rs1<=0; idex_rs2<=0; idex_rd<=0; idex_regwrite<=0; idex_memread<=0; idex_memwrite<=0; idex_memtoreg<=0; idex_branch<=0; idex_jal<=0; idex_jalr<=0; idex_alu_imm<=0; idex_funct3<=0;
            exmem_valid<=0; exmem_alu<=0; exmem_store_data<=0; exmem_rd<=0; exmem_memwrite<=0; exmem_memread<=0; exmem_regwrite<=0; exmem_memtoreg<=0; exmem_funct3<=0; exmem_halt<=0; exmem_wstrb<=0; memwb_halt<=0;
            memwb_valid<=0; memwb_value<=0; memwb_rd<=0; memwb_regwrite<=0;
            halted<=0; illegal_instruction<=0;
            for (integer r=0; r<32; r=r+1) regs[r]<=64'd0;
        end else if (!halted) begin
            if (ex_illegal || (ifid_valid && id_illegal)) begin halted<=1; illegal_instruction<=1; end
            else begin
                if (memwb_valid && memwb_regwrite && memwb_rd!=0) regs[memwb_rd]<=memwb_value;
                regs[0]<=64'd0;
                if (exmem_valid && exmem_memread) begin
                    case (exmem_alu[2:0])
                        default: begin end
                    endcase
                end
                if (exmem_valid && exmem_memread && ((exmem_funct3==1 && exmem_alu[0]) || ((exmem_funct3==2 || exmem_funct3==6) && exmem_alu[1:0]!=0) || (exmem_funct3==3 && exmem_alu[2:0]!=0))) begin halted<=1; illegal_instruction<=1; end
                if (idex_valid && idex_memwrite && ((idex_funct3==1 && ex_result[0]) || (idex_funct3==2 && ex_result[1:0]!=0) || (idex_funct3==3 && ex_result[2:0]!=0) || idex_funct3>3)) begin halted<=1; illegal_instruction<=1; end
                if (idex_valid && idex_memread && ((idex_funct3==1 && ex_result[0]) || (idex_funct3==2 && ex_result[1:0]!=0) || (idex_funct3==3 && ex_result[2:0]!=0) || idex_funct3>6)) begin halted<=1; illegal_instruction<=1; end
                if (!halted) begin
                    if (!stall_if_id && !ex_redirect) begin ifid_pc<=pc; ifid_instr<=instr_rdata; ifid_valid<=1; pc<=pc+4; end
                    else if (flush_if_id) begin ifid_instr<=32'h0000000B; ifid_valid<=0; end
                    if (flush_id_ex || bubble_id_ex) begin idex_valid<=0; idex_instr<=32'h0000000B; end
                    else begin
                        idex_pc<=ifid_pc; idex_instr<=ifid_instr; idex_valid<=ifid_valid;
                        idex_a<=(id_rs1==0)?64'd0:((memwb_valid && memwb_regwrite && memwb_rd==id_rs1)?wb_data:regs[id_rs1]);
                        idex_b<=(id_rs2==0)?64'd0:((memwb_valid && memwb_regwrite && memwb_rd==id_rs2)?wb_data:regs[id_rs2]);
                        idex_imm<=id_imm; idex_rs1<=id_rs1; idex_rs2<=id_rs2; idex_rd<=id_rd;
                        idex_regwrite<=id_regwrite; idex_memread<=id_memread; idex_memwrite<=id_memwrite; idex_memtoreg<=id_memtoreg;
                        idex_branch<=id_branch; idex_jal<=id_jal; idex_jalr<=id_jalr; idex_alu_imm<=id_alu_imm; idex_funct3<=id_funct3;
                    end
                    if (ex_redirect) begin pc<=ex_next_pc; ifid_valid<=0; ifid_instr<=32'h0000000B; end
                    exmem_valid<=idex_valid && !ex_illegal;
                    exmem_halt<=idex_valid && (idex_instr[6:0]==OP_HALT);
                    exmem_alu<=ex_result; exmem_store_data<=ex_store_data << (8*ex_result[2:0]); exmem_rd<=idex_rd; exmem_funct3<=idex_funct3; exmem_wstrb<=ex_store_strobe;
                    exmem_memwrite<=idex_memwrite && !ex_illegal; exmem_memread<=idex_memread && !ex_illegal;
                    exmem_regwrite<=idex_regwrite && !ex_illegal; exmem_memtoreg<=idex_memtoreg;
                    memwb_valid<=exmem_valid;
                    memwb_halt<=exmem_halt;
                    memwb_rd<=exmem_rd; memwb_regwrite<=exmem_regwrite;
                    memwb_value<=exmem_memtoreg ? ex_load_value : exmem_alu;
                    if (memwb_halt) halted<=1;
                end
            end
        end
    end
endmodule
