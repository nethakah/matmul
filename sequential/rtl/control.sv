// state machine IDLE/CALC/DONE
// tells datapath.sv when to load, when to MAC, when to ++counter
// watch status signals from datapath.sv
// handle ready-valid interface

module control (
    input logic clk,
    input logic rst,

    output logic mac,
    input logic loaded,
    input logic result_pending,
    input logic compute_done,
    output logic clear
);

typedef enum logic {
    LOAD = 1'b0,
    CALC = 1'b1
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
    mac = 1'b0;
    clear = 1'b0;
    next_state = curr_state;

    case (curr_state)
        LOAD: begin
            if (loaded) begin
                next_state = CALC;
            end
        end
        CALC: begin // remember this covers the ENTIRE MATRIX ALL ENTRIES UNTIL FULLY DONE
            mac = !result_pending; // pause computing while a finished result waits to be taken
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