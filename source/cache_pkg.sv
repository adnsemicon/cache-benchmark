package cache_pkg;

  parameter int AW   = 16;
  parameter int C_DW = 8;
  parameter int M_DW = 128;
  parameter int CL   = 256;
  parameter int NW   = 4;

  localparam int LINE_BYTES  = M_DW / 8;
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int SETS        = CL / NW;
  localparam int INDEX_BITS  = $clog2(SETS);
  localparam int TAG_BITS    = AW - INDEX_BITS - OFFSET_BITS;
  localparam int VC_SIZE     = 8;

  typedef logic [AW-1:0]          addr_t;
  typedef logic [TAG_BITS-1:0]    tag_t;
  typedef logic [INDEX_BITS-1:0]  index_t;
  typedef logic [OFFSET_BITS-1:0] offset_t;
  typedef logic [M_DW-1:0]        line_t;
  typedef logic [C_DW-1:0]        cpu_data_t;

  typedef struct packed {
    logic       valid;
    logic       lock;
    logic [1:0] freq;
    tag_t       tag;
    line_t      data;
  } cache_line_t;

endpackage