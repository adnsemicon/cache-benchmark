
module victim_cache #(
  parameter int VC_SIZE = 8,
  parameter int LINE_AW = 12,
  parameter int M_DW    = 128
)(
  input  logic clk_i,
  input  logic arst_ni,

  input  logic [LINE_AW-1:0] line_addr_i,

  input  logic promote_i,
  input  logic insert_i,

  input  logic evict_valid_i,
  input  logic [LINE_AW-1:0] evict_addr_i,
  input  logic [M_DW-1:0] evict_data_i,

  output logic hit_o,
  output logic [M_DW-1:0] data_o
);

  localparam int PB =
      (VC_SIZE > 1) ? $clog2(VC_SIZE) : 1;

  logic [VC_SIZE-1:0] valid_q;

  logic [LINE_AW-1:0] addr_q [VC_SIZE];
  logic [M_DW-1:0] data_q [VC_SIZE];

  logic [PB-1:0] wr_ptr;
  logic [PB-1:0] hit_idx;
  logic [PB-1:0] ins_idx;

  logic ins_free;

  //==================================================
  // Victim Cache Lookup
  //==================================================

  always_comb begin

    hit_o   = 1'b0;
    data_o  = '0;
    hit_idx = '0;

    for (int i = 0; i < VC_SIZE; i++) begin

      if (valid_q[i] &&
          addr_q[i] == line_addr_i) begin

        hit_o   = 1'b1;
        data_o  = data_q[i];
        hit_idx = PB'(i);

      end

    end

  end

  //==================================================
  // Find insertion slot
  //==================================================

  always_comb begin

    ins_idx  = wr_ptr;
    ins_free = 1'b0;

    for (int i = VC_SIZE-1; i >= 0; i--) begin

      if (!valid_q[i]) begin

        ins_idx  = PB'(i);
        ins_free = 1'b1;

      end

    end

  end

  //==================================================
  // VC State Update
  //==================================================

  always_ff @(posedge clk_i or negedge arst_ni) begin

    if (!arst_ni) begin

      valid_q <= '0;
      wr_ptr  <= '0;

      for (int i = 0; i < VC_SIZE; i++) begin
        addr_q[i] <= '0;
        data_q[i] <= '0;
      end

    end

    else begin

      // VC hit:
      // Remove promoted line and replace it
      // with the evicted main-cache line.
      if (promote_i && hit_o) begin

        valid_q[hit_idx] <= evict_valid_i;

        if (evict_valid_i) begin

          addr_q[hit_idx] <= evict_addr_i;
          data_q[hit_idx] <= evict_data_i;

        end

      end

      // Memory refill:
      // Insert evicted main-cache line.
      else if (insert_i && evict_valid_i) begin

        valid_q[ins_idx] <= 1'b1;

        addr_q[ins_idx] <= evict_addr_i;
        data_q[ins_idx] <= evict_data_i;

        // Advance FIFO pointer only when
        // the VC was already full.
        if (!ins_free) begin

          if (wr_ptr == PB'(VC_SIZE-1))
            wr_ptr <= '0;
          else
            wr_ptr <= wr_ptr + 1'b1;

        end

      end

    end

  end

endmodule
