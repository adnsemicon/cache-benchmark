module victim_cache #(
  parameter int VC_SIZE = 8,
  parameter int LINE_AW = 12,
  parameter int M_DW    = 128
)(
  input  logic                         clk_i,
  input  logic                         arst_ni,
  input  logic [LINE_AW-1:0]           line_addr_i,
  input  logic                         promote_i,
  input  logic                         insert_i,
  input  logic                         evict_valid_i,
  input  logic [LINE_AW-1:0]           evict_addr_i,
  input  logic [M_DW-1:0]              evict_data_i,
  output logic                         hit_o,
  output logic [M_DW-1:0]              data_o
);

  localparam int PB = (VC_SIZE > 1) ? $clog2(VC_SIZE) : 1;

  logic [VC_SIZE-1:0]  valid_q;
  logic [LINE_AW-1:0]  addr_q [VC_SIZE];
  logic [M_DW-1:0]     data_q [VC_SIZE];
  logic [PB-1:0]       wr_ptr;

  logic [PB-1:0]       hit_idx;
  logic                hit_found;

  // Combinational Hit Search & Captured Data
  always_comb begin
    hit_o     = 1'b0;
    data_o    = '0;
    hit_idx   = '0;
    hit_found = 1'b0;

    for (int i = 0; i < VC_SIZE; i++) begin
      if (valid_q[i] && (addr_q[i] == line_addr_i)) begin
        hit_o     = 1'b1;
        data_o    = data_q[i];
        hit_idx   = PB'(i);
        hit_found = 1'b1;
      end
    end
  end

  // Sequential Update for Victim Cache Entries & Swap
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      valid_q <= '0;
      wr_ptr  <= '0;
      for (int i = 0; i < VC_SIZE; i++) begin
        addr_q[i] <= '0;
        data_q[i] <= '0;
      end
    end else begin
      if (promote_i) begin
        // When promoted, the hit entry takes the new evicted line from main cache,
        // and the old hit line is returned to the main cache.
        if (evict_valid_i) begin
          addr_q[hit_idx] <= evict_addr_i;
          data_q[hit_idx] <= evict_data_i;
          valid_q[hit_idx] <= 1'b1;
        end else begin
          valid_q[hit_idx] <= 1'b0;
        end
      end else if (insert_i) begin
        // Standard eviction insertion into victim cache (FIFO replacement)
        if (evict_valid_i) begin
          addr_q[wr_ptr] <= evict_addr_i;
          data_q[wr_ptr] <= evict_data_i;
          valid_q[wr_ptr] <= 1'b1;
          wr_ptr          <= (wr_ptr == PB'(VC_SIZE-1)) ? '0 : wr_ptr + 1'b1;
        end
      end
    end
  end

endmodule