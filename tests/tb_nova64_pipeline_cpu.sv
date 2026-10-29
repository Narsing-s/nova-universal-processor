`timescale 1ns/1ps
module tb_nova64_pipeline_cpu;
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
    function automatic [31:0] enc_r(input integer f7,input integer rs2,input integer rs1,input integer f3,input integer rd);
        enc_r={f7[6:0],rs2[4:0],rs1[4:0],f3[2:0],rd[4:0],7'b0110011};
    endfunction

    initial begin
        for(integer i=0;i<64;i=i+1) imem[i]=32'h0000000B;
        for(integer i=0;i<32;i=i+1) dmem[i]=0;
        imem[0]=enc_i(5,0,0,1,7'b0010011);       // x1=5
        imem[1]=enc_i(7,0,0,2,7'b0010011);       // x2=7
        imem[2]=enc_r(0,2,1,0,3);                // dependent add x3=x1+x2
        imem[3]=enc_s(0,3,0,3);                  // sd x3,0(x0)
        imem[4]=enc_i(0,0,3,4,7'b0000011);       // ld x4,0(x0)
        imem[5]=enc_i(1,4,0,5,7'b0010011);       // load-use dependent addi
        imem[6]=32'h0000000B;                    // pipeline-draining HALT
        repeat(2) @(negedge clk);
        reset=0;
        cycles=0;
        while(!halted && cycles<80) begin @(negedge clk); cycles=cycles+1; end
        #1;
        if(!halted) $fatal(1,"pipeline timed out");
        if(illegal_instruction) $fatal(1,"pipeline reported illegal instruction");
        if(dut.regs[1]!==64'd5 || dut.regs[2]!==64'd7 || dut.regs[3]!==64'd12)
            $fatal(1,"ALU/forwarding failure x1=%h x2=%h x3=%h",dut.regs[1],dut.regs[2],dut.regs[3]);
        if(dmem[0]!==64'd12 || dut.regs[4]!==64'd12 || dut.regs[5]!==64'd13)
            $fatal(1,"store/load/load-use failure mem=%h x4=%h x5=%h",dmem[0],dut.regs[4],dut.regs[5]);
        if(dut.regs[0]!==64'd0) $fatal(1,"x0 invariant failed");
        $display("PASS: Nova64 pipeline ALU forwarding, store/load, load-use interlock, HALT drain");
        $finish;
    end
endmodule
