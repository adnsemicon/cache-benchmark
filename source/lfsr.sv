// Fibonacci LFSR (left shift). WIDTH=8 uses taps 8,6,5,4 -> maximal length (255).
module lfsr #(
    parameter LFSR_WIDTH = 8,
    parameter [LFSR_WIDTH-1:0] SEED = {LFSR_WIDTH{1'b1}}
) (
    input  wire                  clk_i,
    input  wire                  arst_ni,
    input  wire                  advance_i,
    output reg  [LFSR_WIDTH-1:0] lfsr_o
);

    localparam [LFSR_WIDTH-1:0] SAFE_SEED = (SEED == {LFSR_WIDTH{1'b0}}) ? 1 : SEED;

    reg [LFSR_WIDTH-1:0] lfsr_q;
    reg                 feedback;

    always @* begin
        if (LFSR_WIDTH >= 5)
            feedback = lfsr_q[LFSR_WIDTH-1] ^ lfsr_q[LFSR_WIDTH-3] ^
                       lfsr_q[LFSR_WIDTH-4] ^ lfsr_q[LFSR_WIDTH-5];
        else if (LFSR_WIDTH > 1)
            feedback = lfsr_q[LFSR_WIDTH-1] ^ lfsr_q[0];
        else
            feedback = ~lfsr_q[0];
    end

    always @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            lfsr_q <= SAFE_SEED;
        end else if (advance_i) begin
            if (LFSR_WIDTH == 1)
                lfsr_q <= feedback;
            else
                lfsr_q <= {lfsr_q[LFSR_WIDTH-2:0], feedback};
        end
    end

    assign lfsr_o = lfsr_q;

endmodule