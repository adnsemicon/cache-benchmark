// Tag storage + parallel tag compare for one set. Tags need no reset: a way only
// counts as a hit when its valid bit is set.
module cache_tag_array #(
    parameter TAG_WIDTH = 6,
    parameter NUM_SETS  = 64,
    parameter NW        = 4,
    parameter SET_W     = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter WAY_W     = (NW > 1) ? $clog2(NW) : 1
) (
    input  wire                 clk_i,
    input  wire                 arst_ni,
    input  wire [TAG_WIDTH-1:0] req_tag_i,
    input  wire [SET_W-1:0]     lookup_set_i,
    input  wire [NW-1:0]        valid_mask_i,
    input  wire                 refill_valid_i,
    input  wire [TAG_WIDTH-1:0] refill_tag_i,
    input  wire [SET_W-1:0]     refill_set_i,
    input  wire [WAY_W-1:0]     refill_way_i,
    output reg                  hit_o,
    output reg  [WAY_W-1:0]     hit_way_o
);

    reg [TAG_WIDTH-1:0] tag_q [0:NUM_SETS-1][0:NW-1];

    always @(posedge clk_i) begin
        if (refill_valid_i && refill_set_i < NUM_SETS && refill_way_i < NW)
            tag_q[refill_set_i][refill_way_i] <= refill_tag_i;
    end

    always @* begin
        integer w;
        hit_o     = 1'b0;
        hit_way_o = {WAY_W{1'b0}};
        if (lookup_set_i < NUM_SETS) begin
            for (w = NW - 1; w >= 0; w = w - 1) begin
                if (valid_mask_i[w] && tag_q[lookup_set_i][w] == req_tag_i) begin
                    hit_o     = 1'b1;
                    hit_way_o = w;
                end
            end
        end
    end

    wire unused_ok = &{1'b0, arst_ni};

endmodule