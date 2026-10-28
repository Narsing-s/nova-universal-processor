module nova_cpu (
    input  logic       clk,
    input  logic       reset,
    output logic [7:0] acc,
    output logic       halted
);

    logic [3:0] pc;
    logic [7:0] rom [0:15];
    logic [7:0] instruction;

    assign instruction = rom[pc];

    initial begin
        rom[0] = 8'h15; // ADD 5
        rom[1] = 8'h13; // ADD 3
        rom[2] = 8'h22; // SUB 2
        rom[3] = 8'hF0; // HALT

        for (integer i = 4; i < 16; i = i + 1)
            rom[i] = 8'hF0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pc     <= 4'd0;
            acc    <= 8'd0;
            halted <= 1'b0;
        end else if (!halted) begin
            case (instruction[7:4])
                4'h1: begin
                    acc <= acc + {4'b0000, instruction[3:0]};
                    pc <= pc + 1'b1;
                end

                4'h2: begin
                    acc <= acc - {4'b0000, instruction[3:0]};
                    pc <= pc + 1'b1;
                end

                4'hF: halted <= 1'b1;

                default: halted <= 1'b1;
            endcase
        end
    end

endmodule
