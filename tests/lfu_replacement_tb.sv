module lfu_replacement_tb;
    reg clk_i = 1'b0;
    reg arst_ni = 1'b0;
    reg [1:0] set_index_i = 2'd0;
    reg [1:0] hit_way_i = 2'd0;
    reg hit_i = 1'b0;
    reg refill_valid_i = 1'b0;
    reg [1:0] refill_way_i = 2'd0;
    reg [2:0] valid_mask_i = 3'b000;
    wire [2:0] candidate_mask_o;

    lfu_replacement #(
        .COUNTER_WIDTH(2),
        .NUM_SETS(3),
        .NW(3)
    ) dut (
        .clk_i(clk_i),
        .arst_ni(arst_ni),
        .set_index_i(set_index_i),
        .hit_way_i(hit_way_i),
        .hit_i(hit_i),
        .refill_valid_i(refill_valid_i),
        .refill_way_i(refill_way_i),
        .valid_mask_i(valid_mask_i),
        .candidate_mask_o(candidate_mask_o)
    );

    always #5 clk_i = ~clk_i;

    task tick;
        begin
            @(posedge clk_i);
            #1;
        end
    endtask

    task expect_candidates(input [2:0] expected, input [255:0] label);
        begin
            #1;
            if (candidate_mask_o !== expected) begin
                $display("FAIL %0s: expected %b, got %b", label, expected, candidate_mask_o);
                $fatal(1);
            end
        end
    endtask

    initial begin
        #2;
        arst_ni = 1'b1;

        valid_mask_i = 3'b001;
        refill_valid_i = 1'b1;
        refill_way_i = 2'd0;
        tick();

        valid_mask_i = 3'b011;
        refill_way_i = 2'd1;
        tick();
        refill_valid_i = 1'b0;
        expect_candidates(3'b011, "equal refill counters are tied");

        hit_i = 1'b1;
        hit_way_i = 2'd0;
        tick();
        expect_candidates(3'b010, "least-used valid way selected after hit");
        tick();
        tick();
        hit_i = 1'b0;

        hit_way_i = 2'd1;
        hit_i = 1'b1;
        tick();
        tick();
        hit_i = 1'b0;
        expect_candidates(3'b011, "saturation ages other ways");

        set_index_i = 2'd1;
        valid_mask_i = 3'b001;
        refill_valid_i = 1'b1;
        refill_way_i = 2'd0;
        tick();
        refill_valid_i = 1'b0;
        expect_candidates(3'b001, "set state is independent");

        set_index_i = 2'd0;
        valid_mask_i = 3'b011;
        expect_candidates(3'b011, "switching sets preserves prior counters");

        refill_valid_i = 1'b1;
        refill_way_i = 2'd0;
        tick();
        refill_valid_i = 1'b0;
        expect_candidates(3'b001, "refill resets the selected way counter");

        set_index_i = 2'd3;
        expect_candidates(3'b000, "out-of-range set returns no candidates");

        set_index_i = 2'd0;
        hit_i = 1'b1;
        hit_way_i = 2'd3;
        refill_valid_i = 1'b1;
        refill_way_i = 2'd3;
        tick();
        hit_i = 1'b0;
        refill_valid_i = 1'b0;
        expect_candidates(3'b001, "out-of-range ways do not alter counters");

        arst_ni = 1'b0;
        valid_mask_i = 3'b011;
        expect_candidates(3'b011, "asynchronous reset clears every set");

        $display("PASS lfu_replacement_tb");
        $finish;
    end
endmodule
