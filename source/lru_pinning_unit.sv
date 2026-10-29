module lru_pinning_unit
  import cache_pkg::*;
#(
  parameter int SETS = 64,
  parameter int NW   = 4
)(
  input  logic             clk_i,
  input  logic             arst_ni,

  input  index_t           index_i,
  input  logic             hit_i,
  input  logic [1:0]       hit_way_i,
  input  logic             allocate_i,
  input  logic [1:0]       alloc_way_i,

  input  cache_line_t      lines_i [NW-1:0],

  output logic [1:0]       victim_way_o,
  output logic             lock_o [NW-1:0]
);

  logic [1:0] age [SETS-1:0][NW-1:0];

  // Find victim (lowest age among unlocked)
  always_comb begin
    logic [1:0] min_age;
    victim_way_o = 2'b00;
    min_age      = 2'b11;

    for (int w = 0; w < NW; w++) begin
      lock_o[w] = lines_i[w].lock;

      if (!lines_i[w].lock) begin
        if (age[index_i][w] <= min_age) begin
          min_age      = age[index_i][w];
          victim_way_o = w[1:0];
        end
      end
    end
  end

  // Update age
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < SETS; s++)
        for (int w = 0; w < NW; w++)
          age[s][w] <= '0;
    end
    else begin
      if (hit_i) begin
        for (int w = 0; w < NW; w++) begin
          if (w[1:0] == hit_way_i)
            age[index_i][w] <= 2'b11;
          else if (age[index_i][w] > 0)
            age[index_i][w] <= age[index_i][w] - 1;
        end
      end
      else if (allocate_i) begin
        for (int w = 0; w < NW; w++) begin
          if (w[1:0] == alloc_way_i)
            age[index_i][w] <= 2'b11;
          else if (age[index_i][w] > 0)
            age[index_i][w] <= age[index_i][w] - 1;
        end
      end
    end
  end

endmodule