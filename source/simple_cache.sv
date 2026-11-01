// -----------------------------------------------------------------------------
// simple_cache : parameterizable, read-only, set-associative cache (true LRU)
//
//   | tag | set index | byte offset |      (MSB -> LSB of the byte address)
//
//   c_addr_i -> decode -> tag_ram (compare) -> hit / hit_way
//                      -> data_ram (read)   -> word select -> c_data_o
//   ctrl FSM handles misses (refill), lru picks the victim way.
//   All of AW, C_DW, M_DW, CL, NW must be powers of two.
// -----------------------------------------------------------------------------
module simple_cache
  import simple_cache_pkg::*;
#(
  parameter int AW   = 16,   // address width (bits)
  parameter int C_DW = 8,    // cache-side data width (bits)
  parameter int M_DW = 128,  // memory-side data width = cache line size (bits)
  parameter int CL   = 256,  // total number of cache lines
  parameter int NW   = 4     // number of ways
) (
  input  logic            arst_ni,
  input  logic            clk_i,

  // Cache (requester) side
  input  logic [AW-1:0]   c_addr_i,
  input  logic            c_req_i,
  output logic [C_DW-1:0] c_data_o,
  output logic            c_gnt_o,

  // Memory (downstream) side
  output logic [AW-1:0]   m_addr_o,
  output logic            m_req_o,
  input  logic [M_DW-1:0] m_data_i,
  input  logic            m_gnt_i
);

  // ---------------------------------------------------------------------------
  // Parameter check and derived values
  // ---------------------------------------------------------------------------
  if (!params_legal(AW, C_DW, M_DW, CL, NW)) begin : g_param_check
    $fatal(1, "simple_cache: illegal parameter combination");
  end

  localparam int NS       = CL / NW;
  localparam int OFFSET_W = $clog2(M_DW / 8);
  localparam int IDX_W    = $clog2(NS);
  localparam int TAG_W    = AW - IDX_W - OFFSET_W;
  localparam int BYTE_W   = $clog2(C_DW / 8);
  localparam int IDX_WD   = clog2_min1(NS);
  localparam int WAY_WD   = clog2_min1(NW);

  // ---------------------------------------------------------------------------
  // Address decode (request and fill)
  // ---------------------------------------------------------------------------
  logic [OFFSET_W-1:0] c_offset;
  logic [IDX_WD-1:0]   c_index;
  logic [TAG_W-1:0]    c_tag;

  logic [AW-1:0]       fill_addr;
  logic [IDX_WD-1:0]   f_index;
  logic [TAG_W-1:0]    f_tag;

  assign c_offset = c_addr_i[OFFSET_W-1:0];
  assign c_tag    = c_addr_i[AW-1 -: TAG_W];
  assign f_tag    = fill_addr[AW-1 -: TAG_W];

  if (IDX_W > 0) begin : g_idx
    assign c_index = c_addr_i[OFFSET_W +: IDX_W];
    assign f_index = fill_addr[OFFSET_W +: IDX_W];
  end else begin : g_noidx
    assign c_index = '0;
    assign f_index = '0;
  end

  // ---------------------------------------------------------------------------
  // Internal wiring
  // ---------------------------------------------------------------------------
  logic              hit;
  logic [WAY_WD-1:0] hit_way;
  logic [NW-1:0]     valid_set;
  logic [WAY_WD-1:0] victim;
  logic              lru_upd;
  logic              fill_en;
  logic [WAY_WD-1:0] fill_way;
  logic [M_DW-1:0]   rd_line;

  // ---------------------------------------------------------------------------
  // Sub-blocks
  // ---------------------------------------------------------------------------
  simple_cache_tag_ram #(.NS(NS), .NW(NW), .TAG_W(TAG_W)) u_tag_ram (
    .clk_i, .arst_ni,
    .index_i    (c_index),
    .tag_i      (c_tag),
    .hit_o      (hit),
    .hit_way_o  (hit_way),
    .valid_o    (valid_set),
    .wr_en_i    (fill_en),
    .wr_index_i (f_index),
    .wr_way_i   (fill_way),
    .wr_tag_i   (f_tag)
  );

  simple_cache_data_ram #(.NS(NS), .NW(NW), .M_DW(M_DW)) u_data_ram (
    .clk_i,
    .rd_index_i (c_index),
    .rd_way_i   (hit_way),
    .rd_line_o  (rd_line),
    .wr_en_i    (fill_en),
    .wr_index_i (f_index),
    .wr_way_i   (fill_way),
    .wr_line_i  (m_data_i)
  );

  simple_cache_lru #(.NS(NS), .NW(NW)) u_lru (
    .clk_i, .arst_ni,
    .index_i  (c_index),
    .valid_i  (valid_set),
    .upd_i    (lru_upd),
    .way_i    (hit_way),
    .victim_o (victim)
  );

  simple_cache_ctrl #(.AW(AW), .OFFSET_W(OFFSET_W), .NW(NW)) u_ctrl (
    .clk_i, .arst_ni,
    .c_addr_i,
    .c_req_i,
    .hit_i       (hit),
    .c_gnt_o,
    .victim_i    (victim),
    .lru_upd_o   (lru_upd),
    .fill_en_o   (fill_en),
    .fill_way_o  (fill_way),
    .fill_addr_o (fill_addr),
    .m_addr_o,
    .m_req_o,
    .m_gnt_i
  );

  // ---------------------------------------------------------------------------
  // Word select within the hit line
  // ---------------------------------------------------------------------------
  logic [M_DW-1:0] sel_shifted;

  assign sel_shifted = rd_line >> ((c_offset >> BYTE_W) * C_DW);
  assign c_data_o    = c_gnt_o ? sel_shifted[C_DW-1:0] : '0;

endmodule