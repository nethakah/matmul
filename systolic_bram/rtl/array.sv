module array #(
    parameter M = 8,
    parameter N = 4,
    parameter K = 6,
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst,
    input logic clr,

    input logic [WIDTH-1:0] a_edge [0:M-1],
    input logic [WIDTH-1:0] b_edge [0:K-1],
    output logic [2*WIDTH+$clog2(N)-1:0] ab_out [0:M-1][0:K-1]
    // Note: we actually store an output matrix now because systolic is not in-order of entries like sequential
);

logic [WIDTH-1:0] a_wire [0:M-1][0:K]; // matA flows horizontally
logic [WIDTH-1:0] b_wire [0:M][0:K-1]; // matB flows vertically

// instantiates edge inputs and places them onto boundary wires
// (in other words, takes cols/rows of A/B and puts them on edges in prep for movement)
genvar x;
generate
    for (x=0; x<M; x++) begin : a_edges
        assign a_wire[x][0] = a_edge[x]; // left edge <- A inputs
    end
    for (x=0; x<K; x++) begin : b_edges
        assign b_wire[0][x] = b_edge[x]; // top edge <- B inputs
    end
endgenerate

// instantiates all the PEs and pair the in/outs to the wires we created
genvar i,j;
generate
    for (i=0; i<M; i++) begin : row
        for (j=0; j<K; j++) begin : col
            pe #(
                .N (N),
                .WIDTH (WIDTH)
            ) u_pe ( // dont forget instance name
                .clk (clk),
                .rst (rst),
                .clr (clr),
                .a_in (a_wire[i][j]),
                .a_out (a_wire[i][j+1]),
                .b_in (b_wire[i][j]),
                .b_out (b_wire[i+1][j]),
                .accumulator (ab_out[i][j])
            );
        end
    end
endgenerate

endmodule
