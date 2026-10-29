module simple_cache
  import cache_pkg::*;
#(
  parameter int AW   = 16,
  parameter int C_DW = 8,
  parameter int M_DW = 128,
  parameter int CL   = 256,
  parameter int NW   = 4
)(
  input  logic             arst_ni,
  input  logic             clk_i,

  input  logic [AW-1:0]    c_addr_i,
  input  logic             c_req_i,
  output logic [C_DW-1:0]  c_data_o,
  output logic             c_gnt_o,

  output logic [AW-1:0]    m_addr_o,
  output logic             m_req_o,
  input  logic [M_DW-1:0]  m_data_i,
  input  logic             m_gnt_i
);

  localparam int OFFSET_BITS = $clog2(M_DW/8);
  localparam int INDEX_BITS  = $clog2(CL/NW);
  localparam int TAG_BITS    = AW - INDEX_BITS - OFFSET_BITS;
  localparam int SETS        = CL / NW;
  localparam int VC_SIZE     = 8;

  //==================================================
  // Address Decode
  //==================================================
  tag_t    addr_tag;
  index_t  addr_index;
  offset_t addr_offset;

  assign addr_tag    = c_addr_i[AW-1 -: TAG_BITS];
  assign addr_index  = c_addr_i[OFFSET_BITS +: INDEX_BITS];
  assign addr_offset = c_addr_i[OFFSET_BITS-1:0];

  //==================================================
  // Internal Signals
  //==================================================
  logic hit, vc_hit;
  logic [1:0] hit_way, victim_way;
  line_t hit_data, vc_data;
  cache_line_t lines [NW-1:0];
  logic lock [NW-1:0];

  //==================================================
  // FSM
  //==================================================
  typedef enum logic [2:0] {
    IDLE,
    LOOKUP,
    REFILL_REQ,
    REFILL_WAIT,
    RESPOND
  } state_t;

  state_t state, next_state;
  logic we_main;
  logic [1:0] way_main;
  cache_line_t wdata_main;

  logic we_vc;
  cache_line_t wdata_vc;

  //==================================================
  // Submodules
  //==================================================
  tag_data_array #(.SETS(SETS), .NW(NW)) u_tag_data (
    .clk_i,
    .arst_ni,
    .index_i    (addr_index),
    .tag_i      (addr_tag),
    .we_i       (we_main),
    .way_i      (way_main),
    .wdata_i    (wdata_main),
    .hit_o      (hit),
    .hit_way_o  (hit_way),
    .hit_data_o (hit_data),
    .line_o     (lines)
  );

  lru_pinning_unit #(.SETS(SETS), .NW(NW)) u_lru_pin (
    .clk_i,
    .arst_ni,
    .index_i      (addr_index),
    .hit_i        (hit && (state == LOOKUP)),
    .hit_way_i    (hit_way),
    .allocate_i   (we_main),
    .alloc_way_i  (way_main),
    .lines_i      (lines),
    .victim_way_o (victim_way),
    .lock_o       (lock)
  );

  victim_cache #(.VC_SIZE(VC_SIZE)) u_victim (
    .clk_i,
    .arst_ni,
    .tag_i     (addr_tag),
    .lookup_i  (state == LOOKUP && !hit),
    .we_i      (we_vc),
    .wdata_i   (wdata_vc),
    .hit_o     (vc_hit),
    .data_o    (vc_data),
    .hit_idx_o ()
  );

  //==================================================
  // Byte Select (safe)
  //==================================================
  function automatic logic [C_DW-1:0] get_byte(input line_t line, input offset_t off);
    get_byte = line[off*8 +: 8];
  endfunction



  // Registered response data (corruption avoid korte)
  logic [C_DW-1:0] resp_data_r;
  logic            resp_valid_r;

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      state        <= IDLE;
      resp_data_r  <= '0;
      resp_valid_r <= 1'b0;
    end else begin
      state <= next_state;

      // Default
      resp_valid_r <= 1'b0;

      case (state)
        LOOKUP: begin
          if (hit) begin
            resp_data_r  <= get_byte(hit_data, addr_offset);
            resp_valid_r <= 1'b1;
          end
          else if (vc_hit) begin
            resp_data_r  <= get_byte(vc_data, addr_offset);
            resp_valid_r <= 1'b1;
          end
        end

        REFILL_WAIT: begin
          if (m_gnt_i) begin
            resp_data_r  <= get_byte(m_data_i, addr_offset);
            resp_valid_r <= 1'b1;
          end
        end
      endcase
    end
  end

  // Combinational next state + memory request
  always_comb begin
    next_state = state;
    m_req_o    = 1'b0;
    m_addr_o   = '0;
    we_main    = 1'b0;
    we_vc      = 1'b0;
    way_main   = victim_way;
    wdata_main = '0;
    wdata_vc   = '0;

    c_gnt_o  = resp_valid_r;
    c_data_o = resp_data_r;

    case (state)
      IDLE: begin
        if (c_req_i)
          next_state = LOOKUP;
      end

      LOOKUP: begin
        if (hit) begin
          next_state = IDLE;
        end
        else if (vc_hit) begin
          // Promote from Victim → Main
          we_main = 1'b1;
          way_main = victim_way;

          wdata_main.valid = 1'b1;
          wdata_main.lock  = 1'b0;
          wdata_main.freq  = 2'b01;
          wdata_main.tag   = addr_tag;
          wdata_main.data  = vc_data;

          // Old line to Victim
          if (lines[victim_way].valid) begin
            we_vc    = 1'b1;
            wdata_vc = lines[victim_way];
          end

          next_state = IDLE;
        end
        else begin
          next_state = REFILL_REQ;
        end
      end

      REFILL_REQ: begin
        m_req_o  = 1'b1;
        m_addr_o = {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};

        if (m_gnt_i)
          next_state = REFILL_WAIT;
      end

      REFILL_WAIT: begin
        if (m_gnt_i) begin
          // Allocate new line
          we_main = 1'b1;
          way_main = victim_way;

          wdata_main.valid = 1'b1;
          wdata_main.lock  = 1'b0;
          wdata_main.freq  = 2'b00;
          wdata_main.tag   = addr_tag;
          wdata_main.data  = m_data_i;

          // Evict old line to Victim
          if (lines[victim_way].valid) begin
            we_vc    = 1'b1;
            wdata_vc = lines[victim_way];
          end

          next_state = IDLE;
        end
      end

      default: next_state = IDLE;
    endcase
  end

endmodule