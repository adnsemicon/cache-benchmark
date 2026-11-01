// Small hashed frequency table (TinyLFU-style "sketch", single row).
// Counts how often each line address has been *requested* (hit or miss, even
// if the line was never stored), with 4-bit saturating counters. Every
// AGE_MULT*ENTRIES increments all counters are halved so old popularity decays.
module freq_sketch #(
    parameter int LINE_W   = 12,
    parameter int IDX_W    = 11,        // ENTRIES = 2**IDX_W
    parameter int CW       = 4,
    parameter int AGE_MULT = 2
) (
    input  logic              clk_i,
    input  logic              arst_ni,
    input  logic              inc_en_i,
    input  logic [LINE_W-1:0] inc_line_i,
    input  logic [LINE_W-1:0] rd_a_line_i,
    output logic [CW-1:0]     rd_a_cnt_o,
    input  logic [LINE_W-1:0] rd_b_line_i,
    output logic [CW-1:0]     rd_b_cnt_o
);

    localparam int ENTRIES = 1 << IDX_W;
    localparam int LIMIT   = AGE_MULT * ENTRIES;
    localparam logic [CW-1:0] CMAX = {CW{1'b1}};

    function automatic logic [IDX_W-1:0] hash_f(input logic [LINE_W-1:0] x);
        logic [31:0] m;
        m = 32'(x) * 32'h9E3779B1;
        return m[31 -: IDX_W];
    endfunction

    logic [CW-1:0]  cnt_q [0:ENTRIES-1];
    logic [$clog2(LIMIT+1)-1:0] adds_q;
    logic           age_now;

    assign age_now = inc_en_i && (adds_q == LIMIT - 1);

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)         adds_q <= '0;
        else if (age_now)     adds_q <= '0;
        else if (inc_en_i)    adds_q <= adds_q + 1'b1;
    end

    for (genvar e = 0; e < ENTRIES; e++) begin : g_entry
        always_ff @(posedge clk_i or negedge arst_ni) begin
            if (!arst_ni)                                              cnt_q[e] <= '0;
            else if (age_now)                                          cnt_q[e] <= cnt_q[e] >> 1;
            else if (inc_en_i && hash_f(inc_line_i) == IDX_W'(e) && cnt_q[e] != CMAX)
                                                                       cnt_q[e] <= cnt_q[e] + 1'b1;
        end
    end

    assign rd_a_cnt_o = cnt_q[hash_f(rd_a_line_i)];
    assign rd_b_cnt_o = cnt_q[hash_f(rd_b_line_i)];

endmodule