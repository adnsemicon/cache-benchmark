// DRRIP replacement (Jaleel et al., ISCA 2010): 2-bit Re-Reference Prediction
// Values per line + set dueling between two insertion policies.
//   hit    : RRPV <= 0                       (near-immediate re-reference)
//   victim : first valid way holding the max RRPV; on a replacement all other
//            ways are aged by (MAX - max) so one way always reaches MAX
//   insert : SRRIP -> RRPV = MAX-1 ("long")
//            BRRIP -> RRPV = MAX, except every 32nd insertion = MAX-1
//   dueling: a few leader sets are hard-wired to SRRIP, a few to BRRIP; a
//            saturating PSEL counter tracks which leader misses less and all
//            follower sets use the winner.
// Result: LRU/LFU-like on friendly traffic, but immune to scans and thrashing
// loops (where LRU gets 0% and LFU never forgets an old phase).
module rrip_replacement #(
    parameter int RRPV_WIDTH = 2,
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

    localparam logic [RRPV_WIDTH-1:0] RRPV_MAX  = {RRPV_WIDTH{1'b1}};
    localparam logic [RRPV_WIDTH-1:0] RRPV_LONG = RRPV_MAX - 1'b1;

    // leader-set spacing: 32 for >=64 sets, smaller caches use fewer, closer leaders
    localparam int PERIOD      = (NUM_SETS >= 64) ? 32 : (NUM_SETS >= 4) ? NUM_SETS / 2 : 0;
    localparam int PERIOD_SAFE = (PERIOD > 0) ? PERIOD : 1;
    localparam int PSEL_W      = 10;
    localparam logic [PSEL_W-1:0] PSEL_MID = PSEL_W'(1) << (PSEL_W - 1);
    localparam int BIP_W       = 5;

    logic [RRPV_WIDTH-1:0] rrpv_q [0:NUM_SETS-1][0:NW-1];
    logic [PSEL_W-1:0]     psel_q;
    logic [BIP_W-1:0]      bip_q;

    // ---- current-set view -------------------------------------------------
    logic [RRPV_WIDTH-1:0] cur [0:NW-1];
    logic [RRPV_WIDTH-1:0] max_v, age_delta, insert_val;
    logic                  full, lead_s, lead_b, use_bimodal;

    always_comb begin
        for (int w = 0; w < NW; w++)
            cur[w] = (set_index_i < NUM_SETS) ? rrpv_q[set_index_i][w] : '0;
    end

    always_comb begin
        logic found;
        found        = 1'b0;
        max_v        = '0;
        victim_way_o = '0;
        for (int w = 0; w < NW; w++) begin
            if (valid_mask_i[w] && (!found || cur[w] > max_v)) begin
                found        = 1'b1;
                max_v        = cur[w];
                victim_way_o = WAY_W'(w);
            end
        end
    end

    assign full      = &valid_mask_i;
    assign age_delta = RRPV_MAX - max_v;

    assign lead_s      = (PERIOD > 0) && ((int'(set_index_i) % PERIOD_SAFE) == 0);
    assign lead_b      = (PERIOD > 0) && ((int'(set_index_i) % PERIOD_SAFE) == 1);
    assign use_bimodal = lead_b || (!lead_s && psel_q > PSEL_MID);
    assign insert_val  = (use_bimodal && bip_q != '0) ? RRPV_MAX : RRPV_LONG;

    // ---- policy-selection state ---------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            psel_q <= PSEL_MID;
            bip_q  <= '0;
        end else if (refill_valid_i) begin           // exactly one pulse per miss
            if (lead_s && psel_q != {PSEL_W{1'b1}}) psel_q <= psel_q + 1'b1;
            if (lead_b && psel_q != '0)             psel_q <= psel_q - 1'b1;
            if (use_bimodal)                        bip_q  <= bip_q + 1'b1;
        end
    end

    // ---- per-line RRPVs (generate: scales to any CL) ------------------------------
    for (genvar s = 0; s < NUM_SETS; s++) begin : g_set
        for (genvar w = 0; w < NW; w++) begin : g_way
            always_ff @(posedge clk_i or negedge arst_ni) begin
                if (!arst_ni) begin
                    rrpv_q[s][w] <= RRPV_MAX;
                end else if (set_index_i == SET_W'(s)) begin
                    if (refill_valid_i) begin
                        if (refill_way_i == WAY_W'(w)) rrpv_q[s][w] <= insert_val;
                        else if (full)                 rrpv_q[s][w] <= rrpv_q[s][w] + age_delta;
                    end else if (hit_i && hit_way_i == WAY_W'(w)) begin
                        rrpv_q[s][w] <= '0;
                    end
                end
            end
        end
    end

endmodule