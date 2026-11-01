// data_array : Stores full 128-bit cache lines and extracts requested bytes
module data_array #(
  parameter int CL   = 256,
  parameter int NW   = 4,
  parameter int M_DW = 128,
  parameter int C_DW = 8
)(
  input  logic              clk_i,
  input  logic [$clog2(CL/NW)-1:0] index_i,

  input  logic              fill_i,
  input  logic [$clog2(NW)-1:0] fill_way_i,
  input  logic [M_DW-1:0]   fill_data_i,

  input  logic [$clog2(NW)-1:0] hit_way_i,
  input  logic [$clog2(M_DW/8)-1:0] c_offset_i,
  input  logic [M_DW-1:0]   m_data_i,
  input  logic              bypass_i,

  output logic [C_DW-1:0]   c_data_o
);

  localparam int NUM_SETS = CL / NW;
  logic [NUM_SETS-1:0][NW-1:0][M_DW-1:0] data_mem;

  always_ff @(posedge clk_i) begin
    if (fill_i) begin
      data_mem[index_i][fill_way_i] <= fill_data_i;
    end
  end

  logic [M_DW-1:0] active_line;
  assign active_line = bypass_i ? m_data_i : data_mem[index_i][hit_way_i];

  always_comb begin
    c_data_o = active_line[c_offset_i * C_DW +: C_DW];
  end

endmodule