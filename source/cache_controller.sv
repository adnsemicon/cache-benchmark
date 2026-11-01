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
// Replacement: first invalid way, otherwise POLICY (0 = LRU, 1 = DRRIP).
module cache_controller #(
    parameter int AW   = 16,
    parameter int C_DW = 8,
    parameter int M_DW = 128,
    parameter int CL   = 256,
    parameter int NW   = 4
) (
    input  logic            clk_i,
    input  logic            arst_ni,
    input  logic            c_req_i,
    input  logic [AW-1:0]   c_addr_i,
    output logic            c_gnt_o,
    output logic [C_DW-1:0] c_data_o,
    output logic [AW-1:0]   m_addr_o,
    output logic            m_req_o,
    input  logic [M_DW-1:0] m_data_i,
    input  logic            m_gnt_i
);

    localparam int NUM_SETS   = CL / NW;
    localparam int LINE_BYTES = M_DW / 8;
    localparam int OFF_W      = $clog2(LINE_BYTES);
    localparam int IDX_W      = $clog2(NUM_SETS);
    localparam bit SETS_POW2  = (NUM_SETS & (NUM_SETS - 1)) == 0;
    localparam int RAW_TAG_W  = SETS_POW2 ? AW - OFF_W - IDX_W : AW - OFF_W;
    localparam int TAG_WIDTH  = (RAW_TAG_W > 0) ? RAW_TAG_W : 1;
    localparam int SET_WIDTH  = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1;
    localparam int WAY_WIDTH  = (NW > 1) ? $clog2(NW) : 1;
    localparam int WORDS      = M_DW / C_DW;
    localparam int WORD_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

    localparam logic [1:0] ST_IDLE = 2'd0;
    localparam logic [1:0] ST_MEM  = 2'd1;
    localparam logic [1:0] ST_RESP = 2'd2;

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
    logic [1:0]             state_q;
    logic [AW-1:0]          req_addr_q;
    logic [AW-1:0]          mem_addr_q;
    logic [WAY_WIDTH-1:0]   victim_q;
    logic [C_DW-1:0]        resp_data_q;

    logic [AW-1:0]          lookup_addr;
    logic [TAG_WIDTH-1:0]   tag;
    logic [SET_WIDTH-1:0]   set_idx;
    logic [WORD_WIDTH-1:0]  word;
    logic [AW-1:0]          aligned_addr;

    logic [NW-1:0]          valid_mask, invalid_mask;
    logic                   hit;
    logic [WAY_WIDTH-1:0]   hit_way;
    logic [C_DW-1:0]        cached_data;
    logic [WAY_WIDTH-1:0]   repl_victim, selected_victim;
    logic                   any_invalid;

    logic                   accept, hit_accept, miss_accept, refill_en;

    // The lookup path looks at the incoming address while idle and at the
    // latched address while a miss is being serviced.
    assign lookup_addr = (state_q == ST_IDLE) ? c_addr_i : req_addr_q;

    assign accept      = (state_q == ST_IDLE) && c_req_i;
    assign hit_accept  = accept && hit;
    assign miss_accept = accept && !hit;
    assign refill_en   = (state_q == ST_MEM) && m_gnt_i;

    cache_address_decoder #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) address_decoder (
        .c_addr_i      (lookup_addr),
        .tag_o         (tag),
        .index_o       (set_idx),
        .line_offset_o (),
        .word_offset_o (word),
        .m_addr_o      (aligned_addr)
    );

    cache_valid_array #(.NUM_SETS(NUM_SETS), .NW(NW)) valid_array (
        .clk_i, .arst_ni,
        .lookup_set_i   (set_idx),
        .refill_valid_i (refill_en),
        .refill_set_i   (set_idx),
        .refill_way_i   (victim_q),
        .valid_mask_o   (valid_mask),
        .invalid_mask_o (invalid_mask)
    );

    cache_tag_array #(.TAG_WIDTH(TAG_WIDTH), .NUM_SETS(NUM_SETS), .NW(NW)) tag_array (
        .clk_i, .arst_ni,
        .req_tag_i      (tag),
        .lookup_set_i   (set_idx),
        .valid_mask_i   (valid_mask),
        .refill_valid_i (refill_en),
        .refill_tag_i   (tag),
        .refill_set_i   (set_idx),
        .refill_way_i   (victim_q),
        .hit_o          (hit),
        .hit_way_o      (hit_way)
    );

    cache_data_array #(.C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) data_array (
        .clk_i, .arst_ni,
        .read_set_i     (set_idx),
        .read_way_i     (hit_way),
        .word_offset_i  (word),
        .read_data_o    (cached_data),
        .refill_valid_i (refill_en),
        .refill_set_i   (set_idx),
        .refill_way_i   (victim_q),      // victim way, NOT the hit way
        .refill_data_i  (m_data_i)
    );

    // Replacement policy switch: 0 = true LRU, 1 = DRRIP. Both modules share a port list.
    localparam int POLICY = 0;

    if (POLICY == 0) begin : g_lru
        lru_replacement #(.RRPV_WIDTH(2), .NUM_SETS(NUM_SETS), .NW(NW)) replacement (
            .clk_i, .arst_ni,
            .set_index_i    (set_idx),
            .hit_i          (hit_accept),
            .hit_way_i      (hit_way),
            .refill_valid_i (refill_en),
            .refill_way_i   (victim_q),
            .valid_mask_i   (valid_mask),
            .victim_way_o   (repl_victim)
        );
    end else begin : g_drrip
        rrip_replacement #(.RRPV_WIDTH(2), .NUM_SETS(NUM_SETS), .NW(NW)) replacement (
            .clk_i, .arst_ni,
            .set_index_i    (set_idx),
            .hit_i          (hit_accept),
            .hit_way_i      (hit_way),
            .refill_valid_i (refill_en),
            .refill_way_i   (victim_q),
            .valid_mask_i   (valid_mask),
            .victim_way_o   (repl_victim)
        );
    end

    // ---- victim selection: first invalid way, else policy victim -----------------
    assign any_invalid = |invalid_mask;

    always_comb begin
        selected_victim = repl_victim;
        if (any_invalid) begin
            selected_victim = '0;
            for (int w = NW - 1; w >= 0; w--)
                if (invalid_mask[w]) selected_victim = WAY_WIDTH'(w);
        end
    end

    // ---- FSM -----------------------------------------------------------
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            state_q     <= ST_IDLE;
            req_addr_q  <= '0;
            mem_addr_q  <= '0;
            victim_q    <= '0;
            resp_data_q <= '0;
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