// tag_array : Stores Valid bits and Tags for all sets and ways
module tag_array #(
  parameter int AW   = 16,
  parameter int CL   = 256,
  parameter int NW   = 4
)(
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic [$clog2(CL/NW)-1:0] index_i,
  input  logic [AW-$clog2(CL/NW)-$clog2(128/8)-1:0] tag_i,

  input  logic              fill_i,
  input  logic [$clog2(NW)-1:0] fill_way_i,

  output logic              hit_o,
  output logic [$clog2(NW)-1:0] hit_way_o
);

  localparam int NUM_SETS = CL / NW;
  localparam int INDEX_W  = $clog2(NUM_SETS);
  localparam int OFFSET_W = $clog2(128 / 8);
  localparam int TAG_W    = AW - INDEX_W - OFFSET_W;
  localparam int WAY_W    = (NW > 1) ? $clog2(NW) : 1;

  logic [NUM_SETS-1:0][NW-1:0]         valid_mem;
  logic [NUM_SETS-1:0][NW-1:0][TAG_W-1:0] tag_mem;

  logic [NW-1:0]       curr_valid;
  logic [NW-1:0][TAG_W-1:0] curr_tags;

  always_comb begin
    curr_valid = valid_mem[index_i];
    curr_tags  = tag_mem[index_i];
  end

  logic [WAY_W-1:0] match_way;
  logic             is_hit;

  always_comb begin
    is_hit = 1'b0;
    match_way = '0;
    for (int w = 0; w < NW; w++) begin
      if (curr_valid[w] && (curr_tags[w] == tag_i)) begin
        is_hit = 1'b1;
        match_way = w[WAY_W-1:0];
      end
    end
  end

  assign hit_o     = is_hit;
  assign hit_way_o = match_way;

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      valid_mem <= '0;
      tag_mem   <= '0;
    end else if (fill_i) begin
      valid_mem[index_i][fill_way_i] <= 1'b1;
      tag_mem[index_i][fill_way_i]   <= tag_i;
    end
  end

endmodule