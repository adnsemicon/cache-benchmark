// Picks one set bit of candidate_mask using random_value.
module random_tiebreaker #(
    parameter NW        = 4,
    parameter RNG_WIDTH = 8,
    parameter WAY_W     = (NW > 1) ? $clog2(NW) : 1
) (
    input  wire [NW-1:0]        candidate_mask,
    input  wire [RNG_WIDTH-1:0] random_value,
    output reg  [WAY_W-1:0]     victim_way
);

    always @* begin
        integer count;
        integer pick;
        integer seen;
        integer w;
        count = 0;
        seen  = 0;
        victim_way = {WAY_W{1'b0}};
        for (w = 0; w < NW; w = w + 1)
            if (candidate_mask[w])
                count = count + 1;
        pick = (count > 1) ? (random_value % count) : 0;
        for (w = 0; w < NW; w = w + 1) begin
            if (candidate_mask[w]) begin
                if (seen == pick)
                    victim_way = w;
                seen = seen + 1;
            end
        end
    end

endmodule