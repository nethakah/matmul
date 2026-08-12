// wires datapath and control and exposes interface to outside input

module chip #(
    parameter N = 4,
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst,

    // datapath-slave; note this matches dp
    input logic [WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    input logic s_axis_tlast,
    output logic s_axis_tready,

    // datapath-master; note this matches dp
    output logic [2*WIDTH+$clog2(N)-1:0] m_axis_tdata,
    output logic m_axis_tvalid,
    output logic m_axis_tlast,
    input logic m_axis_tready,

    output logic frame_error
);

// dp and ctrl internal wires
logic mac;
logic loaded;
logic clear;
logic compute_done;

// instantiations
datapath #(
    .N (N),
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
    .mac (mac),
    .loaded (loaded),
    .clear (clear),
    .compute_done (compute_done),
    .frame_error (frame_error)
);

control ctrl (
    .clk (clk),
    .rst (rst),
    .mac (mac),
    .loaded (loaded),
    .result_pending (m_axis_tvalid),
    .compute_done (compute_done),
    .clear (clear)
);

endmodule