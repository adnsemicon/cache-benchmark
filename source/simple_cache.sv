// simple_cache : top level. Address decode + wiring + word select.
module simple_cache #(
  parameter int AW   = 16,
  parameter int C_DW = 8,
  parameter int M_DW = 128,
  parameter int CL   = 256,
  parameter int NW   = 4
) (
  input  logic              arst_ni,
  input  logic              clk_i,

  input  logic [AW-1:0]     c_addr_i,
  input  logic              c_req_i,
  output logic [C_DW-1:0]   c_data_o,
  output logic              c_gnt_o,

  output logic [AW-1:0]     m_addr_o,
  output logic              m_req_o,
  input  logic [M_DW-1:0]   m_data_i,
  input  logic              m_gnt_i
);

  localparam int OFF    = $clog2(M_DW / 8);
  localparam int CB     = C_DW / 8;
  localparam int COFF   = (CB > 1) ? $clog2(CB) : 0;
  localparam int WORDS  = M_DW / C_DW;
  localparam int WSELW  = (WORDS > 1) ? $clog2(WORDS) : 1;
  localparam int SETS   = CL / NW;
  localparam int IDX    = (SETS > 1) ? $clog2(SETS) : 0;
  localparam int IDXW   = (IDX > 0) ? IDX : 1;
  localparam int TAGW   = AW - OFF - IDX;
  localparam int WAYW   = (NW > 1) ? $clog2(NW) : 1;

  logic [IDXW-1:0]  set;
  logic [TAGW-1:0]  tag;
  logic [WSELW-1:0] wsel;

  assign tag = c_addr_i[AW-1 -: TAGW];
  if (IDX > 0) begin : g_idx
    assign set = c_addr_i[OFF +: IDXW];
  end else begin : g_noidx
    assign set = '0;
  end
  if (WORDS > 1) begin : g_wsel
    assign wsel = c_addr_i[COFF +: WSELW];
  end else begin : g_nowsel
    assign wsel = '0;
  end

  logic            hit, bypass, fill, touch;
  logic [WAYW-1:0] hit_way, victim, fill_way, touch_way;
  logic [NW-1:0]   valid_vec;
  logic [M_DW-1:0] rd_line, sel_line;

  tag_array #(.SETS(SETS), .NW(NW), .IDXW(IDXW), .TAGW(TAGW)) u_tag (
    .clk_i, .arst_ni,
    .set_i(set), .tag_i(tag),
    .hit_o(hit), .hit_way_o(hit_way), .valid_o(valid_vec),
    .fill_i(fill), .fill_way_i(fill_way)
  );

  data_array #(.SETS(SETS), .NW(NW), .IDXW(IDXW), .M_DW(M_DW)) u_data (
    .clk_i,
    .set_i(set), .rd_way_i(hit_way), .rd_line_o(rd_line),
    .wr_en_i(fill), .wr_way_i(fill_way), .wr_data_i(m_data_i)
  );

  lru_controller #(.SETS(SETS), .NW(NW), .IDXW(IDXW)) u_lru (
    .clk_i, .arst_ni,
    .set_i(set), .valid_i(valid_vec), .victim_o(victim),
    .touch_i(touch), .touch_way_i(touch_way)
  );

  cache_controller #(.NW(NW)) u_ctrl (
    .c_req_i, .c_gnt_o,
    .m_req_o, .m_gnt_i,
    .hit_i(hit), .hit_way_i(hit_way), .victim_i(victim),
    .bypass_o(bypass), .fill_o(fill), .fill_way_o(fill_way),
    .touch_o(touch), .touch_way_o(touch_way)
  );

  assign m_addr_o = {c_addr_i[AW-1:OFF], {OFF{1'b0}}};
  assign sel_line = bypass ? m_data_i : rd_line;
  assign c_data_o = sel_line[wsel*C_DW +: C_DW];

endmodule