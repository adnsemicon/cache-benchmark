module lru_pinning_unit #(
    parameter int SETS = 128,
    parameter int REPL = 2      // 2-bit RRPV (0..3)
)(
    input  logic              clk_i,
    input  logic              arst_ni,
    input  logic [6:0]        set_idx_i,
    input  logic              hit_i,
    input  logic [1:0]        hit_way_i,
    input  logic              refill_i,
    output logic [1:0]        victim_way_o,
    output logic [1:0]        update_way_o,
    output logic [REPL-1:0]   update_rrpv_o
);

    // 2-bit RRPV per way for each set
    logic [REPL-1:0] rrpv_mem [SETS-1:0][3:0];
    // 10-bit PSEL counter for Set Sampling (Dedicated SRRIP vs BRRIP sets)
    logic [9:0] psel_q;
    // Pseudo-random bit generator for BRRIP insertion (1/32 probability for RRPV=2)
    logic [4:0] lfsr_q;

    // LFSR for Bimodal random insertion
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni)
            lfsr_q <= 5'h1F;
        else
            lfsr_q <= {lfsr_q[3:0], lfsr_q[4] ^ lfsr_q[2]};
    end

    // Find victim way (first way with RRPV == 3, else age up)
    logic [1:0] victim_way_comb;
    logic       found_victim;

    always_comb begin
        found_victim    = 1'b0;
        victim_way_comb = 2'b00;

        for (int w = 0; w < 4; w++) begin
            if (!found_victim && rrpv_mem[set_idx_i][w] == 2'b11) begin
                victim_way_comb = w[1:0];
                found_victim    = 1'b1;
            end
        end
        if (!found_victim) begin
            victim_way_comb = 2'b00; // Fallback way
        end
    end

    assign victim_way_o = victim_way_comb;

    // RRPV Update & Policy Selection logic
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            psel_q <= 10'd512; // Midpoint
            for (int s = 0; s < SETS; s++) begin
                for (int w = 0; w < 4; w++) begin
                    rrpv_mem[s][w] <= 2'b11; // Distant initial state
                end
            end
        end else begin
            if (hit_i) begin
                // Hit: Set RRPV to 0 (Near-Immediate re-reference)
                rrpv_mem[set_idx_i][hit_way_i] <= 2'b00;
            end else if (refill_i) begin
                // Age up other ways in set if victim wasn't at max RRPV
                if (rrpv_mem[set_idx_i][victim_way_comb] != 2'b11) begin
                    for (int w = 0; w < 4; w++) begin
                        if (rrpv_mem[set_idx_i][w] != 2'b11)
                            rrpv_mem[set_idx_i][w] <= rrpv_mem[set_idx_i][w] + 1'b1;
                    end
                end

                // DRRIP Insertion Policy Selection based on PSEL & LFSR
                if (set_idx_i[5:0] == 6'd0) begin
                    // SRRIP Dedicated Set: Always insert with RRPV = 2
                    rrpv_mem[set_idx_i][victim_way_comb] <= 2'b10;
                    if (psel_q > 0) psel_q <= psel_q - 1'b1;
                end else if (set_idx_i[5:0] == 6'd63) begin
                    // BRRIP Dedicated Set: Mostly insert RRPV = 3, rarely RRPV = 2
                    rrpv_mem[set_idx_i][victim_way_comb] <= (lfsr_q == 5'd0) ? 2'b10 : 2'b11;
                    if (psel_q < 10'd1023) psel_q <= psel_q + 1'b1;
                end else begin
                    // Follower Sets: Follow PSEL decision
                    if (psel_q >= 10'd512) begin
                        // Follow BRRIP
                        rrpv_mem[set_idx_i][victim_way_comb] <= (lfsr_q == 5'd0) ? 2'b10 : 2'b11;
                    end else begin
                        // Follow SRRIP
                        rrpv_mem[set_idx_i][victim_way_comb] <= 2'b10;
                    end
                end
            end
        end
    end

    assign update_way_o  = hit_i ? hit_way_i : victim_way_comb;
    assign update_rrpv_o = rrpv_mem[set_idx_i][update_way_o];

endmodule
