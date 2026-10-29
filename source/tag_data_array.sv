module tag_data_array
  import cache_pkg::*;
#(
  parameter int SETS = 64,
  parameter int NW   = 4
)(
  input  logic             clk_i,
  input  logic             arst_ni,

  input  index_t           index_i,
  input  tag_t             tag_i,

  // Write port
  input  logic             we_i,
  input  logic [1:0]       way_i,
  input  cache_line_t      wdata_i,

  // Read / Lookup
  output logic             hit_o,
  output logic [1:0]       hit_way_o,
  output line_t            hit_data_o,
  output cache_line_t      line_o [NW-1:0]
);

  cache_line_t mem [SETS-1:0][NW-1:0];

  // Lookup
  always_comb begin
    hit_o     = 1'b0;
    hit_way_o = '0;
    hit_data_o = '0;

    for (int w = 0; w < NW; w++) begin
      line_o[w] = mem[index_i][w];

      if (mem[index_i][w].valid && mem[index_i][w].tag == tag_i) begin
        hit_o     = 1'b1;
        hit_way_o = w[1:0];
        hit_data_o = mem[index_i][w].data;
      end
    end
  end

  // Write
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < SETS; s++)
        for (int w = 0; w < NW; w++)
          mem[s][w] <= '0;
    end
    else if (we_i) begin
      mem[index_i][way_i] <= wdata_i;
    end
  end

endmodule