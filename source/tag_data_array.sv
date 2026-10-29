// Tag + data storage for the main cache. Fully parameterised (no package types).
module tag_data_array #(
  parameter int SETS     = 64,
  parameter int NW       = 4,
  parameter int TAG_BITS = 4,
  parameter int M_DW     = 128
)(
  input  logic                              clk_i,
  input  logic                              arst_ni,

  input  logic [$clog2(SETS)-1:0]           index_i,
  input  logic [TAG_BITS-1:0]               tag_i,

  // Write port (one way of the selected set)
  input  logic                              we_i,
  input  logic [(NW>1 ? $clog2(NW) : 1)-1:0] way_i,
  input  logic [TAG_BITS-1:0]               wtag_i,
  input  logic [M_DW-1:0]                   wdata_i,

  // Lookup result
  output logic                              hit_o,
  output logic [(NW>1 ? $clog2(NW) : 1)-1:0] hit_way_o,
  output logic [M_DW-1:0]                   hit_data_o,

  // Whole-set view (used for victim selection / eviction)
  output logic [NW-1:0]                     valid_o,
  output logic [NW-1:0][TAG_BITS-1:0]       tag_o,
  output logic [NW-1:0][M_DW-1:0]           data_o
);

  localparam int WB = (NW > 1) ? $clog2(NW) : 1;

  logic [SETS-1:0][NW-1:0] valid_q;
  logic [TAG_BITS-1:0]     tag_mem  [SETS][NW];
  logic [M_DW-1:0]         data_mem [SETS][NW];

  always_comb begin
    hit_o      = 1'b0;
    hit_way_o  = '0;
    hit_data_o = '0;
    for (int w = 0; w < NW; w++) begin
      valid_o[w] = valid_q[index_i][w];
      tag_o[w]   = tag_mem[index_i][w];
      data_o[w]  = data_mem[index_i][w];
      if (valid_q[index_i][w] && (tag_mem[index_i][w] == tag_i)) begin
        hit_o      = 1'b1;
        hit_way_o  = WB'(w);
        hit_data_o = data_mem[index_i][w];
      end
    end
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      valid_q <= '0;
    end else if (we_i) begin
      valid_q[index_i][way_i] <= 1'b1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (we_i) begin
      tag_mem [index_i][way_i] <= wtag_i;
      data_mem[index_i][way_i] <= wdata_i;
    end
  end

endmodule