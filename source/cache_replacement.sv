module cache_replacement #(
    parameter int SETS  = 64,
    parameter int NW    = 4,
    parameter int TAG_W = 8,
    parameter int SET_W = (SETS <= 1) ? 1 : $clog2(SETS),
    parameter int WAY_W = (NW <= 1) ? 1 : $clog2(NW),
    parameter int AGE_W = 16
) (
    input logic clk_i,
    input logic arst_ni,

    input logic [SET_W-1:0] set_i,
    input logic [TAG_W-1:0] tag_i,
    input logic             hit_i,
    input logic [WAY_W-1:0] hit_way_i,

    output logic [WAY_W-1:0] victim_way_o,

    input logic             commit_miss_i,
    input logic [TAG_W-1:0] evicted_tag_i,
    input logic             evicted_valid_i,

    input logic commit_hit_i
);

  // ---------------------------------------------------------
  // ARC resident lists:
  // 00 = T1 (recent)
  // 01 = T2 (frequent)
  // 11 = Invalid
  // ---------------------------------------------------------

  logic [1:0] resident_list[0:SETS-1][0:NW-1];

  logic [AGE_W-1:0] resident_age[0:SETS-1][0:NW-1];

  // ---------------------------------------------------------
  // ARC ghost lists
  // ---------------------------------------------------------

  logic [TAG_W-1:0] b1_tag[0:SETS-1][0:NW-1];
  logic [TAG_W-1:0] b2_tag[0:SETS-1][0:NW-1];

  logic b1_valid[0:SETS-1][0:NW-1];
  logic b2_valid[0:SETS-1][0:NW-1];

  logic [AGE_W-1:0] b1_age[0:SETS-1][0:NW-1];
  logic [AGE_W-1:0] b2_age[0:SETS-1][0:NW-1];

  // ---------------------------------------------------------
  // Adaptive ARC parameter
  // ---------------------------------------------------------

  localparam int P_W = (NW <= 1) ? 1 : $clog2(NW + 1);

  logic [P_W-1:0] p[0:SETS-1];

  logic [AGE_W-1:0] age_counter[0:SETS-1];

  // ---------------------------------------------------------
  // Lookup and replacement variables
  // ---------------------------------------------------------

  logic ghost_b1_hit;
  logic ghost_b2_hit;

  integer ghost_b1_slot;
  integer ghost_b2_slot;

  integer t1_count;
  integer t2_count;

  integer b1_count;
  integer b2_count;

  integer invalid_way;

  integer oldest_t1_way;
  integer oldest_t2_way;

  integer oldest_t1_age;
  integer oldest_t2_age;

  integer oldest_b1_slot;
  integer oldest_b2_slot;

  integer oldest_b1_age;
  integer oldest_b2_age;

  integer delta_p;

  function automatic integer calculate_delta(input integer numerator, input integer denominator);

    integer result;

    begin

      result = 1;

      if (denominator > 0) begin

        for (int q = 1; q <= NW; q++) begin

          if (numerator >= (q * denominator)) result = q;

        end

      end

      return result;

    end

  endfunction

  // ---------------------------------------------------------
  // ARC lookup and victim selection
  // ---------------------------------------------------------

  always_comb begin

    ghost_b1_hit = 1'b0;
    ghost_b2_hit = 1'b0;

    ghost_b1_slot = 0;
    ghost_b2_slot = 0;

    t1_count = 0;
    t2_count = 0;

    b1_count = 0;
    b2_count = 0;

    invalid_way = -1;

    oldest_t1_way = 0;
    oldest_t2_way = 0;

    oldest_t1_age = 32'h7fffffff;
    oldest_t2_age = 32'h7fffffff;

    oldest_b1_slot = 0;
    oldest_b2_slot = 0;

    oldest_b1_age = 32'h7fffffff;
    oldest_b2_age = 32'h7fffffff;

    delta_p = 1;

    // -----------------------------------------------------
    // Search resident and ghost lists
    // -----------------------------------------------------

    for (int i = 0; i < NW; i++) begin

      // Count resident lists

      if (resident_list[set_i][i] == 2'b00) begin

        t1_count++;

        if (resident_age[set_i][i] < oldest_t1_age) begin
          oldest_t1_age = resident_age[set_i][i];
          oldest_t1_way = i;
        end

      end else if (resident_list[set_i][i] == 2'b01) begin

        t2_count++;

        if (resident_age[set_i][i] < oldest_t2_age) begin
          oldest_t2_age = resident_age[set_i][i];
          oldest_t2_way = i;
        end

      end else if (resident_list[set_i][i] == 2'b11) begin

        if (invalid_way < 0) invalid_way = i;

      end

      // Search B1

      if (b1_valid[set_i][i]) begin

        b1_count++;

        if (b1_tag[set_i][i] == tag_i) begin
          ghost_b1_hit  = 1'b1;
          ghost_b1_slot = i;
        end

        if (b1_age[set_i][i] < oldest_b1_age) begin
          oldest_b1_age  = b1_age[set_i][i];
          oldest_b1_slot = i;
        end

      end

      // Search B2

      if (b2_valid[set_i][i]) begin

        b2_count++;

        if (b2_tag[set_i][i] == tag_i) begin
          ghost_b2_hit  = 1'b1;
          ghost_b2_slot = i;
        end

        if (b2_age[set_i][i] < oldest_b2_age) begin
          oldest_b2_age  = b2_age[set_i][i];
          oldest_b2_slot = i;
        end

      end

    end

    // -----------------------------------------------------
    // Adaptive ARC parameter adjustment
    // -----------------------------------------------------

    if (ghost_b1_hit && (b1_count > 0)) begin
      delta_p = calculate_delta(b2_count, b1_count);
    end else if (ghost_b2_hit && (b2_count > 0)) begin
      delta_p = calculate_delta(b1_count, b2_count);
    end

    // -----------------------------------------------------
    // ARC victim selection
    // -----------------------------------------------------

    if (invalid_way >= 0) begin
      victim_way_o = WAY_W'(invalid_way);
    end

        else if (
            (t1_count > int'(p[set_i])) ||
            (ghost_b2_hit && (t1_count == int'(p[set_i])))
        ) begin

      // Replace from T1

      if (oldest_t1_age != 32'h7fffffff) victim_way_o = WAY_W'(oldest_t1_way);
      else victim_way_o = WAY_W'(oldest_t2_way);

    end else begin

      // Replace from T2

      if (oldest_t2_age != 32'h7fffffff) victim_way_o = WAY_W'(oldest_t2_way);
      else victim_way_o = WAY_W'(oldest_t1_way);

    end

  end

  // ---------------------------------------------------------
  // ARC state update
  // ---------------------------------------------------------

  always_ff @(posedge clk_i or negedge arst_ni) begin

    if (!arst_ni) begin

      for (int s = 0; s < SETS; s++) begin

        p[s]           <= '0;
        age_counter[s] <= '0;

        for (int w = 0; w < NW; w++) begin

          resident_list[s][w] <= 2'b11;
          resident_age[s][w] <= '0;

          b1_tag[s][w] <= '0;
          b2_tag[s][w] <= '0;

          b1_valid[s][w] <= 1'b0;
          b2_valid[s][w] <= 1'b0;

          b1_age[s][w] <= '0;
          b2_age[s][w] <= '0;

        end

      end

    end else begin

      // -------------------------------------------------
      // CACHE HIT
      // -------------------------------------------------

      if (commit_hit_i && hit_i) begin

        case (resident_list[set_i][hit_way_i])

          2'b00: begin
            // T1 hit: promote to T2.
            resident_list[set_i][hit_way_i] <= 2'b01;
          end

          2'b01: begin
            // T2 hit: remain in T2.
            resident_list[set_i][hit_way_i] <= 2'b01;
          end

          default: begin
            // Invalid entries should not receive hit updates.
          end

        endcase

        resident_age[set_i][hit_way_i] <= age_counter[set_i] + 1'b1;

        age_counter[set_i] <= age_counter[set_i] + 1'b1;

      end

      // -------------------------------------------------
      // CACHE MISS / COMPLETED MEMORY FILL
      // -------------------------------------------------

      if (commit_miss_i) begin

        // ---------------------------------------------
        // Adapt p
        // ---------------------------------------------

        if (ghost_b1_hit) begin

          if (int'(p[set_i]) + delta_p > NW) p[set_i] <= P_W'(NW);
          else p[set_i] <= p[set_i] + P_W'(delta_p);

        end else if (ghost_b2_hit) begin

          if (delta_p > int'(p[set_i])) p[set_i] <= '0;
          else p[set_i] <= p[set_i] - P_W'(delta_p);

        end

        // ---------------------------------------------
        // Update ghost history
        // ---------------------------------------------

        if (evicted_valid_i) begin

          if (resident_list[set_i][victim_way_o] == 2'b00) begin

            // Evicted from T1 -> B1

            if (!b1_valid[set_i][victim_way_o]) begin

              b1_tag[set_i][victim_way_o]   <= evicted_tag_i;

              b1_valid[set_i][victim_way_o] <= 1'b1;

              b1_age[set_i][victim_way_o]   <= age_counter[set_i] + 1'b1;

            end else begin

              // Replace oldest B1 entry.

              b1_tag[set_i][oldest_b1_slot]   <= evicted_tag_i;

              b1_valid[set_i][oldest_b1_slot] <= 1'b1;

              b1_age[set_i][oldest_b1_slot]   <= age_counter[set_i] + 1'b1;

            end

          end else begin

            // Evicted from T2 -> B2

            if (!b2_valid[set_i][victim_way_o]) begin

              b2_tag[set_i][victim_way_o]   <= evicted_tag_i;

              b2_valid[set_i][victim_way_o] <= 1'b1;

              b2_age[set_i][victim_way_o]   <= age_counter[set_i] + 1'b1;

            end else begin

              // Replace oldest B2 entry.

              b2_tag[set_i][oldest_b2_slot]   <= evicted_tag_i;

              b2_valid[set_i][oldest_b2_slot] <= 1'b1;

              b2_age[set_i][oldest_b2_slot]   <= age_counter[set_i] + 1'b1;

            end

          end

        end

        // ---------------------------------------------
        // Insert incoming block
        // ---------------------------------------------

        if (ghost_b1_hit || ghost_b2_hit) resident_list[set_i][victim_way_o] <= 2'b01;
        else resident_list[set_i][victim_way_o] <= 2'b00;

        resident_age[set_i][victim_way_o] <= age_counter[set_i] + 1'b1;

        age_counter[set_i] <= age_counter[set_i] + 1'b1;

        // ---------------------------------------------
        // Remove re-admitted ghost entries
        // ---------------------------------------------

        if (ghost_b1_hit) b1_valid[set_i][ghost_b1_slot] <= 1'b0;

        if (ghost_b2_hit) b2_valid[set_i][ghost_b2_slot] <= 1'b0;

      end

    end

  end

endmodule
