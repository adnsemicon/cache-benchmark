module victim_cache #(
    parameter int AW     = 16,
    parameter int M_DW   = 128,
    parameter int VC_SIZE = 16  // Number of entries in victim cache (fully associative)
)(
    input  logic              clk_i,
    input  logic              arst_ni,
    input  logic              lookup_en_i,
    input  logic              swap_en_i,
    input  logic [AW-1:0]     addr_i,
    input  logic [15:0]       evicted_tag_i, // {tag, set_idx}
    input  logic [M_DW-1:0]   evicted_data_i,
    output logic              vc_hit_o,
    output logic [M_DW-1:0]   vc_data_o
);

    // Victim Cache Storage Struct / Arrays
    logic                   vc_valid [VC_SIZE-1:0];
    logic [15:0]            vc_tag   [VC_SIZE-1:0];
    logic [M_DW-1:0]        vc_data  [VC_SIZE-1:0];
    
    // Pseudo-LRU or FIFO pointer for replacement inside Victim Cache
    logic [$clog2(VC_SIZE)-1:0] head_ptr;

    integer i;

    // VC Lookup Logic
    always_comb begin
        vc_hit_o  = 1'b0;
        vc_data_o = '0;

        if (lookup_en_i || swap_en_i) begin
            for (i = 0; i < VC_SIZE; i++) begin
                if (vc_valid[i] && (vc_tag[i] == evicted_tag_i)) begin
                    vc_hit_o  = 1'b1;
                    vc_data_o = vc_data[i];
                end
            end
        end
    end

    // VC Management (Insertion & Replacement via FIFO/Pointer)
    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            head_ptr <= '0;
            for (i = 0; i < VC_SIZE; i++) begin
                vc_valid[i] <= 1'b0;
                vc_tag[i]   <= '0;
                vc_data[i]  <= '0;
            end
        end else begin
            if (swap_en_i && vc_hit_o) begin
                // If hit in VC during swap, update the matched entry with the newly evicted line
                for (i = 0; i < VC_SIZE; i++) begin
                    if (vc_valid[i] && (vc_tag[i] == evicted_tag_i)) begin
                        // Store the old main cache eviction into this slot, 
                        // and the matched data was already sent out via vc_data_o
                        vc_data[i] <= evicted_data_i;
                    end
                end
            end else if (!vc_hit_o && lookup_en_i) begin
                // On VC miss, push the newly evicted line from main cache into victim cache
                // using round-robin / FIFO pointer
                vc_valid[head_ptr] <= 1'b1;
                vc_tag[head_ptr]   <= evicted_tag_i;
                vc_data[head_ptr]  <= evicted_data_i;
                head_ptr           <= head_ptr + 1'b1;
            end
        end
    end

endmodule