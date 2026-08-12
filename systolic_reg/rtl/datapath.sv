module datapath #(
    parameter N = 4,
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst,

    //slave
    input logic [WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    input logic s_axis_tlast,
    output logic s_axis_tready,

    //master
    output logic [2*WIDTH+$clog2(N)-1:0] m_axis_tdata,
    output logic m_axis_tvalid,
    output logic m_axis_tlast,
    input logic m_axis_tready,

    //control.sv - logic here is ctrl sets busy=1, then waits until done=1
    input logic compute_busy,
    input logic clear,
    output logic loaded,
    output logic compute_done,

    output logic frame_error
);

// the matrices
logic [WIDTH-1:0] mat_a [N-1:0][N-1:0];
logic [WIDTH-1:0] mat_b [N-1:0][N-1:0];

// array.sv
logic [WIDTH-1:0] a_edge [0:N-1];
logic [WIDTH-1:0] b_edge [0:N-1];
logic [2*WIDTH+$clog2(N)-1:0] ab_out [0:N-1][0:N-1]; // output matrix
array #(
    .N (N),
    .WIDTH (WIDTH)
) u_array (
    .clk (clk),
    .rst (rst),
    .clr (clear),
    .a_edge (a_edge),
    .b_edge (b_edge),
    .ab_out (ab_out)
);

// counters (no -1 because we want an overflow extra 1 bit)
logic [$clog2(2*N*N):0] load_cnt; // N^2 for matA + N^2 for matB
logic [$clog2(3*N):0] t; // cycle counter to know when done computing (heartbeat of compute phase)
// ~N cycles input enterring + ~N to move across array + ~N mult-adds to accumulate dot product
logic [$clog2(N*N):0] out_cnt; // counts us outputting the result matrix ab_out's entries

assign loaded = (load_cnt == 2*N*N); // loaded all
assign s_axis_tready = (load_cnt < 2*N*N); // load entries until we get them all!

// calculation clock
always_ff @(posedge clk) begin
    if (rst) begin
        // the matrices
        for (int x = 0; x < N; x++) begin
            for (int y = 0; y < N; y++) begin
                mat_a[x][y] <= '0;
                mat_b[x][y] <= '0;
            end
        end

        // internal signals
        load_cnt <= '0;
        t <= '0;
        out_cnt <= '0;

        // outputs driven by datapath that are not handled elsewhere
        m_axis_tdata <= '0;
        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        compute_done <= '0;
        frame_error <= '0;
    end
    else if (clear) begin
        // internal signals
        load_cnt <= '0;
        t <= '0;
        out_cnt <= '0;

        // outputs driven by datapath that are not handled elsewhere
        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        compute_done <= '0;
    end // load the two matrices fully - this case happens N*N times first then is done.
    else if (s_axis_tvalid && s_axis_tready) begin
        // row = (load_cnt % (N*N)) / N;
        // col = (load_cnt % (N*N)) % N;
        if (load_cnt < N*N) begin
            mat_a[(load_cnt%(N*N))/N][(load_cnt%(N*N))%N] <= s_axis_tdata;
        end else begin
            mat_b[(load_cnt%(N*N))/N][(load_cnt%(N*N))%N] <= s_axis_tdata;
        end
        load_cnt <= load_cnt + 1;

        if (s_axis_tlast != (load_cnt == 2*N*N - 1)) begin
            frame_error <= 1'b1;
        end

    end // if we are computing, advance (while t < 3N-3)
    else if (compute_busy) begin
        if (t < 3*N-3) begin // computing values - changed to -2 because we gated feed in always_comb w compute_busy
            t <= t + 1;
        end else begin // (t == 3N-3) -> done computing
        // push ab_out
        // tvalid is gonna be double used to check "is slot full"
        // out_cnt is now leading by 1 = index of NEXT element to push
            if (!m_axis_tvalid) begin
                // empty slot - load element and mark full
                m_axis_tdata <= ab_out[out_cnt/N][out_cnt%N];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= (out_cnt == N*N-1); // is this the next element?
                out_cnt <= out_cnt + 1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                // valid data and accepted by receiver
                if (m_axis_tlast) begin
                    // last accepted data
                    m_axis_tvalid <= '0;
                    m_axis_tlast <= '0;
                    compute_done <= 1'b1;
                end else begin // not last one yet
                    m_axis_tdata <= ab_out[out_cnt/N][out_cnt%N];
                    m_axis_tlast <= (out_cnt == N*N-1);
                    out_cnt <= out_cnt + 1;
                end
            end
        end // implicit else: slot is full and not tready -> implies hold current tdata/tvalid (backpressure hopefully)
    end
end

always_comb begin
    // left edge
    for (int i=0; i<N; i++) begin
        if (compute_busy && t >= i && t-i<N) begin 
        // t>=i means we havent hit current compute counter and row i's feed has started
            // note we do this way to guard from unsigned subtract bc we ensure t>=i so there's never wrapping
        // t-i<N means feed hasn't finished
            a_edge[i] = mat_a[i][t-i];
            // feed col (t-i) of row i
            // streams row in order since t-i walks 0,1,...,N-1
        end else begin
            a_edge[i] = '0;
            // finished or not started so feed 0 to the PE (does nothing)
        end
    end

    // top edge - same concept as left edge
    for (int j=0; j<N; j++) begin
        if (compute_busy && t >= j && t-j<N) begin
            b_edge[j] = mat_b[t-j][j];
        end else begin
            b_edge[j] = '0;
        end
    end
end

endmodule