
// -----------------------------------------------------------------------------
// Self-checking testbench for simple_cache
//  - Memory model : address-derived pattern, random grant latency 0..3 cycles
//  - Reference    : independent timestamp-based true-LRU model predicts every
//                   hit/miss; DUT refill count per read must match.
//  - Tests        : directed LRU eviction order, then locality-heavy random reads
// -----------------------------------------------------------------------------
module simple_cache_tb;

  parameter int AW   = 16;
  parameter int C_DW = 8;
  parameter int M_DW = 128;
  parameter int CL   = 256;
  parameter int NW   = 4;
  parameter int N_RANDOM = 20000;

  localparam int NS       = CL / NW;
  localparam int LINE_BYTES = M_DW / 8;
  localparam int C_BYTES    = C_DW / 8;
  localparam int TAG_W      = AW;

  // ---------------------------------------------------------------- DUT
  logic            clk = 1'b0;
  logic            arst_n;
  logic [AW-1:0]   c_addr;
  logic            c_req;
  logic [C_DW-1:0] c_data;
  logic            c_gnt;
  logic [AW-1:0]   m_addr;
  logic            m_req;
  logic [M_DW-1:0] m_data;
  logic            m_gnt;

  simple_cache #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) dut (
    .arst_ni (arst_n), .clk_i (clk),
    .c_addr_i(c_addr), .c_req_i(c_req), .c_data_o(c_data), .c_gnt_o(c_gnt),
    .m_addr_o(m_addr), .m_req_o(m_req), .m_data_i(m_data), .m_gnt_i(m_gnt)
  );

  always #5 clk = ~clk;

  // ---------------------------------------------------------------- memory model
  function automatic logic [7:0] mem_byte(input logic [AW-1:0] a);
    logic [31:0] t;
    t = 32'(a) * 37 + (32'(a) >> 8) * 11 + 5;
    return t[7:0] ^ 8'hA5;
  endfunction

  function automatic logic [M_DW-1:0] line_at(input logic [AW-1:0] a);
    logic [AW-1:0] base;
    base = (a / LINE_BYTES) * LINE_BYTES;
    for (int i = 0; i < LINE_BYTES; i++) line_at[i*8 +: 8] = mem_byte(base + AW'(i));
  endfunction

  function automatic logic [C_DW-1:0] exp_word(input logic [AW-1:0] a);
    logic [AW-1:0] base;
    base = (a / C_BYTES) * C_BYTES;
    for (int k = 0; k < C_BYTES; k++) exp_word[k*8 +: 8] = mem_byte(base + AW'(k));
  endfunction

  int lat = 0;
  always_ff @(posedge clk) begin
    if (!m_req)       lat <= $urandom_range(0, 3);
    else if (lat != 0) lat <= lat - 1;
  end
  assign m_gnt  = m_req && (lat == 0);
  assign m_data = line_at(m_addr);

  // ---------------------------------------------------------------- protocol checks
  int refill_cnt = 0;
  int errors     = 0;
  logic [AW-1:0] m_addr_prev;
  logic          m_pend_prev = 1'b0;

  always_ff @(posedge clk) begin
    if (m_req && m_gnt) refill_cnt <= refill_cnt + 1;
    if (m_req && ((m_addr % LINE_BYTES) != 0)) begin
      errors++; $display("[%0t] ERROR: m_addr not line aligned: %h", $time, m_addr);
    end
    if (m_pend_prev && m_req && (m_addr != m_addr_prev)) begin
      errors++; $display("[%0t] ERROR: m_addr changed while request pending", $time);
    end
    if (c_gnt && !c_req) begin
      errors++; $display("[%0t] ERROR: c_gnt without c_req", $time);
    end
    m_pend_prev <= m_req && !m_gnt;
    m_addr_prev <= m_addr;
  end

  // ---------------------------------------------------------------- reference LRU model
  bit            mv  [NS][NW];
  logic [TAG_W-1:0] mt [NS][NW];
  longint        mts [NS][NW];
  longint        tick = 0;

  function automatic bit model_access(input logic [AW-1:0] a);  // 1 = hit
    int s, victim;
    longint best;
    logic [TAG_W-1:0] t;
    s = int'((a / LINE_BYTES) % NS);
    t = (a / LINE_BYTES) / NS;
    tick++;
    for (int w = 0; w < NW; w++)
      if (mv[s][w] && mt[s][w] == t) begin mts[s][w] = tick; return 1'b1; end
    victim = -1;
    for (int w = 0; w < NW; w++)
      if (!mv[s][w]) begin victim = w; break; end
    if (victim < 0) begin
      best = mts[s][0]; victim = 0;
      for (int w = 1; w < NW; w++)
        if (mts[s][w] < best) begin best = mts[s][w]; victim = w; end
    end
    mv[s][victim] = 1'b1; mt[s][victim] = t; mts[s][victim] = tick;
    return 1'b0;
  endfunction

  // ---------------------------------------------------------------- read task
  int n_hit = 0, n_miss = 0;

  task automatic do_read(input logic [AW-1:0] a, output bit was_hit);
    bit exp_hit;
    bit got_gnt;
    logic [C_DW-1:0] got_data;
    int cnt_before;
    exp_hit = model_access(a);
    cnt_before  = refill_cnt;
    // Called 1 ns after a clock edge: drive, then sample at the next edges
    c_addr = a;
    c_req  = 1'b1;
    do begin
      @(posedge clk);
      got_gnt  = c_gnt;
      got_data = c_data;
    end while (!got_gnt);
    if (got_data !== exp_word(a)) begin
      errors++;
      $display("[%0t] ERROR: data mismatch addr=%h got=%h exp=%h", $time, a, got_data, exp_word(a));
    end
    was_hit = (refill_cnt == cnt_before);
    if (was_hit !== exp_hit) begin
      errors++;
      $display("[%0t] ERROR: hit/miss mismatch addr=%h dut_hit=%0d model_hit=%0d",
               $time, a, was_hit, exp_hit);
    end
    if (refill_cnt - cnt_before > 1) begin
      errors++; $display("[%0t] ERROR: more than one refill for one read", $time);
    end
    if (was_hit) n_hit++; else n_miss++;
    #1;
    c_req = 1'b0;
  endtask

  function automatic logic [AW-1:0] mk_addr(input int tag, input int set, input int off);
    logic [AW-1:0] a;
    a = AW'(((tag * NS) + set) * LINE_BYTES + off);
    return a;
  endfunction

  task automatic expect_hit(input logic [AW-1:0] a, input bit exp_h, input string msg);
    bit h;
    do_read(a, h);
    if (h !== exp_h) begin
      errors++;
      $display("[%0t] ERROR (directed): %s : expected %s", $time, msg, exp_h ? "HIT" : "MISS");
    end
  endtask

  // ---------------------------------------------------------------- stimulus
  initial begin
    bit h;
    logic [AW-1:0] a;
    int unsigned r;

    for (int s = 0; s < NS; s++)
      for (int w = 0; w < NW; w++) begin mv[s][w] = 0; mts[s][w] = 0; mt[s][w] = '0; end

    c_addr = '0; c_req = 1'b0; arst_n = 1'b0;
    repeat (4) @(posedge clk);
    arst_n = 1'b1;
    repeat (2) @(posedge clk);
    #1;

    // ---- directed LRU test on set 0 ----
    if (NW > 1) begin
      for (int t = 0; t < NW; t++) expect_hit(mk_addr(t, 0, 0), 1'b0, "cold fill");
      expect_hit(mk_addr(0, 0, 3), 1'b1, "tag0 still resident (same line, other byte)");
      expect_hit(mk_addr(NW, 0, 0), 1'b0, "new tag causes eviction");
      expect_hit(mk_addr(0, 0, 0), 1'b1, "tag0 was MRU so must survive");
      expect_hit(mk_addr(1, 0, 0), 1'b0, "tag1 was LRU so must be evicted");
    end

    // ---- same line, every offset ----
    for (int o = 0; o < LINE_BYTES; o++) begin
      do_read(mk_addr(5, (NS > 1) ? 1 : 0, o), h);
    end

    // ---- locality-heavy random workload ----
    // Reuse two tags per set (well below the default four-way capacity),
    // while varying byte offsets. Keep a small fraction of fully random
    // accesses to exercise misses and replacement under noise.
    for (int i = 0; i < N_RANDOM; i++) begin
      r = $urandom_range(0, 99);
      if (r < 95) begin
        a = mk_addr($urandom_range(0, 1),
                    $urandom_range(0, NS - 1),
                    $urandom_range(0, LINE_BYTES - 1));
      end else begin
        a = AW'($urandom());
      end
      do_read(a, h);
      if ($urandom_range(0, 3) == 0) begin
        repeat ($urandom_range(1, 3)) @(posedge clk);
        #1;
      end
    end

    repeat (5) @(posedge clk);
    $display("------------------------------------------------------------");
    $display("reads=%0d hits=%0d misses=%0d refills=%0d", n_hit + n_miss, n_hit, n_miss, refill_cnt);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED : %0d errors", errors);
    $finish;
  end

  initial begin
    #100_000_000;
    $display("TEST FAILED : timeout");
    $finish;
  end

endmodule
