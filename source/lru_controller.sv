// lru_controller : LFU replacement with LRU tie-breaking.
module lru_controller #(
  parameter int CL = 256,
  parameter int NW = 4,
  parameter int IDXW = (CL / NW > 1) ? $clog2(CL / NW) : 1,
  parameter int WAYW = (NW > 1) ? $clog2(NW) : 1
)(
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic [IDXW-1:0]   index_i,
  input  logic [NW-1:0]     valid_i,
  input  logic              touch_i,
  input  logic              fill_i,
  input  logic [WAYW-1:0]   touch_way_i,

  output logic [WAYW-1:0]   victim_way_o
);

  localparam int NUM_SETS = CL / NW;
  localparam int AGE_W = (NW > 1) ? $clog2(NW) : 1;
  localparam int FREQ_W = 16;
  logic [NUM_SETS-1:0][NW-1:0][FREQ_W-1:0] frequency_mem;
  logic [NUM_SETS-1:0][NW-1:0][AGE_W-1:0] age_mem;

  always_comb begin
    logic [FREQ_W-1:0] lowest_frequency;
    logic [AGE_W-1:0] oldest_age;

    victim_way_o = '0;
    lowest_frequency = '1;
    oldest_age = '0;

    for (int w = 0; w < NW; w++) begin
      if (!valid_i[w]) begin
        victim_way_o = WAYW'(w);
        break;
      end
    end

    if (&valid_i) begin
      for (int w = 0; w < NW; w++) begin
        if ((frequency_mem[index_i][w] < lowest_frequency) ||
            ((frequency_mem[index_i][w] == lowest_frequency) &&
             (age_mem[index_i][w] >= oldest_age))) begin
          lowest_frequency = frequency_mem[index_i][w];
          oldest_age = age_mem[index_i][w];
          victim_way_o = WAYW'(w);
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < NUM_SETS; s++) begin
        for (int w = 0; w < NW; w++) begin
          frequency_mem[s][w] <= '0;
          age_mem[s][w] <= AGE_W'(NW - 1 - w);
        end
      end
    end else if (touch_i && (int'(touch_way_i) < NW)) begin
      for (int w = 0; w < NW; w++) begin
        if (w == int'(touch_way_i)) begin
          if (fill_i) begin
            frequency_mem[index_i][w] <= {{(FREQ_W-1){1'b0}}, 1'b1};
          end else if (frequency_mem[index_i][w] != {FREQ_W{1'b1}}) begin
            frequency_mem[index_i][w] <= frequency_mem[index_i][w] + 1'b1;
          end
          age_mem[index_i][w] <= '0;
        end else if (age_mem[index_i][w] < age_mem[index_i][touch_way_i]) begin
          age_mem[index_i][w] <= age_mem[index_i][w] + 1'b1;
        end
      end
    end
  end

endmodule
