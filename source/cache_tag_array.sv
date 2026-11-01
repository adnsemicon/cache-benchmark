// Tag storage + parallel tag compare for one set. Tags need no reset: a way only
// counts as a hit when its valid bit is set.
module cache_tag_array #(
    parameter int TAG_WIDTH = 6,
    parameter int NUM_SETS  = 64,
    parameter int NW        = 4,
    localparam int SET_W    = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int WAY_W    = (NW > 1) ? $clog2(NW) : 1
) (
    input  logic                 clk_i,
    input  logic                 arst_ni,
    input  logic [TAG_WIDTH-1:0] req_tag_i,
    input  logic [SET_W-1:0]     lookup_set_i,
    input  logic [NW-1:0]        valid_mask_i,
    input  logic                 refill_valid_i,
    input  logic [TAG_WIDTH-1:0] refill_tag_i,
    input  logic [SET_W-1:0]     refill_set_i,
    input  logic [WAY_W-1:0]     refill_way_i,
    output logic                 hit_o,
    output logic [WAY_W-1:0]     hit_way_o,
    input  logic [WAY_W-1:0]     peek_way_i,      // read the stored tag of any way of the lookup set
    output logic [TAG_WIDTH-1:0] peek_tag_o
);

    logic [TAG_WIDTH-1:0] tag_q [0:NUM_SETS-1][0:NW-1];

    always_ff @(posedge clk_i) begin
        if (refill_valid_i && refill_set_i < NUM_SETS && refill_way_i < NW)
            tag_q[refill_set_i][refill_way_i] <= refill_tag_i;
    end

    always_comb begin
        hit_o     = 1'b0;
        hit_way_o = '0;
        if (lookup_set_i < NUM_SETS) begin
            for (int w = NW - 1; w >= 0; w--) begin
                if (valid_mask_i[w] && tag_q[lookup_set_i][w] == req_tag_i) begin
                    hit_o     = 1'b1;
                    hit_way_o = WAY_W'(w);
                end
            end
        end
    end

    assign peek_tag_o = (lookup_set_i < NUM_SETS && peek_way_i < NW) ? tag_q[lookup_set_i][peek_way_i] : '0;

    wire unused_ok = &{1'b0, arst_ni};

endmodule