// -----------------------------------------------------------------------------
// simple_cache : parameterizable, read-only, set-associative cache
//
//   Byte addresses map to line number, set (line number modulo NS), and tag.
//   This supports non-power-of-two line sizes and set counts.
//
//   c_addr_i -> decode -> tag_ram (compare) -> hit / hit_way
//                      -> data_ram (read)   -> word select -> c_data_o
//   ctrl FSM handles misses (refill), the selected policy picks the victim way.
//   Widths are byte multiples; the line width must be a multiple of C_DW,
//   and CL must be divisible by NW.
// -----------------------------------------------------------------------------
module simple_cache #(
  parameter int AW   = 16,   // address width (bits)
  parameter int C_DW = 8,    // cache-side data width (bits)
  parameter int M_DW = 128,  // memory-side data width = cache line size (bits)
  parameter int CL   = 256,  // total number of cache lines
  parameter int NW   = 4,    // number of ways
  parameter int REPLACEMENT_POLICY = 1 // 0: LRU, 1: tree PLRU
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

  function automatic int unsigned clog2_min1(input int unsigned n);
    int unsigned c;
    c = $clog2(n);
    return (c < 1) ? 1 : c;
  endfunction

  function automatic bit params_legal(input int aw, input int c_dw, input int m_dw,
                                      input int cl, input int nw);
    if (aw < 1 || c_dw < 8 || m_dw < 8 || cl < 1 || nw < 1) return 1'b0;
    if ((c_dw % 8) != 0 || (m_dw % 8) != 0) return 1'b0;
    if ((m_dw < c_dw) || ((m_dw % c_dw) != 0)) return 1'b0;
    if ((cl < nw) || ((cl % nw) != 0)) return 1'b0;
    return 1'b1;
  endfunction

  // ---------------------------------------------------------------------------
  // Parameter check and derived values
  // ---------------------------------------------------------------------------
  if (!params_legal(AW, C_DW, M_DW, CL, NW)) begin : g_param_check
    $fatal(1, "simple_cache: illegal parameter combination");
  end

  localparam int NS       = CL / NW;
  localparam int LINE_BYTES = M_DW / 8;
  localparam int C_BYTES    = C_DW / 8;
  localparam int OFFSET_W   = clog2_min1(LINE_BYTES);
  localparam int TAG_W      = AW;
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

  assign c_offset = c_addr_i % LINE_BYTES;
  assign c_index  = (c_addr_i / LINE_BYTES) % NS;
  assign c_tag    = (c_addr_i / LINE_BYTES) / NS;
  assign f_index  = (fill_addr / LINE_BYTES) % NS;
  assign f_tag    = (fill_addr / LINE_BYTES) / NS;

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

  if (REPLACEMENT_POLICY == 0) begin : g_lru
    simple_cache_lru #(.NS(NS), .NW(NW)) u_replacement (
      .clk_i, .arst_ni,
      .index_i  (c_index),
      .valid_i  (valid_set),
      .upd_i    (lru_upd),
      .way_i    (hit_way),
      .victim_o (victim)
    );
  end else if (REPLACEMENT_POLICY == 1) begin : g_plru
    simple_cache_plru #(.NS(NS), .NW(NW)) u_replacement (
      .clk_i, .arst_ni,
      .index_i  (c_index),
      .valid_i  (valid_set),
      .upd_i    (lru_upd),
      .way_i    (hit_way),
      .victim_o (victim)
    );
  end else begin : g_bad_policy
    initial $fatal(1, "simple_cache: REPLACEMENT_POLICY must be 0 (LRU) or 1 (PLRU)");
    assign victim = '0;
  end

  simple_cache_ctrl #(.AW(AW), .LINE_BYTES(LINE_BYTES), .NW(NW)) u_ctrl (
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

  assign sel_shifted = rd_line >> ((c_offset / C_BYTES) * C_DW);
  assign c_data_o    = c_gnt_o ? sel_shifted[C_DW-1:0] : '0;

endmodule
