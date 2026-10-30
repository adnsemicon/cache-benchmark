
module lru_pinning_unit #(
  parameter int SETS = 64,
  parameter int NW   = 4,
  parameter int REPL = 2
)(
  input  logic clk_i,
  input  logic arst_ni,

  input  logic [$clog2(SETS)-1:0] index_i,
  input  logic hit_i,
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] hit_way_i,

  input  logic promote_i,
  input  logic fill_i,
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] fill_way_i,

  input  logic [NW-1:0] valid_i,

  output logic [(NW>1 ? $clog2(NW) : 1)-1:0] victim_way_o
);

  localparam int WB = (NW > 1) ? $clog2(NW) : 1;

  logic found_inv;
  logic [WB-1:0] inv_way;

  always_comb begin
    inv_way   = '0;
    found_inv = 1'b0;

    for (int w = NW-1; w >= 0; w--) begin
      if (!valid_i[w]) begin
        inv_way   = WB'(w);
        found_inv = 1'b1;
      end
    end
  end

  //==================================================
  // TRUE LRU
  //==================================================
  generate
    if (REPL == 0) begin : g_lru

      logic [WB-1:0] rank [SETS][NW];
      logic [WB-1:0] lru_way;
      logic [WB-1:0] touch_way;
      logic touch;

      assign touch = hit_i | promote_i | fill_i;

      assign touch_way = hit_i ? hit_way_i : fill_way_i;

      always_comb begin
        lru_way = '0;

        for (int w = 0; w < NW; w++) begin
          if (rank[index_i][w] == '0)
            lru_way = WB'(w);
        end
      end

      assign victim_way_o = found_inv ? inv_way : lru_way;

      always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
          for (int s = 0; s < SETS; s++)
            for (int w = 0; w < NW; w++)
              rank[s][w] <= WB'(w);
        end
        else if (touch) begin
          for (int w = 0; w < NW; w++) begin
            if (w == int'(touch_way))
              rank[index_i][w] <= WB'(NW-1);
            else if (rank[index_i][w] >
                     rank[index_i][touch_way])
              rank[index_i][w] <=
                  rank[index_i][w] - 1'b1;
          end
        end
      end

    end

    //==================================================
    // DRRIP
    //==================================================
    else if (REPL == 1) begin : g_drrip

      logic [1:0] rrpv [SETS][NW];

      logic [9:0] psel;
      logic [4:0] bctr;

      logic [1:0] max_r;
      logic [1:0] age_amt;
      logic [1:0] ins_val;

      logic [WB-1:0] rrip_way;

      logic lead_s;
      logic lead_b;
      logic use_b;

      // Leader sets:
      // index % 16 == 0 : SRRIP leader
      // index % 16 == 1 : BRRIP leader

      always_comb begin
        max_r = 2'd0;

        for (int w = 0; w < NW; w++) begin
          if (valid_i[w] && rrpv[index_i][w] > max_r)
            max_r = rrpv[index_i][w];
        end

        // Select the lowest-index way among
        // the ways having maximum RRPV.
        rrip_way = '0;

        for (int w = NW-1; w >= 0; w--) begin
          if (valid_i[w] &&
              rrpv[index_i][w] == max_r)
            rrip_way = WB'(w);
        end

        lead_s = 1'b0;
        lead_b = 1'b0;

        if (SETS >= 16) begin
          lead_s = (index_i[3:0] == 4'd0);
          lead_b = (index_i[3:0] == 4'd1);
        end

        use_b = lead_b ? 1'b1 :
                (lead_s ? 1'b0 : psel[9]);

        // SRRIP insertion: RRPV = 2
        // BRRIP insertion: usually 3,
        // occasionally 2 (1/32 probability).
        ins_val = use_b ?
                  ((bctr == 5'd31) ? 2'd2 : 2'd3)
                  : 2'd2;

        // Age remaining ways so that the
        // maximum valid RRPV reaches 3.
        age_amt = found_inv ? 2'd0 :
                  (2'd3 - max_r);
      end

      assign victim_way_o = found_inv ? inv_way : rrip_way;

      always_ff @(posedge clk_i or negedge arst_ni) begin

        if (!arst_ni) begin

          for (int s = 0; s < SETS; s++) begin
            for (int w = 0; w < NW; w++) begin
              rrpv[s][w] <= 2'd3;
            end
          end

          psel <= 10'd512;
          bctr <= '0;

        end
        else begin

          // Main-cache hit:
          // recently referenced, RRPV = 0.
          if (hit_i) begin

            rrpv[index_i][hit_way_i] <= 2'd0;

          end

          // Victim-cache promotion:
          // This is a re-reference, NOT a new insertion.
          else if (promote_i) begin

            rrpv[index_i][fill_way_i] <= 2'd0;

          end

          // Memory refill:
          else if (fill_i) begin

            for (int w = 0; w < NW; w++) begin

              if (w == int'(fill_way_i)) begin

                rrpv[index_i][w] <= ins_val;

              end
              else if (valid_i[w]) begin

                rrpv[index_i][w] <=
                    rrpv[index_i][w] + age_amt;

              end

            end

            // Set-dueling PSEL update.
            // SRRIP leader miss -> favor BRRIP.
            if (lead_s && psel != 10'h3FF)
              psel <= psel + 1'b1;

            // BRRIP leader miss -> favor SRRIP.
            if (lead_b && psel != 10'h000)
              psel <= psel - 1'b1;

            if (use_b)
              bctr <= bctr + 1'b1;

          end
        end
      end

    end

    //==================================================
    // TREE PLRU
    //==================================================
    else begin : g_plru

      if (NW == 4) begin : g_plru4

        logic [2:0] plru_tree [SETS];
        logic [WB-1:0] plru_way;
        logic [WB-1:0] touch_way;
        logic touch;

        assign touch = hit_i | promote_i | fill_i;
        assign touch_way = hit_i ? hit_way_i : fill_way_i;

        always_comb begin
          if (!plru_tree[index_i][0])
            plru_way = plru_tree[index_i][1] ? 2'd1 : 2'd0;
          else
            plru_way = plru_tree[index_i][2] ? 2'd3 : 2'd2;
        end

        assign victim_way_o =
            found_inv ? inv_way : plru_way;

        always_ff @(posedge clk_i or negedge arst_ni) begin
          if (!arst_ni) begin
            for (int s = 0; s < SETS; s++)
              plru_tree[s] <= '0;
          end
          else if (touch) begin

            case (touch_way)

              2'd0: begin
                plru_tree[index_i][0] <= 1'b1;
                plru_tree[index_i][1] <= 1'b1;
              end

              2'd1: begin
                plru_tree[index_i][0] <= 1'b1;
                plru_tree[index_i][1] <= 1'b0;
              end

              2'd2: begin
                plru_tree[index_i][0] <= 1'b0;
                plru_tree[index_i][2] <= 1'b1;
              end

              2'd3: begin
                plru_tree[index_i][0] <= 1'b0;
                plru_tree[index_i][2] <= 1'b0;
              end

              default: ;

            endcase
          end
        end

      end
      else if (NW == 2) begin : g_plru2

        logic [SETS-1:0] plru_bit;

        assign victim_way_o =
            found_inv ? inv_way :
            (plru_bit[index_i] ? 1'b1 : 1'b0);

        always_ff @(posedge clk_i or negedge arst_ni) begin
          if (!arst_ni) begin
            plru_bit <= '0;
          end
          else if (hit_i || promote_i || fill_i) begin
            // Point to the opposite way after access.
            plru_bit[index_i] <=
                hit_i ? ~hit_way_i[0] :
                        ~fill_way_i[0];
          end
        end

      end
      else begin : g_unsupported
        assign victim_way_o = inv_way;
      end

    end
  endgenerate

endmodule
