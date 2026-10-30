// Replacement policy unit.  
// REPL = 0 : true LRU (rank based)
// REPL = 1 : DRRIP (set-dueling SRRIP vs BRRIP)
// REPL = 2 : Pseudo-LRU (Binary Tree based for 4 ways)
// REPL = 3 : pure BRRIP (Bimodal RRIP)
// In all cases an invalid way is always filled first.
module lru_pinning_unit #(
  parameter int SETS = 64,
  parameter int NW   = 4,
  parameter int REPL = 2
)(
  input  logic                               clk_i,
  input  logic                               arst_ni,

  input  logic [$clog2(SETS)-1:0]            index_i,
  input  logic                               hit_i,
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] hit_way_i,
  input  logic                               fill_i,
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] fill_way_i,
  input  logic [NW-1:0]                      valid_i,

  output logic [(NW>1 ? $clog2(NW) : 1)-1:0] victim_way_o
);

  localparam int WB = (NW > 1) ? $clog2(NW) : 1;

  logic            found_inv;
  logic [WB-1:0]   inv_way;

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

  generate
  //=================================================================
  // REPL = 0 : True LRU
  //=================================================================
  if (REPL == 0) begin : g_lru
    logic [WB-1:0] rank [SETS][NW];
    logic [WB-1:0] lru_way;
    logic          touch;
    logic [WB-1:0] touch_way;

    assign touch     = hit_i | fill_i;
    assign touch_way = hit_i ? hit_way_i : fill_way_i;

    always_comb begin
      lru_way = '0;
      for (int w = 0; w < NW; w++)
        if (rank[index_i][w] == '0) lru_way = WB'(w);
    end
    assign victim_way_o = found_inv ? inv_way : lru_way;

    always_ff @(posedge clk_i or negedge arst_ni) begin
      if (!arst_ni) begin
        for (int s = 0; s < SETS; s++)
          for (int w = 0; w < NW; w++)
            rank[s][w] <= WB'(w);
      end else if (touch) begin
        for (int w = 0; w < NW; w++) begin
          if (w == int'(touch_way))
            rank[index_i][w] <= WB'(NW-1);
          else if (rank[index_i][w] > rank[index_i][touch_way])
            rank[index_i][w] <= rank[index_i][w] - 1'b1;
        end
      end
    end

  //=================================================================
  // REPL = 1 : DRRIP
  //=================================================================
  end else if (REPL == 1) begin : g_drrip
    logic [1:0]  rrpv [SETS][NW];
    logic [9:0]  psel;
    logic [4:0]  bctr;

    logic [1:0]  max_r;
    logic [WB-1:0] rrip_way;
    logic [1:0]  age_amt;
    logic        lead_s, lead_b, use_b;
    logic [1:0]  ins_val;

    always_comb begin
      max_r = 2'd0;
      for (int w = 0; w < NW; w++)
        if (rrpv[index_i][w] > max_r) max_r = rrpv[index_i][w];

      rrip_way = '0;
      for (int w = NW-1; w >= 0; w--)
        if (rrpv[index_i][w] == max_r) rrip_way = WB'(w);

      age_amt = found_inv ? 2'd0 : (2'd3 - max_r);

      lead_s = 1'b0;
      lead_b = 1'b0;
      if (SETS >= 16) begin
        lead_s = (index_i[3:0] == 4'd0);
        lead_b = (index_i[3:0] == 4'd1);
      end
      use_b   = lead_b ? 1'b1 : (lead_s ? 1'b0 : psel[9]);
      ins_val = use_b ? ((bctr == 5'd31) ? 2'd2 : 2'd3) : 2'd2;
    end
    assign victim_way_o = found_inv ? inv_way : rrip_way;

    always_ff @(posedge clk_i or negedge arst_ni) begin
      if (!arst_ni) begin
        for (int s = 0; s < SETS; s++)
          for (int w = 0; w < NW; w++)
            rrpv[s][w] <= 2'd3;
        psel <= 10'd512;
        bctr <= '0;
      end else begin
        if (hit_i) begin
          rrpv[index_i][hit_way_i] <= 2'd0;
        end else if (fill_i) begin
          for (int w = 0; w < NW; w++) begin
            if (w == int'(fill_way_i)) rrpv[index_i][w] <= ins_val;
            else                       rrpv[index_i][w] <= rrpv[index_i][w] + age_amt;
          end
          if (lead_s && psel != 10'h3FF) psel <= psel + 1'b1;
          if (lead_b && psel != 10'h000) psel <= psel - 1'b1;
          if (use_b) bctr <= bctr + 1'b1;
        end
      end
    end

  //=================================================================
  // REPL = 2 : Pseudo-LRU
  //=================================================================
  end else if (REPL == 2) begin : g_plru
    logic [2:0] plru_tree [SETS];
    logic [WB-1:0] plru_way;
    logic          touch;
    logic [WB-1:0] touch_way;

    assign touch     = hit_i | fill_i;
    assign touch_way = hit_i ? hit_way_i : fill_way_i;

    always_comb begin
      if (!plru_tree[index_i][0])
        plru_way = plru_tree[index_i][1] ? 2'd1 : 2'd0;
      else
        plru_way = plru_tree[index_i][2] ? 2'd3 : 2'd2;
    end
    assign victim_way_o = found_inv ? inv_way : plru_way;

    always_ff @(posedge clk_i or negedge arst_ni) begin
      if (!arst_ni) begin
        for (int s = 0; s < SETS; s++)
          plru_tree[s] <= '0;
      end else if (touch) begin
        case (touch_way)
          2'd0: begin plru_tree[index_i][0] <= 1'b1; plru_tree[index_i][1] <= 1'b1; end
          2'd1: begin plru_tree[index_i][0] <= 1'b1; plru_tree[index_i][1] <= 1'b0; end
          2'd2: begin plru_tree[index_i][0] <= 1'b0; plru_tree[index_i][2] <= 1'b1; end
          2'd3: begin plru_tree[index_i][0] <= 1'b0; plru_tree[index_i][2] <= 1'b0; end
          default: ;
        endcase
      end
    end

  //=================================================================
  // REPL = 3 : Pure BRRIP (Bimodal RRIP)
  //=================================================================
  end else begin : g_brrip
    logic [1:0]  rrpv [SETS][NW];
    logic [4:0]  bctr;

    logic [1:0]  max_r;
    logic [WB-1:0] rrip_way;
    logic [1:0]  age_amt;
    logic [1:0]  ins_val;

    always_comb begin
      max_r = 2'd0;
      for (int w = 0; w < NW; w++)
        if (rrpv[index_i][w] > max_r) max_r = rrpv[index_i][w];

      rrip_way = '0;
      for (int w = NW-1; w >= 0; w--)
        if (rrpv[index_i][w] == max_r) rrip_way = WB'(w);

      age_amt = found_inv ? 2'd0 : (2'd3 - max_r);

      // BRRIP insertion: mostly 3, occasionally 2
      ins_val = (bctr == 5'd31) ? 2'd2 : 2'd3;
    end
    assign victim_way_o = found_inv ? inv_way : rrip_way;

    always_ff @(posedge clk_i or negedge arst_ni) begin
      if (!arst_ni) begin
        for (int s = 0; s < SETS; s++)
          for (int w = 0; w < NW; w++)
            rrpv[s][w] <= 2'd3;
        bctr <= '0;
      end else begin
        if (hit_i) begin
          rrpv[index_i][hit_way_i] <= 2'd0;
        end else if (fill_i) begin
          for (int w = 0; w < NW; w++) begin
            if (w == int'(fill_way_i))
              rrpv[index_i][w] <= ins_val;
            else
              rrpv[index_i][w] <= rrpv[index_i][w] + age_amt;
          end
          bctr <= bctr + 1'b1;
        end
      end
    end
  end
  endgenerate

endmodule