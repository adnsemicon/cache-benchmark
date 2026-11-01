// -----------------------------------------------------------------------------
// simple_cache_ctrl : control FSM and memory-side handshake.
//
//   S_IDLE  : hit  -> grant the request this cycle (and tell the LRU)
//             miss -> latch miss address + victim way, go to S_REFILL
//   S_REFILL: m_req_o high with the line-aligned address until m_gnt_i;
//             then pulse fill_en_o (arrays are written) and return to S_IDLE.
//             The request is then retried, hits, and is granted.
// -----------------------------------------------------------------------------
module simple_cache_ctrl
  import simple_cache_pkg::*;
#(
  parameter int AW       = 16,
  parameter int LINE_BYTES = 16,
  parameter int NW       = 4,
  localparam int WAY_WD  = clog2_min1(NW)
) (
  input  logic              clk_i,
  input  logic              arst_ni,

  // requester side
  input  logic [AW-1:0]     c_addr_i,
  input  logic              c_req_i,
  input  logic              hit_i,
  output logic              c_gnt_o,

  // replacement policy
  input  logic [WAY_WD-1:0] victim_i,
  output logic              lru_upd_o,

  // line fill into tag/data arrays
  output logic              fill_en_o,
  output logic [WAY_WD-1:0] fill_way_o,
  output logic [AW-1:0]     fill_addr_o,

  // memory side
  output logic [AW-1:0]     m_addr_o,
  output logic              m_req_o,
  input  logic              m_gnt_i
);

  state_e            state_q;
  logic [AW-1:0]     miss_addr_q;
  logic [WAY_WD-1:0] victim_q;

  assign c_gnt_o     = c_req_i && hit_i && (state_q == S_IDLE);
  assign lru_upd_o   = c_gnt_o;

  assign m_req_o     = (state_q == S_REFILL);
  assign m_addr_o    = miss_addr_q - (miss_addr_q % LINE_BYTES);

  assign fill_en_o   = m_req_o && m_gnt_i;
  assign fill_way_o  = victim_q;
  assign fill_addr_o = miss_addr_q;

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      state_q     <= S_IDLE;
      miss_addr_q <= '0;
      victim_q    <= '0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (c_req_i && !hit_i) begin
            state_q     <= S_REFILL;
            miss_addr_q <= c_addr_i;
            victim_q    <= victim_i;
          end
        end
        S_REFILL: begin
          if (m_gnt_i) state_q <= S_IDLE;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
