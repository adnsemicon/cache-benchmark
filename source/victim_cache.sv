module victim_cache #(
  parameter int VC_SIZE = 8,
  parameter int LINE_AW = 12,   // AW - OFFSET_BITS
  parameter int M_DW    = 128
)(
  input  logic                         clk_i,
  input  logic                         arst_ni,

  input  logic [LINE_AW-1:0]           line_addr_i,   // address being looked up

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
  logic [PB-1:0]       ins_idx;
  logic                ins_free;

  always_comb begin
    hit_o   = 1'b0;
    data_o  = '0;
    hit_idx = '0;
    for (int i = 0; i < VC_SIZE; i++) begin
      if (valid_q[i] && addr_q[i] == line_addr_i) begin
        hit_o   = 1'b1;
        data_o  = data_q[i];
        hit_idx = PB'(i);
      end
    end

    ins_idx  = wr_ptr;
    ins_free = 1'b0;
    for (int i = 0; i < VC_SIZE; i++) begin
      if (!valid_q[i] && !ins_free) begin
        ins_idx  = PB'(i);
        ins_free = 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      valid_q <= '0;
      wr_ptr  <= '0;
    end else begin
      if (promote_i) begin
        valid_q[hit_idx] <= evict_valid_i;
      end else if (insert_i && evict_valid_i) begin
        valid_q[ins_idx] <= 1'b1;
        if (!ins_free)
          wr_ptr <= (wr_ptr == PB'(VC_SIZE-1)) ? '0 : wr_ptr + 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (promote_i) begin
      addr_q[hit_idx] <= evict_addr_i;
      data_q[hit_idx] <= evict_data_i;
    end else if (insert_i && evict_valid_i) begin
      addr_q[ins_idx] <= evict_addr_i;
      data_q[ins_idx] <= evict_data_i;
    end
  end

endmodule