// Splits a byte address into tag / set index / byte offset / word offset and
// produces the line-aligned memory address.
//   m_addr = c_addr & ~(LINE_BYTES-1)
// Works for any NW (1 = direct mapped .. CL = fully associative) and any
// CL/NW (power-of-two sets use pure bit slicing; other counts use a modulo
// index with the full line address as tag).
module cache_address_decoder #(
    parameter AW   = 16,
    parameter C_DW = 8,
    parameter M_DW = 128,
    parameter CL   = 256,
    parameter NW   = 4,
    parameter NUM_SETS          = CL / NW,
    parameter LINE_BYTES        = M_DW / 8,
    parameter CPU_BYTES         = C_DW / 8,
    parameter WORDS_PER_LINE    = M_DW / C_DW,
    parameter BYTE_OFFSET_WIDTH = $clog2(LINE_BYTES),
    parameter CPU_BYTE_OFF_W    = $clog2(CPU_BYTES),
    parameter INDEX_WIDTH       = $clog2(NUM_SETS),
    parameter SETS_POW2         = (NUM_SETS & (NUM_SETS - 1)) == 0,
    parameter RAW_TAG_W         = SETS_POW2 ? AW - BYTE_OFFSET_WIDTH - INDEX_WIDTH : AW - BYTE_OFFSET_WIDTH,
    parameter TAG_WIDTH         = (RAW_TAG_W > 0) ? RAW_TAG_W : 1,
    parameter SET_WIDTH         = (INDEX_WIDTH > 0) ? INDEX_WIDTH : 1,
    parameter OFFSET_WIDTH      = (BYTE_OFFSET_WIDTH > 0) ? BYTE_OFFSET_WIDTH : 1,
    parameter WORD_WIDTH        = (WORDS_PER_LINE > 1) ? $clog2(WORDS_PER_LINE) : 1
) (
    input  wire [AW-1:0]           c_addr_i,
    output reg  [TAG_WIDTH-1:0]    tag_o,
    output reg  [SET_WIDTH-1:0]    index_o,
    output reg  [OFFSET_WIDTH-1:0] line_offset_o,
    output reg  [WORD_WIDTH-1:0]   word_offset_o,
    output wire [AW-1:0]           m_addr_o
);

    reg [AW-1:0] line_addr;

    always @* begin
        line_addr = c_addr_i >> BYTE_OFFSET_WIDTH;

        if (NUM_SETS == 1) begin
            index_o = {SET_WIDTH{1'b0}};
            tag_o   = line_addr;
        end else if (SETS_POW2) begin
            index_o = line_addr[SET_WIDTH-1:0];
            tag_o   = line_addr >> INDEX_WIDTH;
        end else begin
            index_o = line_addr % NUM_SETS;
            tag_o   = line_addr;
        end

        if (BYTE_OFFSET_WIDTH > 0)
            line_offset_o = c_addr_i[OFFSET_WIDTH-1:0];
        else
            line_offset_o = {OFFSET_WIDTH{1'b0}};

        if (WORDS_PER_LINE > 1)
            word_offset_o = c_addr_i >> CPU_BYTE_OFF_W;
        else
            word_offset_o = {WORD_WIDTH{1'b0}};
    end

    assign m_addr_o = c_addr_i & ({AW{1'b1}} << BYTE_OFFSET_WIDTH);

endmodule