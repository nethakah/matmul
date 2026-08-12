
module chip #(
    parameter M = 8,
    parameter N = 4,
    parameter K = 6,
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst,

    // dp
    input logic [WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    input logic s_axis_tlast,
    output logic s_axis_tready,

    // dp
    output logic [2*WIDTH+$clog2(N)-1:0] m_axis_tdata,
    output logic m_axis_tvalid,
    output logic m_axis_tlast,
    input logic m_axis_tready,

    // frame integrity error from DP
    output logic frame_error
);

// dp and ctrl internal ports
logic loaded;
logic compute_busy;
logic compute_done;
logic clear;

// instantiations
datapath #(
    .M (M),
    .N (N),
    .K (K),
    .WIDTH (WIDTH)
) dp (
    .clk (clk),
    .rst (rst),
    .s_axis_tdata (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tlast (s_axis_tlast),
    .s_axis_tready (s_axis_tready),
    .m_axis_tdata (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tlast (m_axis_tlast),
    .m_axis_tready (m_axis_tready),
    .loaded (loaded),
    .compute_busy (compute_busy),
    .compute_done (compute_done),
    .frame_error (frame_error),
    .clear (clear)
);

control ctrl (
    .clk (clk),
    .rst (rst),
    .loaded (loaded),
    .compute_busy (compute_busy),
    .compute_done (compute_done),
    .clear (clear)
);

endmodule