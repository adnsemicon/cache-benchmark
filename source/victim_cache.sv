module victim_cache
  import cache_pkg::*;
#(
  parameter int VC_SIZE = 8
)(
  input  logic             clk_i,
  input  logic             arst_ni,

  input  tag_t             tag_i,
  input  logic             lookup_i,

  // Write (from main cache eviction)
  input  logic             we_i,
  input  cache_line_t      wdata_i,

  // Output
  output logic             hit_o,
  output line_t            data_o,
  output logic [$clog2(VC_SIZE)-1:0] hit_idx_o
);

  cache_line_t vc [VC_SIZE-1:0];
  logic [$clog2(VC_SIZE)-1:0] wr_ptr;

  // Lookup
  always_comb begin
    hit_o = 1'b0;
    data_o = '0;
    hit_idx_o = '0;

    for (int i = 0; i < VC_SIZE; i++) begin
      if (vc[i].valid && vc[i].tag == tag_i) begin
        hit_o = 1'b1;
        data_o = vc[i].data;
        hit_idx_o = i[$clog2(VC_SIZE)-1:0];
      end
    end
  end

  // Write + Invalidate
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      for (int i = 0; i < VC_SIZE; i++)
        vc[i] <= '0;
      wr_ptr <= '0;
    end
    else begin
      if (we_i) begin
        vc[wr_ptr] <= wdata_i;
        wr_ptr <= wr_ptr + 1;
      end

      // Invalidate on hit (will be promoted)
      if (lookup_i && hit_o) begin
        vc[hit_idx_o].valid <= 1'b0;
      end
    end
  end

endmodule