module simple_cache #(
  parameter int AW      = 16,
  parameter int C_DW    = 8,
  parameter int M_DW    = 128,
  parameter int CL      = 256,
  parameter int NW      = 4,
  parameter int VC_SIZE = 64,
`ifdef USE_DRRIP
  parameter int REPL    = 1     // DRRIP (compile with -d USE_DRRIP)
`else
  parameter int REPL    = 2     // 0: true LRU, 1: DRRIP, 2: PLRU (default)
`endif
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
  localparam int SETS        = CL / NW;
  localparam int INDEX_BITS  = $clog2(SETS);
  localparam int TAG_BITS    = AW - INDEX_BITS - OFFSET_BITS;
  localparam int LINE_AW     = AW - OFFSET_BITS;
  localparam int WB          = (NW > 1) ? $clog2(NW) : 1;

  //==================================================
  // FSM
  //==================================================
  typedef enum logic [1:0] { IDLE, REFILL, RESP } state_t;
  state_t state, next_state;

  //==================================================
  // Address Slicing (Fixed with addr_q)
  //==================================================
  logic [AW-1:0] addr_q;
  
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      addr_q <= '0;
    end else if (state == IDLE && c_req_i) begin
      addr_q <= c_addr_i;
    end
  end

  logic [AW-1:0]          cur_addr;
  assign cur_addr = (state == IDLE) ? c_addr_i : addr_q;

  logic [TAG_BITS-1:0]    cur_tag;
  logic [INDEX_BITS-1:0]  cur_index;
  logic [OFFSET_BITS-1:0] cur_off;
  logic [LINE_AW-1:0]     cur_line_addr;

  assign cur_tag       = cur_addr[AW-1 -: TAG_BITS];
  assign cur_index     = cur_addr[OFFSET_BITS +: INDEX_BITS];
  assign cur_off       = cur_addr[OFFSET_BITS-1:0];
  assign cur_line_addr = cur_addr[AW-1:OFFSET_BITS];

  //==================================================
  // Single Byte-Select Function
  //==================================================
  function automatic logic [C_DW-1:0] get_data(
    input logic [M_DW-1:0]        line,
    input logic [OFFSET_BITS-1:0] off
  );
    logic [M_DW+C_DW-1:0] ext;
    ext      = {{C_DW{1'b0}}, line};
    get_data = ext[int'(off)*8 +: C_DW];
  endfunction

  //==================================================
  // Submodules
  //==================================================
  logic                 hit, vc_hit;
  logic [WB-1:0]        hit_way, victim_way;
  logic [M_DW-1:0]      hit_data, vc_data;
  logic [NW-1:0]        set_valid;
  logic [NW-1:0][TAG_BITS-1:0] set_tag;
  logic [NW-1:0][M_DW-1:0]     set_data;

  logic                 we_main;
  logic [WB-1:0]        way_main;
  logic [TAG_BITS-1:0]  wtag_main;
  logic [M_DW-1:0]      wdata_main;

  logic                 rp_hit, rp_fill;
  logic                 vc_promote, vc_insert;

  logic                 evict_valid;
  logic [LINE_AW-1:0]   evict_addr;
  logic [M_DW-1:0]      evict_data;

  assign evict_valid = set_valid[victim_way];
  assign evict_addr  = {set_tag[victim_way], cur_index};
  assign evict_data  = set_data[victim_way];

  tag_data_array #(.SETS(SETS), .NW(NW), .TAG_BITS(TAG_BITS), .M_DW(M_DW)) u_tag_data (
    .clk_i, .arst_ni,
    .index_i    (cur_index),
    .tag_i      (cur_tag),
    .we_i       (we_main),
    .way_i      (way_main),
    .wtag_i     (wtag_main),
    .wdata_i    (wdata_main),
    .hit_o      (hit),
    .hit_way_o  (hit_way),
    .hit_data_o (hit_data),
    .valid_o    (set_valid),
    .tag_o      (set_tag),
    .data_o     (set_data)
  );

  lru_pinning_unit #(.SETS(SETS), .NW(NW), .REPL(REPL)) u_lru_pin (
    .clk_i, .arst_ni,
    .index_i      (cur_index),
    .hit_i        (rp_hit),
    .hit_way_i    (hit_way),
    .fill_i       (rp_fill),
    .fill_way_i   (victim_way),
    .valid_i      (set_valid),
    .victim_way_o (victim_way)
  );

  victim_cache #(.VC_SIZE(VC_SIZE), .LINE_AW(LINE_AW), .M_DW(M_DW)) u_victim (
    .clk_i, .arst_ni,
    .line_addr_i   (cur_line_addr),
    .promote_i     (vc_promote),
    .insert_i      (vc_insert),
    .evict_valid_i (evict_valid),
    .evict_addr_i  (evict_addr),
    .evict_data_i  (evict_data),
    .hit_o         (vc_hit),
    .data_o        (vc_data)
  );

  //==================================================
  // Control Logic
  //==================================================
  logic [C_DW-1:0] resp_data_q, resp_data_d;
  logic            resp_we;

  always_comb begin
    next_state  = state;
    m_req_o     = 1'b0;
    m_addr_o    = '0;
    we_main     = 1'b0;
    way_main    = victim_way;
    wtag_main   = cur_tag;
    wdata_main  = '0;
    rp_hit      = 1'b0;
    rp_fill     = 1'b0;
    vc_promote  = 1'b0;
    vc_insert   = 1'b0;
    resp_we     = 1'b0;
    resp_data_d = '0;

    case (state)
      IDLE: begin
        if (c_req_i) begin
          if (hit) begin
            resp_we     = 1'b1;
            resp_data_d = get_data(hit_data, cur_off);
            rp_hit      = 1'b1;
            next_state  = RESP;
          end else if (vc_hit) begin
            we_main     = 1'b1;
            way_main    = victim_way;
            wdata_main  = vc_data;
            vc_promote  = 1'b1;
            rp_fill     = 1'b1;
            resp_we     = 1'b1;
            resp_data_d = get_data(vc_data, cur_off);
            next_state  = RESP;
          end else begin
            next_state  = REFILL;
          end
        end
      end

      REFILL: begin
        m_req_o     = 1'b1;
        m_addr_o    = {cur_line_addr, {OFFSET_BITS{1'b0}}};
        wtag_main   = cur_tag;  // Ensure correct tag is written
        if (m_gnt_i) begin
          we_main     = 1'b1;
          way_main    = victim_way;
          wdata_main  = m_data_i;
          vc_insert   = 1'b1;
          rp_fill     = 1'b1;
          resp_we     = 1'b1;
          resp_data_d = get_data(m_data_i, cur_off);
          next_state  = RESP;
        end
      end

      RESP: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      state       <= IDLE;
      resp_data_q <= '0;
    end else begin
      state <= next_state;
      if (resp_we) resp_data_q <= resp_data_d;
    end
  end

  assign c_gnt_o  = (state == RESP);
  assign c_data_o = resp_data_q;

  //==================================================
  // Limited Remote Debug Logs (Max 30 prints)
  //==================================================
  int dbg_cnt = 0;

  always_ff @(posedge clk_i) begin
    if (arst_ni && dbg_cnt < 30) begin
      if (state == IDLE && c_req_i) begin
        if (hit) begin
          $display("[DBG %0d] T=%0t | HIT | Addr=0x%0h (Tag=0x%0h, Idx=0x%0h)", dbg_cnt, $time, c_addr_i, cur_tag, cur_index);
          dbg_cnt <= dbg_cnt + 1;
        end else if (vc_hit) begin
          $display("[DBG %0d] T=%0t | VC_HIT | Addr=0x%0h", dbg_cnt, $time, c_addr_i);
          dbg_cnt <= dbg_cnt + 1;
        end else begin
          $display("[DBG %0d] T=%0t | MISS | Addr=0x%0h -> REFILL", dbg_cnt, $time, c_addr_i);
          dbg_cnt <= dbg_cnt + 1;
        end
      end
    end
  end

endmodule
