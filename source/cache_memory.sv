module cache_memory #(
    parameter int SETS  = 64,
    parameter int NW    = 4,
    parameter int TAG_W = 8,
    parameter int M_DW  = 128,
    parameter int WAY_W = (NW <= 1) ? 1 : $clog2(NW)
) (
    input logic clk_i,
    input logic arst_ni,

    input  logic [((SETS <= 1) ? 1 : $clog2(SETS))-1:0] lookup_set_i,
    input  logic [                           TAG_W-1:0] lookup_tag_i,
    output logic                                        hit_o,
    output logic [                           WAY_W-1:0] hit_way_o,
    output logic [                            M_DW-1:0] hit_line_o,

    input logic                                        fill_en_i,
    input logic [((SETS <= 1) ? 1 : $clog2(SETS))-1:0] fill_set_i,
    input logic [                           WAY_W-1:0] fill_way_i,
    input logic [                           TAG_W-1:0] fill_tag_i,
    input logic [                            M_DW-1:0] fill_line_i,

    output logic [TAG_W-1:0] selected_victim_tag_o,
    output logic             selected_victim_valid_o
);

  localparam int SET_W = (SETS <= 1) ? 1 : $clog2(SETS);

  logic [ M_DW-1:0] data_mem [0:SETS-1][0:NW-1];
  logic [TAG_W-1:0] tag_mem  [0:SETS-1][0:NW-1];
  logic             valid_mem[0:SETS-1][0:NW-1];
  logic [   NW-1:0] way_hit;

  integer s, w;

  // This is Cache Lookup operation
  always_comb begin

    way_hit    = '0;
    hit_o      = 1'b0;
    hit_way_o  = '0;
    hit_line_o = '0;

    // Parallel tag comparison
    for (int k = 0; k < NW; k++) begin

      way_hit[k] = valid_mem[lookup_set_i][k] && (tag_mem[lookup_set_i][k] == lookup_tag_i);

    end

    // Detect whether any way matches
    hit_o = |way_hit;

    // One-hot data selection
    for (int k = 0; k < NW; k++) begin

      hit_line_o |= data_mem[lookup_set_i][k] & {M_DW{way_hit[k]}};

    end

    // Encode the matching way
    for (int k = 0; k < NW; k++) begin

      if (way_hit[k]) hit_way_o = WAY_W'(k);

    end

    // Victim metadata lookup
    selected_victim_tag_o   = tag_mem[lookup_set_i][fill_way_i];

    selected_victim_valid_o = valid_mem[lookup_set_i][fill_way_i];

  end

  always_ff @(posedge clk_i or negedge arst_ni) begin

    if (!arst_ni) begin

      for (int s = 0; s < SETS; s++) begin
        for (int w = 0; w < NW; w++) begin
          valid_mem[s][w] <= 1'b0;
        end
      end

    end else if (fill_en_i) begin

      tag_mem[fill_set_i][fill_way_i]   <= fill_tag_i;
      data_mem[fill_set_i][fill_way_i]  <= fill_line_i;
      valid_mem[fill_set_i][fill_way_i] <= 1'b1;

    end

  end

endmodule
