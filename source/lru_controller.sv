// lru_controller : True LRU implementation for 4-way set associativity
module lru_controller #(
  parameter int CL = 256,
  parameter int NW = 4
)(
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic [$clog2(CL/NW)-1:0] index_i,
  input  logic              touch_i,
  input  logic [$clog2(NW)-1:0] touch_way_i,

  output logic [$clog2(NW)-1:0] victim_way_o
);

  localparam int NUM_SETS = CL / NW;
  logic [NUM_SETS-1:0][2:0] lru_state;

  always_comb begin
    unique case (lru_state[index_i])
      3'b000, 3'b001, 3'b010: victim_way_o = 2'd3;
      3'b011, 3'b100:         victim_way_o = 2'd2;
      3'b101, 3'b110:         victim_way_o = 2'd1;
      3'b111:                 victim_way_o = 2'd0;
      default:                victim_way_o = 2'd0;
    endcase
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      lru_state <= '0;
    end else if (touch_i) begin
      unique case (touch_way_i)
        2'd0: lru_state[index_i] <= {1'b1, lru_state[index_i][1], 1'b1};
        2'd1: lru_state[index_i] <= {1'b1, 1'b0, lru_state[index_i][0]};
        2'd2: lru_state[index_i] <= {1'b0, lru_state[index_i][2], 1'b1};
        2'd3: lru_state[index_i] <= {1'b0, 1'b0, 1'b0};
        default: ;
      endcase
    end
  end

endmodule