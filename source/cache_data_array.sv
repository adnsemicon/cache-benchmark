// Line storage. Whole line written on refill, one C_DW word selected on read.
module cache_data_array #(
    parameter int C_DW = 8,
    parameter int M_DW = 128,
    parameter int CL   = 256,
    parameter int NW   = 4,
    localparam int NUM_SETS = CL / NW,
    localparam int SET_W    = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int WAY_W    = (NW > 1) ? $clog2(NW) : 1,
    localparam int WORDS    = M_DW / C_DW,
    localparam int WORD_W   = (WORDS > 1) ? $clog2(WORDS) : 1
) (
    input  logic              clk_i,
    input  logic              arst_ni,
    input  logic [SET_W-1:0]  read_set_i,
    input  logic [WAY_W-1:0]  read_way_i,
    input  logic [WORD_W-1:0] word_offset_i,
    output logic [C_DW-1:0]   read_data_o,
    input  logic              refill_valid_i,
    input  logic [SET_W-1:0]  refill_set_i,
    input  logic [WAY_W-1:0]  refill_way_i,
    input  logic [M_DW-1:0]   refill_data_i
);

    logic [M_DW-1:0] line_q [0:NUM_SETS-1][0:NW-1];
    logic [M_DW-1:0] sel_line;

    always_ff @(posedge clk_i) begin
        if (refill_valid_i && refill_set_i < NUM_SETS && refill_way_i < NW)
            line_q[refill_set_i][refill_way_i] <= refill_data_i;
    end

    always_comb begin
        sel_line    = '0;
        read_data_o = '0;
        if (read_set_i < NUM_SETS && read_way_i < NW) sel_line = line_q[read_set_i][read_way_i];
        if (word_offset_i < WORDS) read_data_o = sel_line[word_offset_i * C_DW +: C_DW];
    end

    wire unused_ok = &{1'b0, arst_ni};

endmodule
