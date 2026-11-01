// -----------------------------------------------------------------------------
// simple_cache_lru : true-LRU replacement state for every set.
//
//  - One age per way per set: 0 = most recently used, NW-1 = least recently used.
//  - Ages are always a permutation of 0..NW-1 (reset: way w has age w).
//  - upd_i : a hit on (index_i, way_i). Younger ways age by one, way_i -> 0.
//  - victim_o : first invalid way of the set, otherwise the way with age NW-1.
//  To switch policy (e.g. tree-PLRU) replace only this module.
// -----------------------------------------------------------------------------
module simple_cache_lru #(
  parameter int NS = 64,
  parameter int NW = 4,
  localparam int IDX_WD = (NS > 1) ? $clog2(NS) : 1,
  localparam int WAY_WD = (NW > 1) ? $clog2(NW) : 1
) (
  input  logic              clk_i,
  input  logic              arst_ni,
  input  logic [IDX_WD-1:0] index_i,    // set being accessed
  input  logic [NW-1:0]     valid_i,    // valid bits of that set
  input  logic              upd_i,      // hit: mark way_i most recently used
  input  logic [WAY_WD-1:0] way_i,
  output logic [WAY_WD-1:0] victim_o
);

  logic [NS-1:0][NW-1:0][WAY_WD-1:0] age_q;

  function automatic logic [NS-1:0][NW-1:0][WAY_WD-1:0] age_init();
    logic [NS-1:0][NW-1:0][WAY_WD-1:0] r;
    for (int s = 0; s < NS; s++)
      for (int w = 0; w < NW; w++) r[s][w] = WAY_WD'(w);
    return r;
  endfunction
  localparam logic [NS-1:0][NW-1:0][WAY_WD-1:0] AGE_RESET = age_init();

  // Victim selection
  always_comb begin
    logic found_invalid;
    found_invalid = 1'b0;
    victim_o      = '0;
    for (int w = NW - 1; w >= 0; w--) begin      // lowest invalid way wins
      if (!valid_i[w]) begin
        victim_o      = WAY_WD'(w);
        found_invalid = 1'b1;
      end
    end
    if (!found_invalid) begin
      for (int w = 0; w < NW; w++)
        if (age_q[index_i][w] == WAY_WD'(NW - 1)) victim_o = WAY_WD'(w);
    end
  end

  // Age update
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      age_q <= AGE_RESET;
    end else if (upd_i) begin
      for (int w = 0; w < NW; w++) begin
        if (age_q[index_i][w] < age_q[index_i][way_i])
          age_q[index_i][w] <= age_q[index_i][w] + 1'b1;
      end
      age_q[index_i][way_i] <= '0;
    end
  end

endmodule
