// Parameterizable read-only set-associative cache (top level).
module simple_cache #(
    parameter AW   = 16,   // address width (bits)
    parameter C_DW = 8,    // CPU-side data width (bits)
    parameter M_DW = 128,  // memory line width (bits)
    parameter CL   = 256,  // total cache lines
    parameter NW   = 4     // ways per set
) (
    input  wire            clk_i,
    input  wire            arst_ni,
    input  wire            c_req_i,
    input  wire [AW-1:0]   c_addr_i,
    output wire            c_gnt_o,
    output wire [C_DW-1:0] c_data_o,
    output wire [AW-1:0]   m_addr_o,
    output wire            m_req_o,
    input  wire [M_DW-1:0] m_data_i,
    input  wire            m_gnt_i
);

    cache_controller #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) controller (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .c_req_i(c_req_i), .c_addr_i(c_addr_i), .c_gnt_o(c_gnt_o), .c_data_o(c_data_o),
        .m_addr_o(m_addr_o), .m_req_o(m_req_o), .m_data_i(m_data_i), .m_gnt_i(m_gnt_i)
    );

endmodule