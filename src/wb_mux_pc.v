module wb_mux_pc (
    input[31:0] perips_nextpc,
    input[31:0] mepc,
    input[31:0] mtvec,
    input excp_token,
    input is_mret,
    input intrpt,
    output reg[31:0] nextpc
);
    always @(*) begin
        if(excp_token) begin
            nextpc = mtvec;
        end else if(is_mret) begin
            nextpc = mepc;
        end else if(intrpt) begin
            nextpc = mtvec;
        end
        else begin
            nextpc = perips_nextpc;
        end
    end
endmodule