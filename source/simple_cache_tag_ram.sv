// -----------------------------------------------------------------------------
// simple_cache_tag_ram : tag + valid storage and parallel tag compare.
//
//  - Combinational lookup: the set selected by index_i is compared against
//    tag_i in all ways; a way hits only if it is valid and its tag matches.
//  - Valid bits reset to 0. Tags need no reset (gated by valid).
//  - Replace the array with an SRAM macro wrapper here if needed.
// -----------------------------------------------------------------------------
module simple_cache_tag_ram
  import simple_cache_pkg::*;
#(
  parameter int NS    = 64,
  parameter int NW    = 4,
  parameter int TAG_W = 6,
  localparam int IDX_WD = clog2_min1(NS),
  localparam int WAY_WD = clog2_min1(NW)
) (
  input  logic              clk_i,
  input  logic              arst_ni,

  // lookup
  input  logic [IDX_WD-1:0] index_i,
  input  logic [TAG_W-1:0]  tag_i,
  output logic              hit_o,
  output logic [WAY_WD-1:0] hit_way_o,
  output logic [NW-1:0]     valid_o,     // valid bits of the looked-up set

  // fill (written when a refill completes; also sets the valid bit)
  input  logic              wr_en_i,
  input  logic [IDX_WD-1:0] wr_index_i,
  input  logic [WAY_WD-1:0] wr_way_i,
  input  logic [TAG_W-1:0]  wr_tag_i
);

  logic [TAG_W-1:0]      tag_q   [NS][NW];
  logic [NS-1:0][NW-1:0] valid_q;

  assign valid_o = valid_q[index_i];

  always_comb begin
    hit_o     = 1'b0;
    hit_way_o = '0;
    for (int w = 0; w < NW; w++) begin
      if (valid_q[index_i][w] && (tag_q[index_i][w] == tag_i)) begin
        hit_o     = 1'b1;
        hit_way_o = WAY_WD'(w);
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni)       valid_q <= '0;
    else if (wr_en_i)   valid_q[wr_index_i][wr_way_i] <= 1'b1;
  end

  always_ff @(posedge clk_i) begin
    if (wr_en_i) tag_q[wr_index_i][wr_way_i] <= wr_tag_i;
  end

endmodule
