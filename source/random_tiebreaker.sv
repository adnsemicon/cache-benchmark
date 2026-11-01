// Picks one set bit of candidate_mask using random_value.
module random_tiebreaker #(
    parameter int NW        = 4,
    parameter int RNG_WIDTH = 8,
    localparam int WAY_W    = (NW > 1) ? $clog2(NW) : 1
) (
    input  logic [NW-1:0]        candidate_mask,
    input  logic [RNG_WIDTH-1:0] random_value,
    output logic [WAY_W-1:0]     victim_way
);

    always_comb begin
        int unsigned count;
        int unsigned pick;
        int unsigned seen;
        count = 0;
        seen  = 0;
        victim_way = '0;
        for (int w = 0; w < NW; w++) if (candidate_mask[w]) count++;
        pick = (count > 1) ? (32'(random_value) % count) : 0;
        for (int w = 0; w < NW; w++) begin
            if (candidate_mask[w]) begin
                if (seen == pick) victim_way = WAY_W'(w);
                seen++;
            end
        end
    end

endmodule
