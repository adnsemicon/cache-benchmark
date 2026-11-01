// Parameterizable read-only set-associative cache (top level).
module simple_cache #(
    parameter int AW   = 16,   // address width (bits)
    parameter int C_DW = 8,    // CPU-side data width (bits)
    parameter int M_DW = 128,  // memory line width (bits)
    parameter int CL   = 256,  // total cache lines
    parameter int NW   = 4     // ways per set
) (
    input  logic            clk_i,
    input  logic            arst_ni,
    input  logic            c_req_i,
    input  logic [AW-1:0]   c_addr_i,
    output logic            c_gnt_o,
    output logic [C_DW-1:0] c_data_o,
    output logic [AW-1:0]   m_addr_o,
    output logic            m_req_o,
    input  logic [M_DW-1:0] m_data_i,
    input  logic            m_gnt_i
);

    cache_controller #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) controller (
        .clk_i, .arst_ni,
        .c_req_i, .c_addr_i, .c_gnt_o, .c_data_o,
        .m_addr_o, .m_req_o, .m_data_i, .m_gnt_i
    );

endmodule
