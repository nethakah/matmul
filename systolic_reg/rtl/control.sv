
module control (
    input logic clk,
    input logic rst,

    input logic loaded,
    input logic compute_done,
    output logic compute_busy,
    output logic clear
);

typedef enum logic {
    LOAD = 1'b0,
    COMPUTE = 1'b1
} state_t;

state_t curr_state;
state_t next_state;

always_ff @(posedge clk) begin
    if (rst) begin
        curr_state <= LOAD;
    end
    else begin
        curr_state <= next_state;
    end
end

always_comb begin
    // set port outputs to default
    compute_busy = 1'b0;
    clear = 1'b0;
    next_state = curr_state;

    case (curr_state)
        LOAD: begin
            if (loaded) begin
                next_state = COMPUTE;
            end
        end
        COMPUTE: begin // remember this covers the ENTIRE MATRIX ALL ENTRIES UNTIL FULLY DONE
            compute_busy = 1'b1;
            if (compute_done) begin // only leave when the last entry actually finalizes
                clear = 1'b1;
                next_state = LOAD;
            end
        end
        default: begin
            next_state = LOAD;
        end
    endcase
end

endmodule