module lru_pinning_unit #(
  parameter int SETS = 64,
  parameter int NW   = 4
)(
  input  logic                               clk_i,
  input  logic                               arst_ni,

  input  logic [$clog2(SETS)-1:0]            index_i,
  input  logic                               touch_i,      // a way of this set was used
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] touch_way_i,
  input  logic [NW-1:0]                      valid_i,      // valid bits of the selected set

  output logic [(NW>1 ? $clog2(NW) : 1)-1:0] victim_way_o
);

  localparam int WB = (NW > 1) ? $clog2(NW) : 1;

  // rank[s][w] : 0 = least recently used ... NW-1 = most recently used
  logic [WB-1:0] rank [SETS][NW];
  logic          found;

  always_comb begin
    victim_way_o = '0;
    found        = 1'b0;
    for (int w = 0; w < NW; w++) begin
      if (!valid_i[w] && !found) begin
        victim_way_o = WB'(w);
        found        = 1'b1;
      end
    end
    if (!found) begin
      for (int w = 0; w < NW; w++) begin
        if (rank[index_i][w] == '0)
          victim_way_o = WB'(w);
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < SETS; s++)
        for (int w = 0; w < NW; w++)
          rank[s][w] <= WB'(w);
    end else if (touch_i) begin
      for (int w = 0; w < NW; w++) begin
        if (w == int'(touch_way_i))
          rank[index_i][w] <= WB'(NW-1);
        else if (rank[index_i][w] > rank[index_i][touch_way_i])
          rank[index_i][w] <= rank[index_i][w] - 1'b1;
      end
    end
  end

endmodule
