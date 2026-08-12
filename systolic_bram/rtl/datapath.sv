module datapath #(
    parameter M = 8,
    parameter N = 4,
    parameter K = 6,
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

    // flag for end-of-frame marker (tlast) disagreeing w our own elem count
    output logic frame_error
);

// BRAM bank wire lists
logic a_we [0:M-1];
logic [$clog2(N)-1:0] a_waddr [0:M-1];
logic [$clog2(N)-1:0] a_raddr [0:M-1];
logic [WIDTH-1:0] a_wdata [0:M-1];
logic [WIDTH-1:0] a_rdata [0:M-1];
logic b_we [0:K-1];
logic [$clog2(N)-1:0] b_waddr [0:K-1];
logic [$clog2(N)-1:0] b_raddr [0:K-1];
logic [WIDTH-1:0] b_wdata [0:K-1];
logic [WIDTH-1:0] b_rdata [0:K-1];

// bram.sv instantiation
genvar bank;
generate
    for (bank=0; bank<M; bank++) begin : a_banks
        bram #(
        .WIDTH (WIDTH),
        .DEPTH (N)
        ) u_a_bram (
            .clk (clk),
            .we (a_we[bank]),
            .waddr (a_waddr[bank]),
            .wdata (a_wdata[bank]),
            .raddr (a_raddr[bank]),
            .rdata (a_rdata[bank])
        );
    end
    for (bank=0; bank<K; bank++) begin : b_banks
        bram #(
        .WIDTH (WIDTH),
        .DEPTH (N)
        ) u_b_bram (
            .clk (clk),
            .we (b_we[bank]),
            .waddr (b_waddr[bank]),
            .wdata (b_wdata[bank]),
            .raddr (b_raddr[bank]),
            .rdata (b_rdata[bank])
        );
    end
endgenerate

// array.sv
logic [WIDTH-1:0] a_edge [0:M-1];
logic [WIDTH-1:0] b_edge [0:K-1];
logic [2*WIDTH+$clog2(N)-1:0] ab_out [0:M-1][0:K-1]; // output matrix
array #(
    .M (M),
    .N (N),
    .K (K),
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
logic [$clog2(M*N + N*K):0] load_cnt; // M*N for matA + N*K for matB
logic [$clog2(M+N+K):0] t; // cycle counter to know when done computing (heartbeat of compute phase)
// ~M/K cycles input enterring + cross array + ~N mult-adds to accumulate dot product
logic [$clog2(M*K):0] out_cnt; // counts us outputting the result matrix ab_out's entries

logic a_valid [0:M-1];   // was mat A bank i's read an in-window/valid read?
logic b_valid [0:K-1];   // was mat B bank j's read an in-window/valid read?

assign loaded = (load_cnt == M*N + N*K); // loaded all
assign s_axis_tready = (load_cnt < M*N + N*K); // load entries until we get them all!

// calculation clock
always_ff @(posedge clk) begin
    if (rst) begin
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
        // per op need to reinitialize like rst but without actual matrix data
        load_cnt <= '0;
        t <= '0;
        out_cnt <= '0;

        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        compute_done <= '0;
        // NO CLEARING FRAME_ERROR bc integreity error must persist until full reset
    end
    else if (s_axis_tvalid && s_axis_tready) begin // load
        load_cnt <= load_cnt + 1;

        if (s_axis_tlast != (load_cnt == M*N + N*K - 1)) begin
            frame_error <= 1'b1;
        end
    end 
    else if (compute_busy) begin // if we are computing, advance (while t < 3N-3)
        if (t < M+N+K-3) begin // computing values:
        // (M-1) is vert distance to farthest row for B propagating down
        // (K-1) is horiz distance to farthest col for A propagating right
        // (N-1) is accumulation length for dot product (N terms)
            t <= t + 1;
        end else begin // (t == 3N-3) -> done computing
        // push ab_out
        // tvalid is gonna be double used to check "is slot full"
        // out_cnt is now leading by 1 = index of NEXT element to push
            if (!m_axis_tvalid) begin
                // empty slot - load element and mark full
                m_axis_tdata <= ab_out[out_cnt/K][out_cnt%K];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= (out_cnt == M*K-1); // is this the next element?
                out_cnt <= out_cnt + 1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                // valid data and accepted by receiver
                if (m_axis_tlast) begin
                    // last accepted data
                    m_axis_tvalid <= '0;
                    m_axis_tlast <= '0;
                    compute_done <= 1'b1;
                end else begin // not last one yet
                    m_axis_tdata <= ab_out[out_cnt/K][out_cnt%K];
                    m_axis_tlast <= (out_cnt == M*K-1);
                    out_cnt <= out_cnt + 1;
                end
            end
        end // implicit else: slot is full and not tready -> implies hold current tdata/tvalid (backpressure hopefully)
    end
end

/////////// LOADING (writing into banks) ///////////

always_comb begin
    for (int bank=0; bank<M; bank++) begin // default (no A bank written)
        a_we[bank] = '0;
        a_waddr[bank] = '0;
        a_wdata[bank] = '0;
    end
    for (int bank=0; bank<K; bank++) begin // default (no B bank written)
        b_we[bank] = '0;
        b_waddr[bank] = '0;
        b_wdata[bank] = '0;
    end

    if (s_axis_tvalid && s_axis_tready) begin // yes an element is arriving
        if (load_cnt<M*N) begin // first MxN = mat A
        // bank=row, addr=col
            a_we[load_cnt/N] = 1'b1; // write enable
            a_waddr[load_cnt/N] = load_cnt%N; // address = col
            a_wdata[load_cnt/N] = s_axis_tdata; // the value to store there
        end else begin // next N*K = mat B
        // addr=row, bank=col
            b_we[(load_cnt-M*N)%K] = 1'b1; // write enable
            b_waddr[(load_cnt-M*N)%K] = (load_cnt-M*N)/K; // address = row
            b_wdata[(load_cnt-M*N)%K] = s_axis_tdata; // the value to store there
        end
    end
end

//////////// FEED ///////////

// prefetching - present read addresses (t+1's values NOW for next cycle bc bram will be 1 cycle late)
always_comb begin
    for (int i=0; i<M; i++) begin
        if (compute_busy && t>=i && t-i<N) // will row i be active next cycle (SHOULD WE FEED VALUE OR 0 for staircase)
            a_raddr[i] = t-i; // yes - get that column
        else
            a_raddr[i] = '0; // no - ask anything j ignore it later
    end
    for (int j = 0; j < K; j++) begin
        if (compute_busy && t>=j && t-j<N) // will col j be active next cycle (SHOULD WE FEED VALUE OR 0 for staircase)
            b_raddr[j] = t-j; // yes - get that row
        else
            b_raddr[j] = '0;
    end
end

// remember if ask was real or useless - delayed 1 cycle so lines up w data
always_ff @(posedge clk) begin
    for (int i=0; i<M; i++)
        a_valid[i] <= (compute_busy) && (t>=i) && (t-i<N); // same condition used in prefetching to see if real ask
    for (int j=0; j<K; j++)
        b_valid[j] <= (compute_busy) && (t>=j) && (t-j<N);
end

// data arrived - feed to array if real else just '0 if invalid
always_comb begin
    for (int i=0; i<M; i++) begin
        if (a_valid[i]) // use data
            a_edge[i] = a_rdata[i];
        else // junk
            a_edge[i] = '0;
    end
    for (int j=0; j<K; j++) begin
        if (b_valid[j]) // use data
            b_edge[j] = b_rdata[j];
        else // junk
            b_edge[j] = '0;
    end
end

endmodule