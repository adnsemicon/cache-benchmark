// Per-set LFU counters with saturating aging.
// Refilled lines start at one; a hit increments its way, aging all ways when
// that counter is saturated. The output marks every valid least-used way.
module lfu_replacement #(
    parameter COUNTER_WIDTH = 4,
    parameter NUM_SETS      = 64,
    parameter NW            = 4,
    parameter SET_W         = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter WAY_W         = (NW > 1) ? $clog2(NW) : 1
) (
    input  wire             clk_i,
    input  wire             arst_ni,
    input  wire [SET_W-1:0] set_index_i,
    input  wire [WAY_W-1:0] hit_way_i,
    input  wire             hit_i,
    input  wire             refill_valid_i,
    input  wire [WAY_W-1:0] refill_way_i,
    input  wire [NW-1:0]    valid_mask_i,
    output reg  [NW-1:0]    candidate_mask_o
);

    localparam integer ENTRY_COUNT = NUM_SETS * NW;
    localparam [COUNTER_WIDTH-1:0] COUNTER_MAX = {COUNTER_WIDTH{1'b1}};
    localparam [COUNTER_WIDTH-1:0] COUNTER_ONE = {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};

    reg [COUNTER_WIDTH-1:0] freq_q [0:ENTRY_COUNT-1];
    integer reset_entry;
    integer update_base;
    integer update_way;

    initial begin
        if (COUNTER_WIDTH < 1)
            $fatal(1, "lfu_replacement: COUNTER_WIDTH must be positive");
        if (NUM_SETS < 1 || NW < 1)
            $fatal(1, "lfu_replacement: NUM_SETS and NW must be positive");
    end

    always @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            for (reset_entry = 0; reset_entry < ENTRY_COUNT; reset_entry = reset_entry + 1)
                freq_q[reset_entry] <= {COUNTER_WIDTH{1'b0}};
        end else if (set_index_i < NUM_SETS) begin
            update_base = set_index_i * NW;
            if (refill_valid_i) begin
                if (refill_way_i < NW)
                    freq_q[update_base + refill_way_i] <= COUNTER_ONE;
            end else if (hit_i && hit_way_i < NW) begin
                if (freq_q[update_base + hit_way_i] == COUNTER_MAX) begin
                    for (update_way = 0; update_way < NW; update_way = update_way + 1)
                        freq_q[update_base + update_way] <=
                            freq_q[update_base + update_way] >> 1;
                    freq_q[update_base + hit_way_i] <= (COUNTER_MAX >> 1) + COUNTER_ONE;
                end else begin
                    freq_q[update_base + hit_way_i] <=
                        freq_q[update_base + hit_way_i] + COUNTER_ONE;
                end
            end
        end
    end

    always @* begin
        integer candidate_base;
        integer way;
        reg found;
        reg [COUNTER_WIDTH-1:0] min_freq;

        candidate_mask_o = {NW{1'b0}};
        candidate_base = 0;
        found = 1'b0;
        min_freq = COUNTER_MAX;
        if (set_index_i < NUM_SETS) begin
            candidate_base = set_index_i * NW;
            for (way = 0; way < NW; way = way + 1) begin
                if (valid_mask_i[way]) begin
                    if (!found || freq_q[candidate_base + way] < min_freq) begin
                        found = 1'b1;
                        min_freq = freq_q[candidate_base + way];
                        candidate_mask_o = {{(NW-1){1'b0}}, 1'b1} << way;
                    end else if (freq_q[candidate_base + way] == min_freq) begin
                        candidate_mask_o[way] = 1'b1;
                    end
                end
            end
        end
    end

endmodule
