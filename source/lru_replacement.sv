// True LRU replacement (drop-in, same ports as rrip_replacement).
// Each way of a set holds a recency rank: 0 = most recently used, NW-1 = least.
// Ranks are always a permutation of 0..NW-1. Touching a way (hit or refill)
// gives it rank 0 and pushes every more-recent way down by one.
// Works for any NW (including non powers of two) and any number of sets.
module lru_replacement #(
    parameter int RRPV_WIDTH = 2,   // unused, kept so both policies share one parameter list
    parameter int NUM_SETS   = 64,
    parameter int NW         = 4,
    localparam int SET_W     = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int WAY_W     = (NW > 1) ? $clog2(NW) : 1
) (
    input  logic             clk_i,
    input  logic             arst_ni,
    input  logic [SET_W-1:0] set_index_i,
    input  logic             hit_i,
    input  logic [WAY_W-1:0] hit_way_i,
    input  logic             refill_valid_i,
    input  logic [WAY_W-1:0] refill_way_i,
    input  logic [NW-1:0]    valid_mask_i,
    output logic [WAY_W-1:0] victim_way_o     // only meaningful when every way is valid
);

    logic [WAY_W-1:0] rank_q [0:NUM_SETS-1][0:NW-1];
    logic [WAY_W-1:0] cur    [0:NW-1];
    logic [WAY_W-1:0] touched_way, touched_rank;
    logic             touch_en;

    assign touch_en    = refill_valid_i || hit_i;
    assign touched_way = refill_valid_i ? refill_way_i : hit_way_i;

    always_comb begin
        for (int w = 0; w < NW; w++)
            cur[w] = (set_index_i < NUM_SETS) ? rank_q[set_index_i][w] : '0;
        touched_rank = (touched_way < NW) ? cur[touched_way] : '0;
    end

    // victim = valid way with the highest rank (the LRU way)
    always_comb begin
        logic             found;
        logic [WAY_W-1:0] best;
        found        = 1'b0;
        best         = '0;
        victim_way_o = '0;
        for (int w = 0; w < NW; w++) begin
            if (valid_mask_i[w] && (!found || cur[w] > best)) begin
                found        = 1'b1;
                best         = cur[w];
                victim_way_o = WAY_W'(w);
            end
        end
    end

    for (genvar s = 0; s < NUM_SETS; s++) begin : g_set
        for (genvar w = 0; w < NW; w++) begin : g_way
            always_ff @(posedge clk_i or negedge arst_ni) begin
                if (!arst_ni) begin
                    rank_q[s][w] <= WAY_W'(w);                    // distinct initial order
                end else if (touch_en && set_index_i == SET_W'(s) && touched_way < NW) begin
                    if (touched_way == WAY_W'(w))      rank_q[s][w] <= '0;
                    else if (rank_q[s][w] < touched_rank) rank_q[s][w] <= rank_q[s][w] + 1'b1;
                end
            end
        end
    end

    wire unused_ok = &{1'b0, valid_mask_i[0]};

endmodule