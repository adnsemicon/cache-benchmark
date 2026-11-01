// Splits a byte address into tag / set index / byte offset / word offset and
// produces the line-aligned memory address.
//   m_addr = c_addr & ~(LINE_BYTES-1)
// Works for any NW (1 = direct mapped .. CL = fully associative) and any
// CL/NW (power-of-two sets use pure bit slicing; other counts use a modulo
// index with the full line address as tag).
module cache_address_decoder #(
    parameter int AW   = 16,
    parameter int C_DW = 8,
    parameter int M_DW = 128,
    parameter int CL   = 256,
    parameter int NW   = 4,
    localparam int NUM_SETS          = CL / NW,
    localparam int LINE_BYTES        = M_DW / 8,
    localparam int CPU_BYTES         = C_DW / 8,
    localparam int WORDS_PER_LINE    = M_DW / C_DW,
    localparam int BYTE_OFFSET_WIDTH = $clog2(LINE_BYTES),
    localparam int CPU_BYTE_OFF_W    = $clog2(CPU_BYTES),
    localparam int INDEX_WIDTH       = $clog2(NUM_SETS),
    localparam bit SETS_POW2         = (NUM_SETS & (NUM_SETS - 1)) == 0,
    localparam int RAW_TAG_W         = SETS_POW2 ? AW - BYTE_OFFSET_WIDTH - INDEX_WIDTH
                                                 : AW - BYTE_OFFSET_WIDTH,
    localparam int TAG_WIDTH         = (RAW_TAG_W > 0) ? RAW_TAG_W : 1,
    localparam int SET_WIDTH         = (INDEX_WIDTH > 0) ? INDEX_WIDTH : 1,
    localparam int OFFSET_WIDTH      = (BYTE_OFFSET_WIDTH > 0) ? BYTE_OFFSET_WIDTH : 1,
    localparam int WORD_WIDTH        = (WORDS_PER_LINE > 1) ? $clog2(WORDS_PER_LINE) : 1
) (
    input  logic [AW-1:0]           c_addr_i,
    output logic [TAG_WIDTH-1:0]    tag_o,
    output logic [SET_WIDTH-1:0]    index_o,
    output logic [OFFSET_WIDTH-1:0] line_offset_o,
    output logic [WORD_WIDTH-1:0]   word_offset_o,
    output logic [AW-1:0]           m_addr_o
);

    logic [AW-1:0] line_addr;
    assign line_addr = c_addr_i >> BYTE_OFFSET_WIDTH;

    if (NUM_SETS == 1) begin : g_one_set
        assign index_o = '0;
        assign tag_o   = TAG_WIDTH'(line_addr);
    end else if (SETS_POW2) begin : g_pow2_sets
        assign index_o = SET_WIDTH'(line_addr);
        assign tag_o   = TAG_WIDTH'(line_addr >> INDEX_WIDTH);
    end else begin : g_generic_sets
        assign index_o = SET_WIDTH'(line_addr % NUM_SETS);
        assign tag_o   = TAG_WIDTH'(line_addr);
    end

    assign line_offset_o = (BYTE_OFFSET_WIDTH > 0) ? OFFSET_WIDTH'(c_addr_i) : '0;
    assign word_offset_o = (WORDS_PER_LINE > 1) ? WORD_WIDTH'(c_addr_i >> CPU_BYTE_OFF_W) : '0;
    assign m_addr_o      = c_addr_i & ({AW{1'b1}} << BYTE_OFFSET_WIDTH);

endmodule
