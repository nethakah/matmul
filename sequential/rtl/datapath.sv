
module datapath #(
    parameter N = 4, // NxN matrices
    parameter WIDTH = 8 // max bits for each value in the matrix we load in
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
    
    //
    input logic mac, // tells us to multiply-accumulate
    output logic loaded, // tell ctrl we have loaded the two matrices fully
    input logic clear,
    output logic compute_done
);

logic [WIDTH-1:0] mat_a [N-1:0][N-1:0];
logic [WIDTH-1:0] mat_b [N-1:0][N-1:0];

logic [2*WIDTH+$clog2(N)-1:0] accumulator; 
// multiplying needs 2*WIDTH bits and then adding N products tg needs clog2(N) more bits
logic [$clog2(2*N*N):0] load_cnt;
// N^2 elements from mat_a and N^2 elements from mat_b
// so <N*N means loading mat_a
// and >=N*N means loading mat_b

// internal counters for during CALC to track what output element is being computed
logic [$clog2(N)-1:0] i; // row of mat_a
logic [$clog2(N)-1:0] j; // col of mat_b
logic [$clog2(N)-1:0] k; // fixed and cycles from 0->N-1 so we pick out one element from row and one from col each clk cycle

assign loaded = (load_cnt == 2*N*N);
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
        accumulator <= '0;
        load_cnt <= '0;
        i <= '0;
        j <= '0;
        k <= '0;

        // outputs driven by datapath that are not handled elsewhere
        m_axis_tdata <= '0;
        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        compute_done <= '0;
    end 
    else if (clear) begin
        // per op reinitialize (dont need to reset matrix arrays bc overwritten by next load)
        accumulator <= '0;
        load_cnt <= '0;
        i <= '0;
        j <= '0;
        k <= '0;
        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        compute_done <= '0;
    end
    // load the two matrices fully - this case happens N*N times first then is done.
    else if (s_axis_tvalid && s_axis_tready) begin
        // row = (load_cnt % (N*N)) / N;
        // col = (load_cnt % (N*N)) % N;
        if (load_cnt < N*N) begin
            mat_a[(load_cnt%(N*N))/N][(load_cnt%(N*N))%N] <= s_axis_tdata;
        end else begin
            mat_b[(load_cnt%(N*N))/N][(load_cnt%(N*N))%N] <= s_axis_tdata;
        end
        load_cnt <= load_cnt + 1;
    end 
    // Compute an entry and output it (case 2 and 3).
    else if (mac) begin
        accumulator <= accumulator + (mat_a[i][k] * mat_b[k][j]);
        if (k==N-1) begin // current element fully computed
            j <= j + 1;
            k <= '0;
            m_axis_tdata <= accumulator + (mat_a[i][k] * mat_b[k][j]);
            m_axis_tvalid <= 1'b1;
            accumulator <= '0;
            if (j==N-1) begin // final column of B to multiply the row of A against
                i <= i + 1;
                j <= '0;
                if (i==N-1) begin // final row of A to multiply against columns of B
                    i <= '0;
                    m_axis_tlast <= 1; // since we are on the last entry/element, assert we are done!
                end
            end
        end else begin
            k <= k+1;
        end
    end 
    // outputting
    else if (m_axis_tvalid && m_axis_tready) begin
        m_axis_tvalid <= '0;
        m_axis_tlast <= '0;
        if (m_axis_tlast) begin
            compute_done <= 1'b1;
        end
    end
end

endmodule