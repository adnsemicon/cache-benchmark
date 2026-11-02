// mru_controller : MRU replacement with invalid-way-first allocation.
module mru_controller #(
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
  input  logic [WAYW-1:0]   touch_way_i,

  output logic [WAYW-1:0]   victim_way_o
);

  localparam int NUM_SETS = CL / NW;
  localparam int AGE_W    = (NW > 1) ? $clog2(NW) : 1;

  logic [NUM_SETS-1:0][NW-1:0][AGE_W-1:0] age_mem;

  always_comb begin
    logic invalid_found;
    invalid_found = 1'b0;

    victim_way_o = '0;

    // invalid-way-first allocation
    for (int w = 0; w < NW; w++) begin
      if (!valid_i[w]) begin
        victim_way_o = WAYW'(w);
        invalid_found = 1'b1;
        break;
      end
    end

    // MRU victim selection: newest way wins (smallest age value)
    if (!invalid_found) begin
      victim_way_o = '0;
      for (int w = 1; w < NW; w++) begin
        if (age_mem[index_i][w] < age_mem[index_i][victim_way_o]) begin
          victim_way_o = WAYW'(w);
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int s = 0; s < NUM_SETS; s++) begin
        for (int w = 0; w < NW; w++) begin
          age_mem[s][w] <= AGE_W'(NW - 1 - w);
        end
      end
    end else if (touch_i && (int'(touch_way_i) < NW)) begin
      // touched way becomes most-recently-used (newest)
      for (int w = 0; w < NW; w++) begin
        if (w == int'(touch_way_i)) begin
          age_mem[index_i][w] <= '0;
        end else begin
          // move anything newer than the touched way one step older
          if (age_mem[index_i][w] < AGE_W'(NW-1)) begin
            age_mem[index_i][w] <= age_mem[index_i][w] + 1'b1;
          end
        end
      end
    end
  end

endmodule
