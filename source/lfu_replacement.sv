// LFU replacement with aging. 4-bit saturating use counters per line.
//   refill : new line starts at 1
//   hit    : counter++ ; at saturation every counter in the set is halved
//   victim : valid way with the lowest counter; ties are broken by a rotating
//            start pointer (cheap pseudo-random, no LFSR needed)
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
    input  logic             hit_i,
    input  logic [WAY_W-1:0] hit_way_i,
    input  logic             refill_valid_i,
    input  logic [WAY_W-1:0] refill_way_i,
    input  logic [NW-1:0]    valid_mask_i,
    output logic [WAY_W-1:0] victim_way_o     // only meaningful when every way is valid
);

    localparam logic [COUNTER_WIDTH-1:0] CMAX = {COUNTER_WIDTH{1'b1}};
    localparam logic [COUNTER_WIDTH-1:0] CONE = COUNTER_WIDTH'(1);

    logic [COUNTER_WIDTH-1:0] freq_q [0:NUM_SETS-1][0:NW-1];
    logic [COUNTER_WIDTH-1:0] cur    [0:NW-1];
    logic [WAY_W-1:0]         rot_q;

    always_comb begin
        for (int w = 0; w < NW; w++)
            cur[w] = (set_index_i < NUM_SETS) ? freq_q[set_index_i][w] : '0;
    end

    // minimum counter among valid ways, then first minimum at/after rot_q
    always_comb begin
        logic found;
        logic [COUNTER_WIDTH-1:0] min_f;
        int   idx;
        found = 1'b0; min_f = CMAX; victim_way_o = '0;
        for (int w = 0; w < NW; w++)
            if (valid_mask_i[w] && (!found || cur[w] < min_f)) begin found = 1'b1; min_f = cur[w]; end
        for (int i = NW - 1; i >= 0; i--) begin
            idx = (int'(rot_q) + i) % NW;
            if (valid_mask_i[idx] && cur[idx] == min_f) victim_way_o = WAY_W'(idx);
        end
    end

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)                 rot_q <= '0;
        else if (refill_valid_i)      rot_q <= (int'(rot_q) == NW - 1) ? '0 : rot_q + 1'b1;
    end

    for (genvar s = 0; s < NUM_SETS; s++) begin : g_set
        for (genvar w = 0; w < NW; w++) begin : g_way
            always_ff @(posedge clk_i or negedge arst_ni) begin
                if (!arst_ni) begin
                    freq_q[s][w] <= '0;
                end else if (set_index_i == SET_W'(s)) begin
                    if (refill_valid_i) begin
                        if (refill_way_i == WAY_W'(w)) freq_q[s][w] <= CONE;
                    end else if (hit_i && hit_way_i < NW) begin
                        if (hit_way_i == WAY_W'(w)) begin
                            if (freq_q[s][w] == CMAX) freq_q[s][w] <= (CMAX >> 1) + CONE;
                            else                      freq_q[s][w] <= freq_q[s][w] + CONE;
                        end else if (freq_q[s][hit_way_i] == CMAX) begin
                            freq_q[s][w] <= freq_q[s][w] >> 1;
                        end
                    end
                end
            end
        end
    end

endmodule