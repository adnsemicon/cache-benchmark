// Tree-based pseudo-LRU replacement state, one binary tree per set.
// Invalid ways are selected first; once full, tree bits guide victim selection.
module simple_cache_plru #(
  parameter int NS = 64,
  parameter int NW = 4,
  localparam int IDX_WD = (NS > 1) ? $clog2(NS) : 1,
  localparam int WAY_WD = (NW > 1) ? $clog2(NW) : 1,
  localparam int LEVELS = (NW > 1) ? $clog2(NW) : 0,
  localparam int LEAVES = 2 ** LEVELS,
  localparam int NODES = (LEAVES > 1) ? LEAVES - 1 : 1
) (
  input  logic              clk_i,
  input  logic              arst_ni,
  input  logic [IDX_WD-1:0] index_i,
  input  logic [NW-1:0]     valid_i,
  input  logic              upd_i,
  input  logic [WAY_WD-1:0] way_i,
  output logic [WAY_WD-1:0] victim_o
);
  // A zero bit points to the left subtree as the next victim; one points right.
  logic [NS-1:0][NODES-1:0] direction_q;

  always_comb begin : choose_victim
    logic found_invalid;
    int node;
    int start_way;
    int span;
    int right_start;

    found_invalid = 1'b0;
    victim_o = '0;
    node = 0;
    start_way = 0;
    span = LEAVES;

    // Prefer the lowest-numbered invalid way while a set is being filled.
    for (int w = 0; w < NW; w++) begin
      if (!found_invalid && !valid_i[w]) begin
        victim_o = WAY_WD'(w);
        found_invalid = 1'b1;
      end
    end

    if (!found_invalid && NW > 1) begin
      for (int level = 0; level < LEVELS; level++) begin
        span = span / 2;
        right_start = start_way + span;
        if (right_start >= NW || !direction_q[index_i][node]) begin
          node = 2 * node + 1;
        end else begin
          node = 2 * node + 2;
          start_way = right_start;
        end
      end
      victim_o = WAY_WD'(start_way);
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin : update_tree
    int node;
    int way_span;
    int branch;

    if (!arst_ni) begin
      direction_q <= '0;
    end else if (upd_i && NW > 1) begin
      node = 0;
      way_span = LEAVES;
      for (int level = 0; level < LEVELS; level++) begin
        way_span = way_span / 2;
        branch = (int'(way_i) / way_span) % 2;
        // After using a branch, mark its sibling as the less-recent choice.
        direction_q[index_i][node] <= (branch == 0);
        node = 2 * node + 1 + branch;
      end
    end
  end
endmodule
