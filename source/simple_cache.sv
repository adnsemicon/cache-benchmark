module simple_cache #(
    parameter int AW   = 16,   // Address Width
    parameter int C_DW = 8,    // Cache Data Width (CPU side)
    parameter int M_DW = 128,  // Memory Data Width (Cache line size)
    parameter int CL   = 512,  // Total Cache Lines
    parameter int NW   = 4,    // Number of Ways per Set
    parameter int VC_SIZE = 16 // Victim Cache Size
)(
    input  logic              arst_ni,
    input  logic              clk_i,
    
    // CPU-Side Interface
    input  logic [AW-1:0]     c_addr_i,
    input  logic              c_req_i,
    output logic [C_DW-1:0]   c_data_o,
    output logic              c_gnt_o,
    
    // Memory-Side Interface
    output logic [AW-1:0]     m_addr_o,
    output logic              m_req_o,
    input  logic [M_DW-1:0]   m_data_i,
    input  logic              m_gnt_i
);

    // Derived Parameters
    localparam int NUM_SETS = CL / NW;                    // e.g., 512 / 4 = 128 sets
    localparam int INDEX_BITS = $clog2(NUM_SETS);         // 7 bits
    localparam int OFFSET_BITS = $clog2(M_DW / C_DW);     // log2(128/8) = 4 bits
    localparam int TAG_BITS = AW - INDEX_BITS - OFFSET_BITS; // 16 - 7 - 4 = 5 bits

    // Address Decoding
    logic [TAG_BITS-1:0]    tag_in;
    logic [INDEX_BITS-1:0]  set_in;
    logic [OFFSET_BITS-1:0] offset_in;

    assign tag_in    = c_addr_i[AW-1 : AW-TAG_BITS];
    assign set_in    = c_addr_i[AW-TAG_BITS-1 : OFFSET_BITS];
    assign offset_in = c_addr_i[OFFSET_BITS-1 : 0];

    // Storage Arrays for Main Cache
    logic                   valid_mem [NUM_SETS-1:0][NW-1:0];
    logic [TAG_BITS-1:0]    tag_mem   [NUM_SETS-1:0][NW-1:0];
    logic [M_DW-1:0]        data_mem  [NUM_SETS-1:0][NW-1:0];

    // Hit & Way Signals
    logic                   main_cache_hit;
    logic [1:0]             hit_way;
    logic [C_DW-1:0]        matched_data;

    // DRRIP & Victim Cache Control Signals
    logic [1:0]             victim_way;
    logic [1:0]             update_way;
    logic [1:0]             update_rrpv;
    logic                   refill_trigger;
    
    // Victim Cache Wires
    logic                   vc_hit;
    logic [M_DW-1:0]        vc_data_out;
    logic                   vc_lookup_en;
    logic                   vc_swap_en;

    // ---------------------------------------------------------
    // 1. Tag & Hit Comparison Logic
    // ---------------------------------------------------------
    always_comb begin
        main_cache_hit = 1'b0;
        hit_way        = 2'b00;
        matched_data   = '0;

        for (int w = 0; w < NW; w++) begin
            if (valid_mem[set_in][w] && (tag_mem[set_in][w] == tag_in)) begin
                main_cache_hit = 1'b1;
                hit_way        = w[1:0];
                // Extract specific C_DW chunk from M_DW line based on offset
                case (offset_in[3:2]) // Adjust based on chunk granularity
                    2'b00: matched_data = data_mem[set_in][w][C_DW-1 : 0];
                    2'b01: matched_data = data_mem[set_in][w][2*C_DW-1 : C_DW];
                    2'b10: matched_data = data_mem[set_in][w][3*C_DW-1 : 2*C_DW];
                    2'b11: matched_data = data_mem[set_in][w][4*C_DW-1 : 3*C_DW];
                    default: matched_data = data_mem[set_in][w][C_DW-1 : 0];
                endcase
            end
        end
    end

    // ---------------------------------------------------------
    // 2. LRU / DRRIP Pinning Unit Instantiation
    // ---------------------------------------------------------
    lru_pinning_unit #(
        .SETS(NUM_SETS),
        .REPL(2)
    ) u_lru_pinning (
        .clk_i(clk_i),
        .arst_ni(arst_ni),
        .set_idx_i(set_in),
        .hit_i(main_cache_hit),
        .hit_way_i(hit_way),
        .refill_i(refill_trigger),
        .victim_way_o(victim_way),
        .update_way_o(update_way),
        .update_rrpv_o(update_rrpv)
    );

    // ---------------------------------------------------------
    // 3. Victim Cache Instantiation
    // ---------------------------------------------------------
    victim_cache #(
        .AW(AW),
        .M_DW(M_DW),
        .VC_SIZE(VC_SIZE)
    ) u_victim_cache (
        .clk_i(clk_i),
        .arst_ni(arst_ni),
        .lookup_en_i(vc_lookup_en),
        .swap_en_i(vc_swap_en),
        .addr_i(c_addr_i),
        .evicted_tag_i({tag_in, set_in}),
        .evicted_data_i(data_mem[set_in][victim_way]),
        .vc_hit_o(vc_hit),
        .vc_data_o(vc_data_out)
    );

    // ---------------------------------------------------------
    // 4. Main FSM & Control State Machine
    // ---------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        TAG_CHECK,
        VC_LOOKUP,
        VC_SWAP,
        MEM_REFILL
    } state_e;

    state_e state_q, state_d;

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            state_q <= IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    // Sequential updates for cache lines & refill handling
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            refill_trigger <= 1'b0;
            for (int s = 0; s < NUM_SETS; s++) begin
                for (int w = 0; w < NW; w++) begin
                    valid_mem[s][w] <= 1'b0;
                    tag_mem[s][w]   <= '0;
                    data_mem[s][w]  <= '0;
                end
            end
        end else begin
            refill_trigger <= 1'b0;

            if (state_q == TAG_CHECK && main_cache_hit) begin
                // Hit: Data returned immediately
            end else if (state_q == MEM_REFILL && m_gnt_i) begin
                // Refill from main memory into victim-selected way
                valid_mem[set_in][victim_way] <= 1'b1;
                tag_mem[set_in][victim_way]   <= tag_in;
                data_mem[set_in][victim_way]  <= m_data_i;
                refill_trigger                <= 1'b1;
            end else if (state_q == VC_SWAP) begin
                // Handle swap between Main Cache and Victim Cache
                data_mem[set_in][victim_way]  <= vc_data_out;
                tag_mem[set_in][victim_way]   <= tag_in;
                valid_mem[set_in][victim_way] <= 1'b1;
            end
        end
    end

    // Combinational Next State Logic
    always_comb begin
        state_d      = state_q;
        c_gnt_o      = 1'b0;
        m_req_o      = 1'b0;
        m_addr_o     = {c_addr_i[AW-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}}; // Cache-line aligned
        c_data_o     = '0;
        vc_lookup_en = 1'b0;
        vc_swap_en   = 1'b0;

        case (state_q)
            IDLE: begin
                if (c_req_i) begin
                    state_d = TAG_CHECK;
                end
            end

            TAG_CHECK: begin
                if (main_cache_hit) begin
                    c_gnt_o  = 1'b1;
                    c_data_o = matched_data;
                    state_d  = IDLE;
                end else begin
                    // Miss -> Check Victim Cache
                    vc_lookup_en = 1'b1;
                    state_d      = VC_LOOKUP;
                end
            end

            VC_LOOKUP: begin
                if (vc_hit) begin
                    // Victim Cache Hit -> Swap
                    vc_swap_en = 1'b1;
                    state_d    = VC_SWAP;
                end else begin
                    // Victim Cache Miss -> Go to Main Memory
                    m_req_o = 1'b1;
                    if (m_gnt_i) begin
                        state_d = IDLE;
                    end else begin
                        state_d = MEM_REFILL;
                    end
                end
            end

            VC_SWAP: begin
                c_gnt_o  = 1'b1;
                state_d  = IDLE;
            end

            MEM_REFILL: begin
                m_req_o = 1'b1;
                if (m_gnt_i) begin
                    c_gnt_o = 1'b1;
                    state_d = IDLE;
                end
            end

            default: state_d = IDLE;
        endcase
    end

endmodule