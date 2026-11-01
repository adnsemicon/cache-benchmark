//==============================================================================
// simple_cache_tb : self-checking testbench for simple_cache
//------------------------------------------------------------------------------
// Checking strategy
//   * Data    : every granted read is compared against an address-derived
//               memory pattern (what a flat memory would return).
//   * Hit/miss: an independent tree-PLRU reference model predicts
//               whether each read hits; the DUT's refill count must agree.
//   * Protocol: line-aligned and stable m_addr_o, m_req_o held until m_gnt_i,
//               m_addr_o equals the requested line, no c_gnt_o without c_req_o,
//               bounded response time, and zero-wait-state hits.
//
// Test phases
//   1 directed : PLRU eviction order
//   2 directed : every byte offset of a line
//   3 stream   : sequential words over twice the cache capacity
//   4 thrash   : cyclic access to NW+1 tags in one set
//   5 locality : two hot tags per set, 5 % random noise
//   6 mixed    : working set of 2*CL lines plus fully random addresses
//   7 reset    : asynchronous reset must invalidate every line
//
// Runtime options (plusargs)
//   +SEED=<n>      random seed                      (default 1)
//   +N_RANDOM=<n>  transactions per random phase    (default N_RANDOM param)
//   +MAX_LAT=<n>   max memory grant latency, cycles (default MAX_LAT param)
//   +VERBOSE       print one line per read
//
// Exit status: non-zero ($fatal) if any check fails.
//==============================================================================
module simple_cache_tb;

  //----------------------------------------------------------------------------
  // Configuration
  //----------------------------------------------------------------------------
  parameter int AW       = 16;
  parameter int C_DW     = 8;
  parameter int M_DW     = 128;
  parameter int CL       = 512;
  parameter int NW       = 4;
  parameter int N_RANDOM = 24429;
  parameter int MAX_LAT  = 3;

  // Design contract: a hit is granted in the same cycle as the request.
  // Set to 0 if the DUT is changed to use synchronous (SRAM) arrays.
  localparam bit EXPECT_ZERO_WAIT_HIT = 1'b1;

  localparam int NS         = CL / NW;
  localparam int OFFSET_W   = $clog2(M_DW / 8);
  localparam int IDX_W      = $clog2(NS);
  localparam int IDX_WD     = (IDX_W > 0) ? IDX_W : 1;
  localparam int TAG_W      = AW - IDX_W - OFFSET_W;
  localparam int LINE_BYTES = M_DW / 8;
  localparam int WORD_BYTES = C_DW / 8;

  localparam int CLK_PERIOD  = 10;
  localparam int MAX_PRINT   = 20;     // errors printed in full
  localparam int ABORT_AFTER = 100;    // abort run after this many errors

  // Runtime options
  int unsigned seed     = 1;
  int          n_random = N_RANDOM;
  int          max_lat  = MAX_LAT;
  bit          verbose  = 1'b0;

  //----------------------------------------------------------------------------
  // Clock, DUT
  //----------------------------------------------------------------------------
  logic            clk    = 1'b0;
  logic            arst_n = 1'b0;
  logic [AW-1:0]   c_addr = '0;
  logic            c_req  = 1'b0;
  logic [C_DW-1:0] c_data;
  logic            c_gnt;
  logic [AW-1:0]   m_addr;
  logic            m_req;
  logic [M_DW-1:0] m_data;
  logic            m_gnt;

  always #(CLK_PERIOD / 2) clk = ~clk;

  simple_cache #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) dut (
    .arst_ni (arst_n), .clk_i (clk),
    .c_addr_i(c_addr), .c_req_i(c_req), .c_data_o(c_data), .c_gnt_o(c_gnt),
    .m_addr_o(m_addr), .m_req_o(m_req), .m_data_i(m_data), .m_gnt_i(m_gnt)
  );

  //----------------------------------------------------------------------------
  // Error reporting
  //----------------------------------------------------------------------------
  int    errors     = 0;
  int    corrupt_cnt = 0;
  int    misaligned_cnt = 0;
  string phase_name = "init";

  task automatic report_error(input string msg);
    errors++;
    if (errors <= MAX_PRINT)
      $display("[%0t] ERROR [%s]: %s", $time, phase_name, msg);
    if (errors == MAX_PRINT)
      $display("[%0t] further errors suppressed", $time);
    if (errors >= ABORT_AFTER)
      $fatal(1, "simple_cache_tb: aborting after %0d errors", errors);
  endtask

  //----------------------------------------------------------------------------
  // Memory model (address-derived pattern, random grant latency)
  //----------------------------------------------------------------------------
  function automatic logic [7:0] mem_byte(input logic [AW-1:0] a);
    logic [31:0] t;
    t = 32'(a) * 37 + (32'(a) >> 8) * 11 + 5;
    return t[7:0] ^ 8'hA5;
  endfunction

  function automatic logic [AW-1:0] line_base(input logic [AW-1:0] a);
    return {a[AW-1:OFFSET_W], {OFFSET_W{1'b0}}};
  endfunction

  function automatic logic [M_DW-1:0] line_at(input logic [AW-1:0] a);
    logic [AW-1:0] base;
    base = line_base(a);
    for (int i = 0; i < LINE_BYTES; i++) line_at[i*8 +: 8] = mem_byte(base + AW'(i));
  endfunction

  // Expected C_DW word for a byte address (word containing that byte)
  function automatic logic [C_DW-1:0] exp_word(input logic [AW-1:0] a);
    logic [AW-1:0] base;
    base = a & ~AW'(WORD_BYTES - 1);
    for (int k = 0; k < WORD_BYTES; k++) exp_word[k*8 +: 8] = mem_byte(base + AW'(k));
  endfunction

  int lat = 0;
  always @(posedge clk) begin
    if (!m_req)        lat <= $urandom_range(0, max_lat);
    else if (lat != 0) lat <= lat - 1;
  end
  assign m_gnt  = m_req && (lat == 0);
  assign m_data = line_at(m_addr);

  //----------------------------------------------------------------------------
  // Protocol monitor
  //----------------------------------------------------------------------------
  int            refill_cnt  = 0;
  logic [AW-1:0] cur_addr    = '0;     // request currently driven by the test
  bit            cur_valid   = 1'b0;
  logic [AW-1:0] m_addr_prev = '0;
  bit            m_pend_prev = 1'b0;

  always @(posedge clk) begin
    if (arst_n) begin
      if (m_req && m_gnt) refill_cnt <= refill_cnt + 1;

      if (m_req) begin
        if (m_addr[OFFSET_W-1:0] != '0) begin
          misaligned_cnt++;
          report_error($sformatf("m_addr not line aligned: %h", m_addr));
        end
        if (cur_valid && (m_addr != line_base(cur_addr)))
          report_error($sformatf("m_addr %h is not the line of request %h", m_addr, cur_addr));
      end

      if (m_pend_prev) begin
        if (!m_req)
          report_error("m_req dropped before m_gnt");
        else if (m_addr != m_addr_prev)
          report_error("m_addr changed while request pending");
      end

      if (c_gnt && !c_req)
        report_error("c_gnt asserted without c_req");

      m_pend_prev <= m_req && !m_gnt;
      m_addr_prev <= m_addr;
    end
  end

  //----------------------------------------------------------------------------
  // Reference model: tree-PLRU, independent of the DUT replacement state.
  //----------------------------------------------------------------------------
  bit               mv  [NS][NW];
  logic [TAG_W-1:0] mt  [NS][NW];
  localparam int PLRU_LEVELS = (NW > 1) ? $clog2(NW) : 0;
  localparam int PLRU_LEAVES = 2 ** PLRU_LEVELS;
  localparam int PLRU_NODES = (PLRU_LEAVES > 1) ? PLRU_LEAVES - 1 : 1;
  bit               model_plru [NS][PLRU_NODES];
  bit               model_evicted;

  function automatic int set_of(input logic [AW-1:0] a);
    if (IDX_W > 0) return int'(a[OFFSET_W +: IDX_WD]);
    return 0;
  endfunction

  task automatic clear_model();
    for (int s = 0; s < NS; s++)
      for (int w = 0; w < NW; w++) begin
        mv[s][w] = 1'b0;
        mt[s][w] = '0;
      end
    for (int s = 0; s < NS; s++)
      for (int n = 0; n < PLRU_NODES; n++) model_plru[s][n] = 1'b0;
  endtask

  // Update the tree on the accessed way, as the DUT does on its grant.
  function automatic bit model_access(input logic [AW-1:0] a);
    int s, victim, node, start_way, span, right_start, way_span, branch;
    logic [TAG_W-1:0] t;
    s = set_of(a);
    t = a[AW-1 -: TAG_W];
    model_evicted = 1'b0;
    for (int w = 0; w < NW; w++) begin
      if (mv[s][w] && mt[s][w] == t) begin
        if (NW > 1) begin
          node = 0;
          way_span = PLRU_LEAVES;
          for (int level = 0; level < PLRU_LEVELS; level++) begin
            way_span = way_span / 2;
            branch = (w / way_span) % 2;
            model_plru[s][node] = (branch == 0);
            node = 2 * node + 1 + branch;
          end
        end
        return 1'b1;
      end
    end
    victim = -1;
    for (int w = 0; w < NW; w++)
      if (!mv[s][w]) begin victim = w; break; end
    if (victim < 0) begin
      model_evicted = 1'b1;
      node = 0;
      start_way = 0;
      span = PLRU_LEAVES;
      for (int level = 0; level < PLRU_LEVELS; level++) begin
        span = span / 2;
        right_start = start_way + span;
        if (right_start >= NW || !model_plru[s][node]) begin
          node = 2 * node + 1;
        end else begin
          node = 2 * node + 2;
          start_way = right_start;
        end
      end
      victim = start_way;
    end
    mv[s][victim] = 1'b1;
    mt[s][victim] = t;
    // A refilled line is granted on the controller's retry cycle.
    if (NW > 1) begin
      node = 0;
      way_span = PLRU_LEAVES;
      for (int level = 0; level < PLRU_LEVELS; level++) begin
        way_span = way_span / 2;
        branch = (victim / way_span) % 2;
        model_plru[s][node] = (branch == 0);
        node = 2 * node + 1 + branch;
      end
    end
    return 1'b0;
  endfunction

  //----------------------------------------------------------------------------
  // Statistics and functional coverage
  //----------------------------------------------------------------------------
  int tot_reads = 0, tot_hits = 0, tot_miss = 0, tot_evict = 0;
  int ph_reads, ph_hits, ph_miss, ph_evict, ph_err0;
  int planned_reads = 0, progress_step = 1, next_progress = 1, last_progress = 0;
  bit set_seen [NS];
  bit off_seen [LINE_BYTES];
  int hit_lat_min  = 32'h7fffffff, hit_lat_max  = 0;
  int miss_lat_min = 32'h7fffffff, miss_lat_max = 0;

  task automatic begin_phase(input string name);
    phase_name = name;
    ph_reads = 0; ph_hits = 0; ph_miss = 0; ph_evict = 0; ph_err0 = errors;
  endtask

  task automatic end_phase();
    // Phase details are summarized by the progress and final counters.
  endtask

  //----------------------------------------------------------------------------
  // Driver tasks (drive 1 ns after a clock edge, sample at the edge)
  //----------------------------------------------------------------------------
  task automatic apply_reset();
    c_req     = 1'b0;
    cur_valid = 1'b0;
    arst_n    = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    arst_n = 1'b1;
    clear_model();
    @(posedge clk);
    #1;
  endtask

  task automatic do_read(input logic [AW-1:0] a, output bit was_hit);
    bit              exp_hit;
    bit              got_gnt;
    logic [C_DW-1:0] got_data;
    int              cnt_before;
    int              cycles;

    exp_hit    = model_access(a);
    cnt_before = refill_cnt;
    cur_addr   = a;
    cur_valid  = 1'b1;
    c_addr     = a;
    c_req      = 1'b1;
    cycles     = 0;

    do begin
      @(posedge clk);
      cycles++;
      got_gnt  = c_gnt;
      got_data = c_data;
      if (cycles > 1000 + max_lat)
        $fatal(1, "simple_cache_tb: timeout waiting for c_gnt (addr=%h, phase=%s)", a, phase_name);
    end while (!got_gnt);

    if (got_data !== exp_word(a)) begin
      corrupt_cnt++;
      report_error($sformatf("data mismatch addr=%h got=%h exp=%h", a, got_data, exp_word(a)));
    end

    was_hit = (refill_cnt == cnt_before);
    if (was_hit !== exp_hit)
      report_error($sformatf("hit/miss mismatch addr=%h dut_hit=%0d model_hit=%0d", a, was_hit, exp_hit));
    if (refill_cnt - cnt_before > 1)
      report_error("more than one refill for a single read");
    if (was_hit && EXPECT_ZERO_WAIT_HIT && cycles != 1)
      report_error($sformatf("hit took %0d cycles (expected same-cycle grant)", cycles));

    // statistics
    ph_reads++;  tot_reads++;
    if (was_hit) begin
      ph_hits++; tot_hits++;
      if (cycles < hit_lat_min) hit_lat_min = cycles;
      if (cycles > hit_lat_max) hit_lat_max = cycles;
    end else begin
      ph_miss++; tot_miss++;
      if (cycles < miss_lat_min) miss_lat_min = cycles;
      if (cycles > miss_lat_max) miss_lat_max = cycles;
    end
    if (model_evicted) begin ph_evict++; tot_evict++; end
    set_seen[set_of(a)]       = 1'b1;
    off_seen[a[OFFSET_W-1:0]] = 1'b1;
    while (next_progress <= tot_reads && next_progress <= planned_reads) begin
      $display("Progress: %0d / %0d", next_progress, planned_reads);
      last_progress = next_progress;
      next_progress += progress_step;
    end
    if (tot_reads == planned_reads && last_progress != planned_reads) begin
      $display("Progress: %0d / %0d", planned_reads, planned_reads);
      last_progress = planned_reads;
    end
    if (verbose)
      $display("[%0t] RD %h -> %s (%0d cyc)", $time, a, was_hit ? "HIT " : "MISS", cycles);

    #1;
    c_req     = 1'b0;
    cur_valid = 1'b0;
  endtask

  function automatic logic [AW-1:0] mk_addr(input int tag, input int set, input int off);
    logic [AW-1:0] a;
    a = '0;
    a[AW-1 -: TAG_W] = TAG_W'(tag);
    if (IDX_W > 0) a[OFFSET_W +: IDX_WD] = IDX_WD'(set);
    a[OFFSET_W-1:0] = OFFSET_W'(off);
    return a;
  endfunction

  task automatic expect_hit(input logic [AW-1:0] a, input bit exp_h, input string msg);
    bit h;
    do_read(a, h);
    if (h !== exp_h)
      report_error($sformatf("%s: expected %s", msg, exp_h ? "HIT" : "MISS"));
  endtask

  task automatic maybe_gap(input int pct);
    if ($urandom_range(0, 99) < pct) begin
      repeat ($urandom_range(1, 3)) @(posedge clk);
      #1;
    end
  endtask

  //----------------------------------------------------------------------------
  // Test phases
  //----------------------------------------------------------------------------
  task automatic phase_plru_order();
    bit h;
    begin_phase("1 directed: PLRU order");
    if (NW > 1) begin
      for (int t = 0; t < NW; t++) expect_hit(mk_addr(t, 0, 0), 1'b0, "cold fill");
      expect_hit(mk_addr(0, 0, 3),  1'b1, "same line, other byte, must hit");
      expect_hit(mk_addr(NW, 0, 0), 1'b0, "new tag must evict");
      if (NW == 4) begin
        expect_hit(mk_addr(0, 0, 0), 1'b1, "tag0 survives PLRU replacement");
        expect_hit(mk_addr(1, 0, 0), 1'b1, "tag1 survives PLRU replacement");
      end else begin
        do_read(mk_addr(0, 0, 0), h);
        do_read(mk_addr(1, 0, 0), h);
      end
    end
    end_phase();
  endtask

  task automatic phase_offsets();
    bit h;
    int s;
    begin_phase("2 directed: byte offsets");
    s = (NS > 1) ? 1 : 0;
    for (int o = 0; o < LINE_BYTES; o++)     do_read(mk_addr(5, s, o), h);
    for (int o = LINE_BYTES - 1; o >= 0; o--) do_read(mk_addr(5, s, o), h);
    end_phase();
  endtask

  task automatic phase_stream();
    bit h;
    begin_phase("3 stream: sequential words");
    for (int i = 0; i < 2 * CL * (LINE_BYTES / WORD_BYTES); i++)
      do_read(AW'(i * WORD_BYTES), h);
    end_phase();
  endtask

  task automatic phase_thrash();
    bit h;
    int s;
    begin_phase("4 thrash: NW+1 tags, one set");
    s = (NS > 1) ? NS - 1 : 0;
    for (int i = 0; i < 50 * (NW + 1); i++)
      do_read(mk_addr(i % (NW + 1), s, 0), h);
    end_phase();
  endtask

  task automatic phase_locality();
    bit h;
    logic [AW-1:0] a;
    begin_phase("5 random: locality heavy");
    for (int i = 0; i < n_random; i++) begin
      if ($urandom_range(0, 99) < 95)
        a = mk_addr($urandom_range(0, 1), $urandom_range(0, NS - 1),
                    $urandom_range(0, LINE_BYTES - 1));
      else
        a = AW'($urandom());
      do_read(a, h);
      maybe_gap(25);
    end
    end_phase();
  endtask

  task automatic phase_mixed();
    bit h;
    logic [AW-1:0] a;
    begin_phase("6 random: mixed working set");
    for (int i = 0; i < n_random; i++) begin
      if ($urandom_range(0, 99) < 70)
        a = AW'(($urandom_range(0, CL * 2 - 1) << OFFSET_W) | $urandom_range(0, LINE_BYTES - 1));
      else
        a = AW'($urandom());
      do_read(a, h);
      maybe_gap(25);
    end
    end_phase();
  endtask

  task automatic phase_reset();
    bit h;
    begin_phase("7 reset: invalidates lines");
    do_read(mk_addr(1, 0, 0), h);
    expect_hit(mk_addr(1, 0, 1), 1'b1, "line resident before reset");
    apply_reset();
    expect_hit(mk_addr(1, 0, 0), 1'b0, "reset must clear valid bits");
    expect_hit(mk_addr(1, 0, 1), 1'b1, "line resident again after refill");
    end_phase();
  endtask

  //----------------------------------------------------------------------------
  // Final report
  //----------------------------------------------------------------------------
  task automatic final_report();
    $display("[+]       HITS : %0d", tot_hits);
    $display("[-]     MISSES : %0d", tot_miss);
    $display("[-]    CORRUPT : %0d", corrupt_cnt);
    $display("[-] MISALIGNED : %0d", misaligned_cnt);
    $display(">>> Overall Score : %0d", tot_hits);
    if (errors != 0) begin
      $fatal(1, "simple_cache_tb: %0d check(s) failed", errors);
    end
  endtask

  //----------------------------------------------------------------------------
  // Main sequence
  //----------------------------------------------------------------------------
  initial begin : main
    int unsigned seed_value;
    if ($value$plusargs("SEED=%d", seed))         ;
    if ($value$plusargs("N_RANDOM=%d", n_random)) ;
    if ($value$plusargs("MAX_LAT=%d", max_lat))   ;
    if ($test$plusargs("VERBOSE"))                verbose = 1'b1;
    seed_value = $urandom(seed);

    planned_reads = ((NW > 1) ? NW + 4 : 0)
                  + 2 * LINE_BYTES
                  + 2 * CL * (LINE_BYTES / WORD_BYTES)
                  + 50 * (NW + 1)
                  + 2 * n_random
                  + 4;
    progress_step = (planned_reads + 7) / 8;
    if (progress_step < 1) progress_step = 1;
    next_progress = progress_step;
    $display("Progress: 0 / %0d", planned_reads);

    for (int s = 0; s < NS; s++)         set_seen[s] = 1'b0;
    for (int o = 0; o < LINE_BYTES; o++) off_seen[o] = 1'b0;
    clear_model();

    apply_reset();
    phase_plru_order();
    phase_offsets();
    phase_stream();
    phase_thrash();
    phase_locality();
    phase_mixed();
    phase_reset();

    repeat (5) @(posedge clk);
    final_report();
    $finish;
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * 100_000_000);
    $fatal(1, "simple_cache_tb: global timeout");
  end

endmodule
