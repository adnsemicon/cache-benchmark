module simple_cache #(
  parameter int AW   = 16,
  parameter int C_DW = 8,
  parameter int M_DW = 128,
  parameter int CL   = 256,
  parameter int NW   = 4
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

  localparam int SETS = CL / NW;
  localparam int LINE_WORDS = M_DW / C_DW;
  localparam int OFFSET_W = (LINE_WORDS <= 1) ? 0 : $clog2(LINE_WORDS);
  localparam int SET_W = (SETS <= 1) ? 0 : $clog2(SETS);

  cache_controller #(
    .AW(AW),
    .C_DW(C_DW),
    .M_DW(M_DW),
    .CL(CL),
    .NW(NW)
  ) u_cache_controller (
    .clk_i(clk_i),
    .arst_ni(arst_ni),
    .c_addr_i(c_addr_i),
    .c_req_i(c_req_i),
    .c_data_o(c_data_o),
    .c_gnt_o(c_gnt_o),
    .m_addr_o(m_addr_o),
    .m_req_o(m_req_o),
    .m_data_i(m_data_i),
    .m_gnt_i(m_gnt_i)
  );

endmodule