// Line storage. Whole line written on refill, one C_DW word selected on read.
module cache_data_array #(
    parameter C_DW = 8,
    parameter M_DW = 128,
    parameter CL   = 256,
    parameter NW   = 4,
    parameter NUM_SETS = CL / NW,
    parameter SET_W    = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter WAY_W    = (NW > 1) ? $clog2(NW) : 1,
    parameter WORDS    = M_DW / C_DW,
    parameter WORD_W   = (WORDS > 1) ? $clog2(WORDS) : 1
) (
    input  wire             clk_i,
    input  wire             arst_ni,
    input  wire [SET_W-1:0] read_set_i,
    input  wire [WAY_W-1:0] read_way_i,
    input  wire [WORD_W-1:0] word_offset_i,
    output reg  [C_DW-1:0]  read_data_o,
    input  wire             refill_valid_i,
    input  wire [SET_W-1:0] refill_set_i,
    input  wire [WAY_W-1:0] refill_way_i,
    input  wire [M_DW-1:0] refill_data_i
);

    reg [M_DW-1:0] line_q [0:NUM_SETS-1][0:NW-1];
    reg [M_DW-1:0] sel_line;

    always @(posedge clk_i) begin
        if (refill_valid_i && refill_set_i < NUM_SETS && refill_way_i < NW)
            line_q[refill_set_i][refill_way_i] <= refill_data_i;
    end

    always @* begin
        sel_line    = {M_DW{1'b0}};
        read_data_o = {C_DW{1'b0}};
        if (read_set_i < NUM_SETS && read_way_i < NW)
            sel_line = line_q[read_set_i][read_way_i];
        if (word_offset_i < WORDS)
            read_data_o = sel_line[word_offset_i * C_DW +: C_DW];
    end

    wire unused_ok = &{1'b0, arst_ni};

endmodule