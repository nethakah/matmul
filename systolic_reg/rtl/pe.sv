module pe #(
    parameter N = 4,
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst,
    input logic clr,
    
    input logic [WIDTH-1:0] a_in,
    input logic [WIDTH-1:0] b_in,
    output logic [WIDTH-1:0] a_out,
    output logic [WIDTH-1:0] b_out,

    output logic [2*WIDTH+$clog2(N)-1:0] accumulator
);

always_ff @(posedge clk) begin
    if (rst || clr) begin
        accumulator <= '0;
        a_out <= '0;
        b_out <= '0;
    end
    else begin
        accumulator <= accumulator + (a_in * b_in);
        a_out <= a_in;
        b_out <= b_in;
    end
end

endmodule