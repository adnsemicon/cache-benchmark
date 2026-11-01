// SRRIP replacement state for each set. The legacy module name is retained so
// existing source lists continue to compile without changes.
module simple_cache_lru #(
  parameter int NS = 64,
  parameter int NW = 4,
  localparam int IDX_WD = (NS > 1) ? $clog2(NS) : 1,
  localparam int WAY_WD = (NW > 1) ? $clog2(NW) : 1
) (
  input  logic              clk_i,
  input  logic              arst_ni,
  input  logic [IDX_WD-1:0] index_i,
  input  logic [NW-1:0]     valid_i,
  input  logic              upd_i,
  input  logic [WAY_WD-1:0] way_i,
  input  logic              miss_i,
  input  logic              fill_i,
  input  logic [IDX_WD-1:0] fill_index_i,
  input  logic [WAY_WD-1:0] fill_way_i,
  output logic [WAY_WD-1:0] victim_o
);
  // RRPV 0 = near/immediate reuse, 3 = distant re-reference.
  logic [NS-1:0][NW-1:0][1:0] rrpv_q;
  logic                      recent_fill_q;
  logic [IDX_WD-1:0]         recent_fill_index_q;
  logic [WAY_WD-1:0]         recent_fill_way_q;

  always_comb begin : choose_victim
    logic found_invalid;
    logic [1:0] max_rrpv;

    found_invalid = 1'b0;
    max_rrpv = '0;
    victim_o = '0;

    // Fill the lowest numbered invalid way before replacing a valid line.
    for (int w = 0; w < NW; w++) begin
      if (!found_invalid && !valid_i[w]) begin
        victim_o = WAY_WD'(w);
        found_invalid = 1'b1;
      end
    end

    if (!found_invalid) begin
      for (int w = 0; w < NW; w++)
        if (rrpv_q[index_i][w] > max_rrpv) max_rrpv = rrpv_q[index_i][w];
      for (int w = 0; w < NW; w++) begin
        if (rrpv_q[index_i][w] == max_rrpv) begin
          victim_o = WAY_WD'(w);
          break;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin : update_rrpv
    logic [1:0] max_rrpv;
    logic [1:0] age_delta;
    logic [2:0] aged_value;
    logic       recent_fill_hit;

    if (!arst_ni) begin
      rrpv_q               <= '1;
      recent_fill_q        <= 1'b0;
      recent_fill_index_q  <= '0;
      recent_fill_way_q    <= '0;
    end else if (fill_i) begin
      // SRRIP inserts demand lines at RRPV 2.
      rrpv_q[fill_index_i][fill_way_i] <= 2'd2;
      recent_fill_q                   <= 1'b1;
      recent_fill_index_q             <= fill_index_i;
      recent_fill_way_q               <= fill_way_i;
    end else if (miss_i && (&valid_i)) begin
      // Age all ways by the minimum amount needed to make a victim eligible.
      max_rrpv = '0;
      for (int w = 0; w < NW; w++)
        if (rrpv_q[index_i][w] > max_rrpv) max_rrpv = rrpv_q[index_i][w];
      age_delta = 2'd3 - max_rrpv;
      for (int w = 0; w < NW; w++) begin
        aged_value = {1'b0, rrpv_q[index_i][w]} + {1'b0, age_delta};
        rrpv_q[index_i][w] <= (aged_value > 3) ? 2'd3 : aged_value[1:0];
      end
    end else if (upd_i) begin
      // The grant following a refill completes the original miss. Preserve
      // the insertion value instead of promoting the line as a later hit.
      recent_fill_hit = recent_fill_q &&
                        (index_i == recent_fill_index_q) &&
                        (way_i == recent_fill_way_q);
      if (!recent_fill_hit) rrpv_q[index_i][way_i] <= 2'd0;
      recent_fill_q <= 1'b0;
    end
  end
endmodule
