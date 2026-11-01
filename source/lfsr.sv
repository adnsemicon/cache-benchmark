// Fibonacci LFSR (left shift). WIDTH=8 uses taps 8,6,5,4 -> maximal length (255).
module lfsr #(
    parameter int LFSR_WIDTH = 8,
    parameter logic [LFSR_WIDTH-1:0] SEED = {LFSR_WIDTH{1'b1}}
) (
    input  logic                  clk_i,
    input  logic                  arst_ni,
    input  logic                  advance_i,
    output logic [LFSR_WIDTH-1:0] lfsr_o
);

    localparam logic [LFSR_WIDTH-1:0] SAFE_SEED =
        (SEED == '0) ? LFSR_WIDTH'(1) : SEED;

    logic [LFSR_WIDTH-1:0] lfsr_q;
    logic                  feedback;

    if (LFSR_WIDTH >= 5) begin : g_taps_wide
        assign feedback = lfsr_q[LFSR_WIDTH-1] ^ lfsr_q[LFSR_WIDTH-3] ^
                          lfsr_q[LFSR_WIDTH-4] ^ lfsr_q[LFSR_WIDTH-5];
    end else if (LFSR_WIDTH > 1) begin : g_taps_narrow
        assign feedback = lfsr_q[LFSR_WIDTH-1] ^ lfsr_q[0];
    end else begin : g_taps_one
        assign feedback = ~lfsr_q[0];
    end

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            lfsr_q <= SAFE_SEED;
        end else if (advance_i) begin
            if (LFSR_WIDTH == 1) lfsr_q <= feedback;
            else                 lfsr_q <= {lfsr_q[(LFSR_WIDTH > 1 ? LFSR_WIDTH-2 : 0):0], feedback};
        end
    end

    assign lfsr_o = lfsr_q;

endmodule
