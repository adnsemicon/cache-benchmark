// Least-Frequently-Used replacement, per-line saturating counters with aging.
//  - refill  : counter of the new line starts at 1
//  - hit     : counter++ ; if already saturated, every counter in the set is
//              halved first (prevents stale "forever hot" lines)
//  - output  : candidate_mask_o = valid ways holding the minimum counter
module lfu_replacement #(
    parameter int COUNTER_WIDTH = 4,
    parameter int NUM_SETS      = 64,
    parameter int NW            = 4,
    localparam int SET_W        = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int WAY_W        = (NW > 1) ? $clog2(NW) : 1
) (
    input  logic             clk_i,
    input  logic             arst_ni,
    input  logic [SET_W-1:0] set_index_i,
    input  logic [WAY_W-1:0] hit_way_i,
    input  logic             hit_i,
    input  logic             refill_valid_i,
    input  logic [WAY_W-1:0] refill_way_i,
    input  logic [NW-1:0]    valid_mask_i,
    output logic [NW-1:0]    candidate_mask_o
);

    localparam logic [COUNTER_WIDTH-1:0] COUNTER_MAX = {COUNTER_WIDTH{1'b1}};
    localparam logic [COUNTER_WIDTH-1:0] COUNTER_ONE = COUNTER_WIDTH'(1);

    logic [COUNTER_WIDTH-1:0] freq_q [0:NUM_SETS-1][0:NW-1];

    // One counter per (set, way); see header for the update rules.
    for (genvar s = 0; s < NUM_SETS; s++) begin : g_set
        for (genvar w = 0; w < NW; w++) begin : g_way
            always_ff @(posedge clk_i or negedge arst_ni) begin
                if (!arst_ni) begin
                    freq_q[s][w] <= '0;
                end else if (set_index_i == SET_W'(s)) begin
                    if (refill_valid_i) begin
                        if (refill_way_i == WAY_W'(w)) freq_q[s][w] <= COUNTER_ONE;
                    end else if (hit_i && hit_way_i < NW) begin
                        if (hit_way_i == WAY_W'(w)) begin
                            if (freq_q[s][w] == COUNTER_MAX)
                                freq_q[s][w] <= (COUNTER_MAX >> 1) + COUNTER_ONE;
                            else
                                freq_q[s][w] <= freq_q[s][w] + COUNTER_ONE;
                        end else if (freq_q[s][hit_way_i] == COUNTER_MAX) begin
                            freq_q[s][w] <= freq_q[s][w] >> 1;   // aging
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        logic                     found;
        logic [COUNTER_WIDTH-1:0] min_freq;
        found            = 1'b0;
        min_freq         = COUNTER_MAX;
        candidate_mask_o = '0;
        if (set_index_i < NUM_SETS) begin
            for (int w = 0; w < NW; w++) begin
                if (valid_mask_i[w] && (!found || freq_q[set_index_i][w] < min_freq)) begin
                    found    = 1'b1;
                    min_freq = freq_q[set_index_i][w];
                end
            end
            for (int w = 0; w < NW; w++) begin
                candidate_mask_o[w] = valid_mask_i[w] && found && (freq_q[set_index_i][w] == min_freq);
            end
        end
    end

endmodule
