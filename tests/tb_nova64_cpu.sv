`timescale 1ns/1ps
module tb_nova64_cpu;
    logic clk=0, reset=1;
    logic [63:0] instr_addr, data_addr, data_wdata, data_rdata;
    logic [31:0] instr_rdata;
    logic [7:0] data_wstrb;
    logic data_we, halted, illegal_instruction;
    logic [31:0] imem [0:63];
    logic [63:0] dmem [0:31];
    integer cycles;

    always #5 clk=~clk;
    assign instr_rdata=imem[instr_addr[7:2]];
    assign data_rdata=dmem[data_addr[7:3]];
    always_ff @(posedge clk)
        if (data_we)
            for (integer lane=0; lane<8; lane=lane+1)
                if (data_wstrb[lane])
                    dmem[data_addr[7:3]][lane*8 +: 8] <= data_wdata[lane*8 +: 8];

    nova64_cpu dut(
        .clk(clk),.reset(reset),.instr_addr(instr_addr),.instr_rdata(instr_rdata),
        .data_addr(data_addr),.data_wdata(data_wdata),.data_wstrb(data_wstrb),
        .data_we(data_we),.data_rdata(data_rdata),.halted(halted),
        .illegal_instruction(illegal_instruction)
    );

    function automatic [31:0] enc_i(input integer imm,input integer rs1,input integer f3,input integer rd,input logic [6:0] op);
        enc_i={imm[11:0],rs1[4:0],f3[2:0],rd[4:0],op};
    endfunction
    function automatic [31:0] enc_s(input integer imm,input integer rs2,input integer rs1,input integer f3);
        enc_s={imm[11:5],rs2[4:0],rs1[4:0],f3[2:0],imm[4:0],7'b0100011};
    endfunction
    function automatic [31:0] enc_r(input integer f7,input integer rs2,input integer rs1,input integer f3,input integer rd);
        enc_r={f7[6:0],rs2[4:0],rs1[4:0],f3[2:0],rd[4:0],7'b0110011};
    endfunction
    function automatic [31:0] enc_b(input integer imm,input integer rs2,input integer rs1,input integer f3);
        enc_b={imm[12],imm[10:5],rs2[4:0],rs1[4:0],f3[2:0],imm[4:1],imm[11],7'b1100011};
    endfunction
    function automatic [31:0] enc_j(input integer imm,input integer rd);
        enc_j={imm[20],imm[10:1],imm[11],imm[19:12],rd[4:0],7'b1101111};
    endfunction

    always @(negedge clk) begin
        if (!reset && dut.regs[0] !== 64'd0)
            $fatal(1,"x0 invariant failed");
        if (!reset && data_we && data_wstrb==0)
            $fatal(1,"data write without byte strobes");
        if (!reset && !data_we && data_wstrb!=0)
            $fatal(1,"byte strobes without data write");
    end

    initial begin
        for(integer i=0;i<64;i=i+1) imem[i]=32'h0000000B;
        for(integer i=0;i<32;i=i+1) dmem[i]=64'd0;
        imem[0]=enc_i(5,0,0,1,7'b0010011);         // x1=5
        imem[1]=enc_i(-1,0,0,2,7'b0010011);        // x2=all ones
        imem[2]=enc_r(0,2,1,0,3);                  // x3=4
        imem[3]=enc_s(0,3,0,3);                    // sd x3,0(x0)
        imem[4]=enc_i(0,0,3,4,7'b0000011);         // ld x4,0(x0)
        imem[5]=enc_s(8,2,0,2);                    // sw x2,8(x0)
        imem[6]=enc_i(8,0,2,5,7'b0000011);         // lw sign extends
        imem[7]=enc_i(8,0,6,6,7'b0000011);         // lwu zero extends
        imem[8]={20'h80000,5'd7,7'b0110111};       // lui x7,0x80000
        imem[9]=enc_s(16,7,0,3);                   // sd x7,16(x0)
        imem[10]=enc_i(16,0,3,8,7'b0000011);       // ld x8,16(x0)
        imem[11]=enc_i(1,0,0,9,7'b0010011);        // x9=1
        imem[12]={6'b000000,6'd40,5'd9,3'b001,5'd10,7'b0010011}; // slli x10,x9,40
        imem[13]=enc_b(8,4,3,0);                   // beq x3,x4,+8
        imem[14]=enc_i(99,0,0,11,7'b0010011);      // skipped
        imem[15]=enc_i(7,0,0,11,7'b0010011);       // x11=7
        imem[16]=enc_j(8,12);                      // jal x12,+8
        imem[17]=enc_i(99,0,0,13,7'b0010011);      // skipped
        imem[18]=enc_i(8,0,0,13,7'b0010011);       // x13=8
        imem[19]=32'h0000000B;                     // HALT

        repeat(2) @(negedge clk);
        reset=0;
        cycles=0;
        while(!halted && cycles<60) begin @(negedge clk); cycles=cycles+1; end
        #1;
        if(!halted) $fatal(1,"Nova64 timed out");
        if(illegal_instruction) $fatal(1,"Nova64 raised illegal_instruction");
        if(dut.regs[3] !== 64'd4 || dut.regs[4] !== 64'd4)
            $fatal(1,"64-bit arithmetic or SD/LD failed x3=%h x4=%h",dut.regs[3],dut.regs[4]);
        if(dmem[0] !== 64'd4 || dmem[1] !== 64'h00000000FFFFFFFF)
            $fatal(1,"64-bit/32-bit store lane failure dmem0=%h dmem1=%h",dmem[0],dmem[1]);
        if(dut.regs[5] !== 64'hFFFFFFFFFFFFFFFF || dut.regs[6] !== 64'h00000000FFFFFFFF)
            $fatal(1,"LW/LWU sign extension failure");
        if(dut.regs[7] !== 64'hFFFFFFFF80000000 || dut.regs[8] !== 64'hFFFFFFFF80000000)
            $fatal(1,"64-bit LUI/LD failed x7=%h x8=%h",dut.regs[7],dut.regs[8]);
        if(dut.regs[10] !== 64'h0000010000000000)
            $fatal(1,"64-bit shift failed: %h",dut.regs[10]);
        if(dut.regs[11] !== 7 || dut.regs[12] !== 68 || dut.regs[13] !== 8)
            $fatal(1,"Branch/JAL/link behavior failed x11=%h x12=%h x13=%h",dut.regs[11],dut.regs[12],dut.regs[13]);
        $display("PASS: Nova64 arithmetic, 64-bit registers, SD/LD, LW/LWU, shift-by-40, branch/JAL, x0");
        $finish;
    end
endmodule
