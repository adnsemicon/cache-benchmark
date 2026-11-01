// simple_cache : Parameterizable Set-Associative Read-Only Cache (Fixed)
module simple_cache #(
  parameter int AW   = 16,   // Address Width
  parameter int C_DW = 8,    // Cache Data Width (CPU side)
  parameter int M_DW = 128,  // Memory Data Width (Cache Line size)
  parameter int CL   = 256,  // Total Cache Lines
  parameter int NW   = 4     // Number of Ways (Associativity)
)(
  input  logic              arst_ni,
  input  logic              clk_i,

  // CPU Interface
  input  logic [AW-1:0]     c_addr_i,
  input  logic              c_req_i,
  output logic [C_DW-1:0]   c_data_o,
  output logic              c_gnt_o,

  // Memory Interface
  output logic [AW-1:0]     m_addr_o,
  output logic              m_req_o,
  input  logic [M_DW-1:0]   m_data_i,
  input  logic              m_gnt_i
);

  // Derived Parameters
  localparam int NUM_SETS = CL / NW;
  localparam int INDEX_W  = $clog2(NUM_SETS);
  localparam int OFFSET_W = $clog2(M_DW / 8);
  localparam int TAG_W    = AW - INDEX_W - OFFSET_W;
  localparam int WAY_W    = (NW > 1) ? $clog2(NW) : 1;

  // Address Decoding
  logic [TAG_W-1:0]    c_tag;
  logic [INDEX_W-1:0]  c_index;
  logic [OFFSET_W-1:0] c_offset;

  assign c_tag    = c_addr_i[AW-1 : AW-TAG_W];
  assign c_index  = c_addr_i[OFFSET_W + INDEX_W - 1 : OFFSET_W];
  assign c_offset = c_addr_i[OFFSET_W-1 : 0];

  // Control Signals & Interconnects
  logic              hit;
  logic [WAY_W-1:0]  hit_way;
  logic [WAY_W-1:0]  victim_way;
  logic              bypass;
  logic              fill;
  logic [WAY_W-1:0]  fill_way;
  logic              touch;
  logic [WAY_W-1:0]  touch_way;
  logic [NW-1:0]     valid_vec;

  // Memory Address (Cache-line aligned)
  assign m_addr_o = {c_addr_i[AW-1 : OFFSET_W], {OFFSET_W{1'b0}}};

  // 1. Tag Array Submodule
  tag_array #(
    .AW(AW), .CL(CL), .NW(NW)
  ) u_tag_array (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .index_i(c_index),
    .tag_i(c_tag),
    .fill_i(fill),
    .fill_way_i(fill_way),
    .hit_o(hit),
    .hit_way_o(hit_way),
    .valid_o(valid_vec)
  );

  // 2. Data Array Submodule
  data_array #(
    .CL(CL), .NW(NW), .M_DW(M_DW), .C_DW(C_DW)
  ) u_data_array (
    .clk_i(clk_i),
    .index_i(c_index),
    .fill_i(fill),
    .fill_way_i(fill_way),
    .fill_data_i(m_data_i),
    .hit_way_i(hit_way),
    .c_offset_i(c_offset),
    .m_data_i(m_data_i),
    .bypass_i(bypass),
    .c_data_o(c_data_o)
  );

  // 3. LRU Controller Submodule
  lru_controller #(
    .CL(CL), .NW(NW), .IDXW((INDEX_W > 0) ? INDEX_W : 1), .WAYW(WAY_W)
  ) u_lru_controller (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .index_i(c_index),
    .valid_i(valid_vec),
    .touch_i(touch),
    .touch_way_i(touch_way),
    .victim_way_o(victim_way)
  );

  // 4. Cache Controller Submodule (FSM-based)
  cache_controller #(
    .NW(NW)
  ) u_cache_controller (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .c_req_i(c_req_i),
    .c_gnt_o(c_gnt_o),
    .m_req_o(m_req_o),
    .m_gnt_i(m_gnt_i),
    .hit_i(hit),
    .hit_way_i(hit_way),
    .victim_i(victim_way),
    .bypass_o(bypass),
    .fill_o(fill),
    .fill_way_o(fill_way),
    .touch_o(touch),
    .touch_way_o(touch_way)
  );

endmodule