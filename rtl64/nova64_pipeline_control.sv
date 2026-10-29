module nova64_pipeline_control (
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    input  logic       id_uses_rs1,
    input  logic       id_uses_rs2,

    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,
    input  logic [4:0] ex_rd,
    input  logic       ex_regwrite,
    input  logic       ex_memread,

    input  logic [4:0] mem_rd,
    input  logic       mem_regwrite,
    input  logic [4:0] wb_rd,
    input  logic       wb_regwrite,

    input  logic       redirect_valid,

    output logic       stall_if_id,
    output logic       bubble_id_ex,
    output logic       flush_if_id,
    output logic       flush_id_ex,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);
    // Forward encoding: 00=register file, 10=EX/MEM, 01=MEM/WB.
    // EX/MEM is intentionally preferred over MEM/WB for the newest value.
    logic load_use_hazard;

    always_comb begin
        load_use_hazard = ex_memread && (ex_rd != 5'd0) &&
            ((id_uses_rs1 && id_rs1 == ex_rd) ||
             (id_uses_rs2 && id_rs2 == ex_rd));

        stall_if_id = load_use_hazard && !redirect_valid;
        bubble_id_ex = load_use_hazard && !redirect_valid;
        flush_if_id = redirect_valid;
        flush_id_ex = redirect_valid;

        forward_a = 2'b00;
        if (ex_rs1 != 5'd0 && mem_regwrite && mem_rd != 5'd0 && mem_rd == ex_rs1)
            forward_a = 2'b10;
        else if (ex_rs1 != 5'd0 && wb_regwrite && wb_rd != 5'd0 && wb_rd == ex_rs1)
            forward_a = 2'b01;

        forward_b = 2'b00;
        if (ex_rs2 != 5'd0 && mem_regwrite && mem_rd != 5'd0 && mem_rd == ex_rs2)
            forward_b = 2'b10;
        else if (ex_rs2 != 5'd0 && wb_regwrite && wb_rd != 5'd0 && wb_rd == ex_rs2)
            forward_b = 2'b01;
    end
endmodule
