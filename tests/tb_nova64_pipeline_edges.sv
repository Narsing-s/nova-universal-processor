`timescale 1ns/1ps
module tb_nova64_pipeline_edges;
    logic clk=0, reset=1;
    logic [63:0] instr_addr, data_addr, data_wdata, data_rdata;
    logic [31:0] instr_rdata;
    logic [7:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem[0:63];
    logic [63:0] dmem[0:31];
    integer cycles;
    always #5 clk=~clk;
    assign instr_rdata=imem[instr_addr[7:2]];
    assign data_rdata=dmem[data_addr[7:3]];
    always_ff @(posedge clk)
        if(data_we)
            for(integer lane=0;lane<8;lane=lane+1)
                if(data_wstrb[lane]) dmem[data_addr[7:3]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];

    nova64_pipeline_cpu dut(.*);
    function automatic [31:0] enc_i(input integer imm,input integer rs1,input integer f3,input integer rd,input logic [6:0] op);
        enc_i={imm[11:0],rs1[4:0],f3[2:0],rd[4:0],op};
    endfunction
    function automatic [31:0] enc_s(input integer imm,input integer rs2,input integer rs1,input integer f3);
        enc_s={imm[11:5],rs2[4:0],rs1[4:0],f3[2:0],imm[4:0],7'b0100011};
    endfunction
    function automatic [31:0] enc_b(input integer imm,input integer rs2,input integer rs1,input integer f3);
        enc_b={imm[12],imm[10:5],rs2[4:0],rs1[4:0],f3[2:0],imm[4:1],imm[11],7'b1100011};
    endfunction
    function automatic [31:0] enc_j(input integer imm,input integer rd);
        enc_j={imm[20],imm[10:1],imm[11],imm[19:12],rd[4:0],7'b1101111};
    endfunction
    initial begin
        for(integer i=0;i<64;i=i+1) imem[i]=32'h0000000B;
        for(integer i=0;i<32;i=i+1) dmem[i]=0;
        // Signed and unsigned byte/half/word loads, with stores at nonzero lanes.
        imem[0]=enc_i(127,0,0,1,7'b0010011);     // x1=127
        imem[1]=enc_s(1,1,0,0);                  // sb x1,1(x0)
        imem[2]=enc_i(1,0,4,2,7'b0000011);       // lbu x2,1(x0)
        imem[3]=enc_i(1,0,0,3,7'b0000011);       // lb x3,1(x0)
        imem[4]=enc_i(-1,0,0,4,7'b0010011);      // x4=-1
        imem[5]=enc_s(2,4,0,1);                  // sh x4,2(x0)
        imem[6]=enc_i(2,0,5,5,7'b0000011);       // lhu x5,2(x0)
        imem[7]=enc_i(2,0,1,6,7'b0000011);       // lh x6,2(x0)
        imem[8]=enc_s(4,4,0,2);                  // sw x4,4(x0)
        imem[9]=enc_i(4,0,6,7,7'b0000011);       // lwu x7,4(x0)
        imem[10]=enc_i(4,0,2,8,7'b0000011);      // lw x8,4(x0)
        // Branch should skip x11=99; JAL should skip x13=88 and write its link.
        imem[11]=enc_i(1,0,0,9,7'b0010011);
        imem[12]=enc_i(1,0,0,10,7'b0010011);
        imem[13]=enc_b(8,10,9,0);
        imem[14]=enc_i(99,0,0,11,7'b0010011);
        imem[15]=enc_i(7,0,0,11,7'b0010011);
        imem[16]=enc_j(8,12);
        imem[17]=enc_i(88,0,0,13,7'b0010011);
        imem[18]=enc_i(9,0,0,13,7'b0010011);
        imem[19]=32'h0000000B;
        repeat(2) @(negedge clk);
        reset=0;
        cycles=0;
        while(!halted && cycles<140) begin @(negedge clk); cycles=cycles+1; end
        #1;
        if(!halted) $fatal(1,"pipeline edge test timed out");
        if(illegal_instruction) $fatal(1,"pipeline edge test illegal instruction");
        if(dut.regs[2]!==64'd127 || dut.regs[3]!==64'd127) $fatal(1,"byte load extension failed");
        if(dut.regs[5]!==64'h000000000000FFFF || dut.regs[6]!==64'hFFFFFFFFFFFFFFFF) $fatal(1,"halfword load extension failed x5=%h x6=%h",dut.regs[5],dut.regs[6]);
        if(dut.regs[7]!==64'h00000000FFFFFFFF || dut.regs[8]!==64'hFFFFFFFFFFFFFFFF) $fatal(1,"word load extension failed x7=%h x8=%h",dut.regs[7],dut.regs[8]);
        if(dut.regs[11]!==64'd7 || dut.regs[12]!==64'd68 || dut.regs[13]!==64'd9) $fatal(1,"branch/jump failed x11=%h x12=%h x13=%h",dut.regs[11],dut.regs[12],dut.regs[13]);
        if(dmem[0][15:8]!==8'h7F || dmem[0][31:16]!==16'hFFFF || dmem[0][63:32]!==32'hFFFFFFFF) $fatal(1,"store byte lanes failed mem=%h",dmem[0]);
        if(dut.regs[0]!==64'd0) $fatal(1,"x0 invariant failed");
        $display("PASS: Nova64 pipeline signed/unsigned widths, byte lanes, branch, JAL and link tests");
        $finish;
    end
endmodule
