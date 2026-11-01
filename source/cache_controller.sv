module cache_controller #(
  parameter int AW    = 16,
  parameter int C_DW  = 8,
  parameter int M_DW  = 128,
  parameter int CL    = 256,
  parameter int NW    = 4,

  parameter int SETS  = CL / NW,
  parameter int LINE_WORDS = M_DW / C_DW,
  parameter int OFFSET_W = (LINE_WORDS <= 1) ? 0 : $clog2(LINE_WORDS),
  parameter int SET_W = (SETS <= 1) ? 0 : $clog2(SETS),
  parameter int TAG_W = AW - OFFSET_W - SET_W,
  parameter int WAY_W = (NW <= 1) ? 1 : $clog2(NW)
) (
  input  logic              clk_i,
  input  logic              arst_ni,

  input  logic [AW-1:0]     c_addr_i,
  input  logic              c_req_i,
  output logic [C_DW-1:0]   c_data_o,
  output logic              c_gnt_o,

  output logic [AW-1:0]     m_addr_o,
  output logic              m_req_o,
  input  logic [M_DW-1:0]   m_data_i,
  input  logic              m_gnt_i
);

  typedef enum logic [1:0] {IDLE, MEM_REQ, RESP} state_e;
  state_e state_q, state_d;

  logic [AW-1:0] req_addr_q;
  logic [M_DW-1:0] response_line_q;

  logic [SET_W-1:0] lookup_set;
  logic [TAG_W-1:0] lookup_tag;
  logic [OFFSET_W-1:0] lookup_offset;

  logic cache_hit;
  logic [WAY_W-1:0] cache_hit_way;
  logic [M_DW-1:0] cache_hit_line;
  logic [TAG_W-1:0] victim_tag;
  logic victim_valid;
  logic [WAY_W-1:0] victim_way;

  logic fill_en;
  logic [SET_W-1:0] fill_set;
  logic [TAG_W-1:0] fill_tag;
  logic [M_DW-1:0] fill_line;

  logic repl_commit_hit, repl_commit_miss;
  logic [AW-1:0] active_addr;
  logic [M_DW-1:0] selected_line;

  // During IDLE, decode the live request. During a miss, use the latched
  // address so the memory transaction is independent of requester changes.
  always_comb begin
    active_addr = (state_q == IDLE) ? c_addr_i : req_addr_q;

    if (SET_W == 0)
      lookup_set = '0;
    else
      lookup_set = active_addr[OFFSET_W +: SET_W];

    if (OFFSET_W == 0)
      lookup_offset = '0;
    else
      lookup_offset = active_addr[0 +: OFFSET_W];

    lookup_tag = active_addr[AW-1 -: TAG_W];
  end

  cache_memory #(
    .SETS(SETS), .NW(NW), .TAG_W(TAG_W), .M_DW(M_DW), .WAY_W(WAY_W)
  ) u_cache_memory (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .lookup_set_i(lookup_set),
    .lookup_tag_i(lookup_tag),
    .hit_o(cache_hit),
    .hit_way_o(cache_hit_way),
    .hit_line_o(cache_hit_line),
    .fill_en_i(fill_en),
    .fill_set_i(fill_set),
    .fill_way_i(victim_way),
    .fill_tag_i(fill_tag),
    .fill_line_i(fill_line),
    .selected_victim_tag_o(victim_tag),
    .selected_victim_valid_o(victim_valid)
  );

  cache_replacement #(
    .SETS(SETS), .NW(NW), .TAG_W(TAG_W),
    .SET_W((SETS <= 1) ? 1 : $clog2(SETS)), .WAY_W(WAY_W)
  ) u_replacement (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .set_i(lookup_set),
    .tag_i(lookup_tag),
    .hit_i(cache_hit),
    .hit_way_i(cache_hit_way),
    .victim_way_o(victim_way),
    .commit_miss_i(repl_commit_miss),
    .evicted_tag_i(victim_tag),
    .evicted_valid_i(victim_valid),
    .commit_hit_i(repl_commit_hit)
  );

  always_comb begin
    state_d          = state_q;
    c_gnt_o          = 1'b0;
    c_data_o         = '0;
    m_req_o          = 1'b0;
    m_addr_o         = '0;
    fill_en          = 1'b0;
    fill_set         = '0;
    fill_tag         = '0;
    fill_line        = m_data_i;
    repl_commit_hit  = 1'b0;
    repl_commit_miss = 1'b0;
    selected_line    = cache_hit_line;

    case (state_q)
      IDLE: begin
        if (c_req_i && cache_hit) begin
          c_gnt_o         = 1'b1;
          repl_commit_hit = 1'b1;
          selected_line   = cache_hit_line;
          state_d         = IDLE;
        end else if (c_req_i && !cache_hit) begin
          state_d = MEM_REQ;
        end
      end

      MEM_REQ: begin
        m_req_o = 1'b1;
        // Align to a complete cache line by clearing line-word offset bits.
        m_addr_o = req_addr_q;
        if (OFFSET_W != 0)
          m_addr_o[OFFSET_W-1:0] = '0;

        if (m_gnt_i) begin
          fill_en          = 1'b1;
          fill_set         = lookup_set;
          fill_tag         = lookup_tag;
          fill_line        = m_data_i;
          repl_commit_miss = 1'b1;
          state_d          = RESP;
        end
      end

      RESP: begin
        c_gnt_o       = 1'b1;
        selected_line = response_line_q;
        state_d       = IDLE;
      end

      default: state_d = IDLE;
    endcase

    if (OFFSET_W == 0)
      c_data_o = selected_line[C_DW-1:0];
    else
      c_data_o = selected_line[lookup_offset*C_DW +: C_DW];
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      state_q         <= IDLE;
      req_addr_q      <= '0;
      response_line_q <= '0;
    end else begin
      state_q <= state_d;

      if (state_q == IDLE && c_req_i && !cache_hit)
        req_addr_q <= c_addr_i;

      if (state_q == MEM_REQ && m_gnt_i)
        response_line_q <= m_data_i;
    end
  end

endmodule