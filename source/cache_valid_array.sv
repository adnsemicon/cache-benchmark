// Per-line valid bits. Cleared by reset, set on refill (read-only cache: no invalidation).
module cache_valid_array #(
    parameter int NUM_SETS = 64,
    parameter int NW       = 4,
    localparam int SET_W   = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int WAY_W   = (NW > 1) ? $clog2(NW) : 1
) (
    input  logic              clk_i,
    input  logic              arst_ni,
    input  logic [SET_W-1:0]  lookup_set_i,
    input  logic              refill_valid_i,
    input  logic [SET_W-1:0]  refill_set_i,
    input  logic [WAY_W-1:0]  refill_way_i,
    output logic [NW-1:0]     valid_mask_o,
    output logic [NW-1:0]     invalid_mask_o
);

    logic [NW-1:0] valid_q [0:NUM_SETS-1];

    // One register per set (generate instead of a loop: scales to any CL and
    // keeps simulators/synthesis from unrolling a huge reset loop).
    for (genvar s = 0; s < NUM_SETS; s++) begin : g_set
        always_ff @(posedge clk_i or negedge arst_ni) begin
            if (!arst_ni) begin
                valid_q[s] <= '0;
            end else if (refill_valid_i && refill_set_i == SET_W'(s) && refill_way_i < NW) begin
                valid_q[s][refill_way_i] <= 1'b1;
            end
        end
    end

    always_comb begin
        valid_mask_o = '0;
        if (lookup_set_i < NUM_SETS) valid_mask_o = valid_q[lookup_set_i];
        invalid_mask_o = ~valid_mask_o;
    end

endmodule
