// Set-local Adaptive Replacement Cache (ARC) replacement state.
//
// Each set maintains:
//   T1/T2: resident ways (T1 = recent, T2 = frequent)
//   B1/B2: ghost tags for recently evicted T1/T2 lines
//   p:     adaptive target size for T1
//
// This is a synthesizable, bounded hardware ARC variant. Ghost history is
// limited to NW entries per set. Replacement state changes only when an
// access is committed (a hit or a completed miss fill).
module cache_replacement #(
  parameter int SETS  = 64,
  parameter int NW    = 4,
  parameter int TAG_W = 8,
  parameter int SET_W = (SETS <= 1) ? 1 : $clog2(SETS),
  parameter int WAY_W = (NW <= 1) ? 1 : $clog2(NW),
  parameter int AGE_W = 16
) (
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic [SET_W-1:0]  set_i,
  input  logic [TAG_W-1:0]  tag_i,
  input  logic              hit_i,
  input  logic [WAY_W-1:0]  hit_way_i,

  // For a completed miss, victim_way_o identifies the way to overwrite.
  output logic [WAY_W-1:0]  victim_way_o,
  input  logic              commit_miss_i,
  input  logic [TAG_W-1:0]  evicted_tag_i,
  input  logic              evicted_valid_i,

  input  logic              commit_hit_i
);

  logic [1:0] resident_list [0:SETS-1][0:NW-1];
  logic [AGE_W-1:0] resident_age [0:SETS-1][0:NW-1];

  logic [TAG_W-1:0] b1_tag [0:SETS-1][0:NW-1];
  logic [TAG_W-1:0] b2_tag [0:SETS-1][0:NW-1];
  logic b1_valid [0:SETS-1][0:NW-1];
  logic b2_valid [0:SETS-1][0:NW-1];
  logic [AGE_W-1:0] b1_age [0:SETS-1][0:NW-1];
  logic [AGE_W-1:0] b2_age [0:SETS-1][0:NW-1];

  logic [((NW <= 1) ? 1 : $clog2(NW+1))-1:0] p [0:SETS-1];
  logic [AGE_W-1:0] age_counter [0:SETS-1];

  logic ghost_b1_hit, ghost_b2_hit;
  integer ghost_b1_slot, ghost_b2_slot;
  integer t1_count;
  integer oldest_t1_age, oldest_t2_age;
  integer oldest_t1_way, oldest_t2_way;
  integer invalid_way;

  always_comb begin
    ghost_b1_hit  = 1'b0;
    ghost_b2_hit  = 1'b0;
    ghost_b1_slot = 0;
    ghost_b2_slot = 0;

    t1_count       = 0;
    oldest_t1_age = 32'h7fffffff;
    oldest_t2_age = 32'h7fffffff;
    oldest_t1_way = 0;
    oldest_t2_way = 0;
    invalid_way   = -1;

    for (int i = 0; i < NW; i++) begin
      if (b1_valid[set_i][i] && b1_tag[set_i][i] == tag_i) begin
        ghost_b1_hit  = 1'b1;
        ghost_b1_slot = i;
      end
      if (b2_valid[set_i][i] && b2_tag[set_i][i] == tag_i) begin
        ghost_b2_hit  = 1'b1;
        ghost_b2_slot = i;
      end

      if (resident_list[set_i][i] == 2'd0)
        t1_count++;

      // A valid bit is represented by list value 2'b11 until first fill.
      if (resident_list[set_i][i] == 2'b11 && invalid_way < 0)
        invalid_way = i;

      if (resident_list[set_i][i] == 2'd0 &&
          resident_age[set_i][i] < oldest_t1_age) begin
        oldest_t1_age = resident_age[set_i][i];
        oldest_t1_way = i;
      end
      if (resident_list[set_i][i] == 2'd1 &&
          resident_age[set_i][i] < oldest_t2_age) begin
        oldest_t2_age = resident_age[set_i][i];
        oldest_t2_way = i;
      end
    end

    if (invalid_way >= 0)
      victim_way_o = WAY_W'(invalid_way);
    else if ((t1_count > int'(p[set_i])) && (oldest_t1_way >= 0))
      victim_way_o = WAY_W'(oldest_t1_way);
    else if (oldest_t2_age != 32'h7fffffff)
      victim_way_o = WAY_W'(oldest_t2_way);
    else
      victim_way_o = WAY_W'(oldest_t1_way);
  end

  // Reset list value 2'b11 marks an unused way. The memory valid bits remain
  // authoritative; this marker only helps choose empty ways first.
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < SETS; s++) begin
        p[s]           <= '0;
        age_counter[s] <= '0;
        for (int w = 0; w < NW; w++) begin
          resident_list[s][w] <= 2'b11;
          resident_age[s][w]  <= '0;
          b1_tag[s][w]        <= '0;
          b2_tag[s][w]        <= '0;
          b1_valid[s][w]      <= 1'b0;
          b2_valid[s][w]      <= 1'b0;
          b1_age[s][w]        <= '0;
          b2_age[s][w]        <= '0;
        end
      end
    end else begin
      if (commit_hit_i && hit_i) begin
        resident_list[set_i][hit_way_i] <= 2'd1; // promote T1 to T2
        resident_age[set_i][hit_way_i]  <= age_counter[set_i] + 1'b1;
        age_counter[set_i]              <= age_counter[set_i] + 1'b1;
      end

      if (commit_miss_i) begin
        // ARC adapts p according to which ghost list was hit.
        if (ghost_b1_hit) begin
          if (p[set_i] < NW)
            p[set_i] <= p[set_i] + 1'b1;
        end else if (ghost_b2_hit) begin
          if (p[set_i] > 0)
            p[set_i] <= p[set_i] - 1'b1;
        end

        // Record the evicted line in the corresponding ghost history.
        if (evicted_valid_i) begin
          if (resident_list[set_i][victim_way_o] == 2'd0) begin
            b1_tag[set_i][victim_way_o]   <= evicted_tag_i;
            b1_valid[set_i][victim_way_o] <= 1'b1;
            b1_age[set_i][victim_way_o]   <= age_counter[set_i] + 1'b1;
          end else begin
            b2_tag[set_i][victim_way_o]   <= evicted_tag_i;
            b2_valid[set_i][victim_way_o] <= 1'b1;
            b2_age[set_i][victim_way_o]   <= age_counter[set_i] + 1'b1;
          end
        end

        // A ghost hit is admitted to T2; a never-seen line starts in T1.
        if (ghost_b1_hit || ghost_b2_hit)
          resident_list[set_i][victim_way_o] <= 2'd1;
        else
          resident_list[set_i][victim_way_o] <= 2'd0;

        resident_age[set_i][victim_way_o] <= age_counter[set_i] + 1'b1;
        age_counter[set_i]                <= age_counter[set_i] + 1'b1;

        if (ghost_b1_hit)
          b1_valid[set_i][ghost_b1_slot] <= 1'b0;
        if (ghost_b2_hit)
          b2_valid[set_i][ghost_b2_slot] <= 1'b0;
      end
    end
  end

endmodule