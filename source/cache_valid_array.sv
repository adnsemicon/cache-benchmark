// Per-line valid bits. Cleared by reset, set on refill (read-only cache: no invalidation).
module cache_valid_array #(
    parameter NUM_SETS = 64,
    parameter NW       = 4,
    parameter SET_W    = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter WAY_W    = (NW > 1) ? $clog2(NW) : 1
) (
    input  wire             clk_i,
    input  wire             arst_ni,
    input  wire [SET_W-1:0] lookup_set_i,
    input  wire             refill_valid_i,
    input  wire [SET_W-1:0] refill_set_i,
    input  wire [WAY_W-1:0] refill_way_i,
    output reg  [NW-1:0]    valid_mask_o,
    output reg  [NW-1:0]    invalid_mask_o
);

    reg [NW-1:0] valid_q [0:NUM_SETS-1];

    // One register per set (generate instead of a loop: scales to any CL and
    // keeps simulators/synthesis from unrolling a huge reset loop).
    genvar s;
    generate
        for (s = 0; s < NUM_SETS; s = s + 1) begin : g_set
            always @(posedge clk_i or negedge arst_ni) begin
                if (!arst_ni) begin
                    valid_q[s] <= {NW{1'b0}};
                end else if (refill_valid_i && refill_set_i == s && refill_way_i < NW) begin
                    valid_q[s][refill_way_i] <= 1'b1;
                end
            end
        end
    endgenerate

    always @* begin
        valid_mask_o = {NW{1'b0}};
        if (lookup_set_i < NUM_SETS)
            valid_mask_o = valid_q[lookup_set_i];
        invalid_mask_o = ~valid_mask_o;
    end

endmodule