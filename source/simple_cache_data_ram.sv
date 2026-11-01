// -----------------------------------------------------------------------------
// simple_cache_data_ram : cache line storage.
//
//  - One M_DW-bit line per (set, way). Combinational read, line-wide write.
//  - No reset: contents are only used after the valid bit is set.
//  - Replace the array with an SRAM/BRAM wrapper here (adds a read cycle).
// -----------------------------------------------------------------------------
module simple_cache_data_ram #(
  parameter int NS   = 64,
  parameter int NW   = 4,
  parameter int M_DW = 128,
  localparam int IDX_WD = (NS > 1) ? $clog2(NS) : 1,
  localparam int WAY_WD = (NW > 1) ? $clog2(NW) : 1
) (
  input  logic              clk_i,

  // read
  input  logic [IDX_WD-1:0] rd_index_i,
  input  logic [WAY_WD-1:0] rd_way_i,
  output logic [M_DW-1:0]   rd_line_o,

  // write (line fill)
  input  logic              wr_en_i,
  input  logic [IDX_WD-1:0] wr_index_i,
  input  logic [WAY_WD-1:0] wr_way_i,
  input  logic [M_DW-1:0]   wr_line_i
);

  logic [M_DW-1:0] data_q [NS][NW];

  assign rd_line_o = data_q[rd_index_i][rd_way_i];

  always_ff @(posedge clk_i) begin
    if (wr_en_i) data_q[wr_index_i][wr_way_i] <= wr_line_i;
  end

endmodule
