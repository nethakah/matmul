module bram #(
    parameter WIDTH = 8, // bits per word
    parameter DEPTH = 16 // # of words
)(
    input logic clk,

    // write
    input logic we,
    input logic [$clog2(DEPTH)-1:0] waddr,
    input logic [WIDTH-1:0] wdata,

    // read
    input logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0] rdata
);

// storage
logic [WIDTH-1:0] mem [0:DEPTH-1];

always_ff @(posedge clk) begin
    if (we) begin
        mem[waddr] <= wdata;
    end

    // since SYNC, we set rdata for the next clock edge with CURRENT raddr
    rdata <= mem[raddr];
end

endmodule