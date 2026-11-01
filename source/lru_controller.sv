// lru_controller : Invalid-first replacement with pseudo-LRU for four ways.
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
  input  logic [WAYW-1:0]   touch_way_i,

  output logic [WAYW-1:0]   victim_way_o
);

  localparam int NUM_SETS = CL / NW;
  logic [NUM_SETS-1:0][2:0] lru_state;
  logic [NUM_SETS-1:0][WAYW-1:0] rr_next;
  logic [WAYW-1:0] policy_victim;

  generate
    if (NW == 4) begin : g_plru
      always_comb begin
        if (!lru_state[index_i][2]) begin
          policy_victim = lru_state[index_i][1] ? 2'd1 : 2'd0;
        end else begin
          policy_victim = lru_state[index_i][0] ? 2'd3 : 2'd2;
        end
      end

      always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
          lru_state <= '0;
        end else if (touch_i) begin
          unique case (touch_way_i)
            2'd0: lru_state[index_i] <= {1'b1, 1'b1, lru_state[index_i][0]};
            2'd1: lru_state[index_i] <= {1'b1, 1'b0, lru_state[index_i][0]};
            2'd2: lru_state[index_i] <= {1'b0, lru_state[index_i][1], 1'b1};
            2'd3: lru_state[index_i] <= {1'b0, lru_state[index_i][1], 1'b0};
            default: ;
          endcase
        end
      end
    end else begin : g_round_robin
      always_comb begin
        policy_victim = rr_next[index_i];
      end

      always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
          rr_next <= '0;
        end else if (touch_i) begin
          if (touch_way_i == WAYW'(NW - 1)) begin
            rr_next[index_i] <= '0;
          end else begin
            rr_next[index_i] <= touch_way_i + 1'b1;
          end
        end
      end
    end
  endgenerate

  always_comb begin
    victim_way_o = policy_victim;
    for (int w = 0; w < NW; w++) begin
      if (!valid_i[w]) begin
        victim_way_o = WAYW'(w);
        break;
      end
    end
  end

endmodule