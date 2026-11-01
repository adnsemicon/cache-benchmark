// cache_controller : FSM-based Cache Controller
module cache_controller #(
  parameter int NW   = 4,
  parameter int WAYW = (NW > 1) ? $clog2(NW) : 1
)(
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic              c_req_i,
  output logic              c_gnt_o,

  output logic              m_req_o,
  input  logic              m_gnt_i,

  input  logic              hit_i,
  input  logic [WAYW-1:0]   hit_way_i,
  input  logic [WAYW-1:0]   victim_i,

  output logic              bypass_o,
  output logic              fill_o,
  output logic [WAYW-1:0]   fill_way_o,
  output logic              touch_o,
  output logic [WAYW-1:0]   touch_way_o
);

  typedef enum logic [0:0] {
    IDLE      = 1'b0,
    WAIT_MEM  = 1'b1
  } state_e;

  state_e current_state, next_state;

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    next_state    = current_state;
    m_req_o       = 1'b0;
    c_gnt_o       = 1'b0;
    fill_o        = 1'b0;
    bypass_o      = 1'b0;
    fill_way_o    = victim_i;
    touch_o       = 1'b0;
    touch_way_o   = hit_way_i;

    unique case (current_state)
      IDLE: begin
        if (c_req_i) begin
          if (hit_i) begin
            c_gnt_o     = 1'b1;
            touch_o     = 1'b1;
            touch_way_o = hit_way_i;
            next_state  = IDLE;
          end else begin
            m_req_o    = 1'b1;
            next_state = WAIT_MEM;
          end
        end
      end

      WAIT_MEM: begin
        m_req_o = 1'b1;
        if (m_gnt_i) begin
          fill_o      = 1'b1;
          fill_way_o  = victim_i;
          bypass_o    = 1'b1;
          c_gnt_o     = 1'b1;
          touch_o     = 1'b1;
          touch_way_o = victim_i;
          next_state  = IDLE;
        end
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

endmodule