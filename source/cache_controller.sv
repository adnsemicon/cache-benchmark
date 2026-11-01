// Read-only set-associative cache controller.
//
// FSM (all outputs registered/state-decoded, gnt is a clean 1-cycle pulse):
//   IDLE : tag lookup directly on c_addr_i in the cycle req is seen.
//          hit  -> latch data,                        go RESP        (gnt next cycle)
//          miss -> latch addr/victim, go MEM
//   MEM  : m_req_o held until m_gnt_i; on grant the line is written into the
//          arrays in the same edge and the requested word is latched -> RESP
//   RESP : c_gnt_o = 1 for exactly one cycle, then back to IDLE
//
// Latency: hit = 1 cycle after req, miss = memory latency + 2.
// Replacement: first invalid way, otherwise LFU with LFSR random tie-break.
module cache_controller #(
    parameter AW   = 16,
    parameter C_DW = 8,
    parameter M_DW = 128,
    parameter CL   = 256,
    parameter NW   = 4
) (
    input  wire            clk_i,
    input  wire            arst_ni,
    input  wire            c_req_i,
    input  wire [AW-1:0]   c_addr_i,
    output reg             c_gnt_o,
    output reg  [C_DW-1:0] c_data_o,
    output reg  [AW-1:0]   m_addr_o,
    output reg             m_req_o,
    input  wire [M_DW-1:0] m_data_i,
    input  wire            m_gnt_i
);

    localparam NUM_SETS   = CL / NW;
    localparam LINE_BYTES = M_DW / 8;
    localparam OFF_W      = $clog2(LINE_BYTES);
    localparam IDX_W      = $clog2(NUM_SETS);
    localparam SETS_POW2  = (NUM_SETS & (NUM_SETS - 1)) == 0;
    localparam RAW_TAG_W  = SETS_POW2 ? AW - OFF_W - IDX_W : AW - OFF_W;
    localparam TAG_WIDTH  = (RAW_TAG_W > 0) ? RAW_TAG_W : 1;
    localparam SET_WIDTH  = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1;
    localparam WAY_WIDTH  = (NW > 1) ? $clog2(NW) : 1;
    localparam WORDS      = M_DW / C_DW;
    localparam WORD_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_MEM  = 2'd1;
    localparam [1:0] ST_RESP = 2'd2;

    // ------------------------------------------------------------------
    initial begin
        if (NW < 1 || CL < 1 || CL % NW != 0)
            $fatal(1, "simple_cache: CL must be a positive multiple of NW");
        if (C_DW < 8 || C_DW % 8 != 0 || M_DW % C_DW != 0)
            $fatal(1, "simple_cache: C_DW must be a byte multiple dividing M_DW");
        if ((M_DW/8 & (M_DW/8 - 1)) != 0 || (C_DW/8 & (C_DW/8 - 1)) != 0)
            $fatal(1, "simple_cache: M_DW/8 and C_DW/8 must be powers of two");
        if (AW < 1)
            $fatal(1, "simple_cache: AW must be >= 1");
    end

    // ------------------------------------------------------------------
    reg [1:0]             state_q;
    reg [AW-1:0]          req_addr_q;
    reg [AW-1:0]          mem_addr_q;
    reg [WAY_WIDTH-1:0]   victim_q;
    reg [C_DW-1:0]        resp_data_q;

    wire [AW-1:0]         lookup_addr;
    wire [TAG_WIDTH-1:0]  tag;
    wire [SET_WIDTH-1:0]  set_idx;
    wire [WORD_WIDTH-1:0] word;
    wire [AW-1:0]         aligned_addr;

    wire [NW-1:0]         valid_mask, invalid_mask;
    wire                  hit;
    wire [WAY_WIDTH-1:0]  hit_way;
    wire [C_DW-1:0]       cached_data;
    wire [NW-1:0]         lfu_candidates;

    wire [NW-1:0]         victim_candidates;
    reg [WAY_WIDTH-1:0]   random_way, selected_victim;
    wire [7:0]            random_value;
    wire                  any_invalid;
    reg                   multiple_victims;

    wire                  accept, hit_accept, miss_accept, refill_en;

    // The lookup path looks at the incoming address while idle and at the
    // latched address while a miss is being serviced.
    assign lookup_addr = (state_q == ST_IDLE) ? c_addr_i : req_addr_q;

    assign accept      = (state_q == ST_IDLE) && c_req_i;
    assign hit_accept  = accept && hit;
    assign miss_accept = accept && !hit;
    assign refill_en   = (state_q == ST_MEM) && m_gnt_i;

    cache_address_decoder #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) address_decoder (
        .c_addr_i(lookup_addr),
        .tag_o(tag),
        .index_o(set_idx),
        .line_offset_o(),
        .word_offset_o(word),
        .m_addr_o(aligned_addr)
    );

    cache_valid_array #(.NUM_SETS(NUM_SETS), .NW(NW)) valid_array (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .lookup_set_i(set_idx),
        .refill_valid_i(refill_en),
        .refill_set_i(set_idx),
        .refill_way_i(victim_q),
        .valid_mask_o(valid_mask),
        .invalid_mask_o(invalid_mask)
    );

    cache_tag_array #(.TAG_WIDTH(TAG_WIDTH), .NUM_SETS(NUM_SETS), .NW(NW)) tag_array (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .req_tag_i(tag),
        .lookup_set_i(set_idx),
        .valid_mask_i(valid_mask),
        .refill_valid_i(refill_en),
        .refill_tag_i(tag),
        .refill_set_i(set_idx),
        .refill_way_i(victim_q),
        .hit_o(hit),
        .hit_way_o(hit_way)
    );

    cache_data_array #(.C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) data_array (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .read_set_i(set_idx),
        .read_way_i(hit_way),
        .word_offset_i(word),
        .read_data_o(cached_data),
        .refill_valid_i(refill_en),
        .refill_set_i(set_idx),
        .refill_way_i(victim_q),
        .refill_data_i(m_data_i)
    );

    lfu_replacement #(.COUNTER_WIDTH(4), .NUM_SETS(NUM_SETS), .NW(NW)) replacement (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .set_index_i(set_idx),
        .hit_way_i(hit_way),
        .hit_i(hit_accept),
        .refill_valid_i(refill_en),
        .refill_way_i(victim_q),
        .valid_mask_i(valid_mask),
        .candidate_mask_o(lfu_candidates)
    );

    // ---- victim selection ------------------------------------------------
    assign any_invalid       = |invalid_mask;
    assign victim_candidates = lfu_candidates;

    always @* begin
        integer n;
        integer w;
        n = 0;
        for (w = 0; w < NW; w = w + 1)
            if (victim_candidates[w])
                n = n + 1;
        multiple_victims = (n > 1);
    end

    lfsr #(.LFSR_WIDTH(8)) random_generator (
        .clk_i(clk_i), .arst_ni(arst_ni),
        .advance_i(miss_accept && !any_invalid && multiple_victims),
        .lfsr_o(random_value)
    );

    random_tiebreaker #(.NW(NW), .RNG_WIDTH(8)) tie_breaker (
        .candidate_mask(victim_candidates),
        .random_value(random_value),
        .victim_way(random_way)
    );

    always @* begin
        integer w;
        selected_victim = random_way;
        if (any_invalid) begin
            selected_victim = {WAY_WIDTH{1'b0}};
            for (w = NW - 1; w >= 0; w = w - 1)
                if (invalid_mask[w])
                    selected_victim = w;
        end
    end

    // ---- FSM -----------------------------------------------------------
    always @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            state_q     <= ST_IDLE;
            req_addr_q  <= {AW{1'b0}};
            mem_addr_q  <= {AW{1'b0}};
            victim_q    <= {WAY_WIDTH{1'b0}};
            resp_data_q <= {C_DW{1'b0}};
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (hit_accept) begin
                        resp_data_q <= cached_data;
                        state_q     <= ST_RESP;
                    end else if (miss_accept) begin
                        req_addr_q  <= c_addr_i;
                        mem_addr_q  <= aligned_addr;
                        victim_q    <= selected_victim;
                        state_q     <= ST_MEM;
                    end
                end
                ST_MEM: begin
                    if (m_gnt_i) begin
                        resp_data_q <= m_data_i[word * C_DW +: C_DW];
                        state_q     <= ST_RESP;
                    end
                end
                ST_RESP: state_q <= ST_IDLE;
                default: state_q <= ST_IDLE;
            endcase
        end
    end

    assign c_gnt_o  = (state_q == ST_RESP);
    assign c_data_o = resp_data_q;
    assign m_req_o  = (state_q == ST_MEM);
    assign m_addr_o = mem_addr_q;

endmodule