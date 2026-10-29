module tb_check #(
  parameter int AW   = 16,
  parameter int C_DW = 8,
  parameter int M_DW = 128,
  parameter int CL   = 256,
  parameter int NW   = 4,
  parameter int N    = 60000
);
  localparam int LB = M_DW/8;
  localparam int CB = C_DW/8;

  logic clk = 0, arst_n = 0;
  always #5 clk = ~clk;

  logic [AW-1:0]   c_addr; logic c_req; logic [C_DW-1:0] c_data; logic c_gnt;
  logic [AW-1:0]   m_addr; logic m_req; logic [M_DW-1:0] m_data; logic m_gnt;

  simple_cache #(.AW(AW), .C_DW(C_DW), .M_DW(M_DW), .CL(CL), .NW(NW)) dut (
    .arst_ni(arst_n), .clk_i(clk),
    .c_addr_i(c_addr), .c_req_i(c_req), .c_data_o(c_data), .c_gnt_o(c_gnt),
    .m_addr_o(m_addr), .m_req_o(m_req), .m_data_i(m_data), .m_gnt_i(m_gnt));

  // ---------------- reference memory ----------------
  function automatic logic [7:0] mem_byte(input logic [AW-1:0] a);
    mem_byte = 8'((a * 37) ^ (a >> 5) ^ (a >> 11) ^ 13);
  endfunction

  function automatic logic [M_DW-1:0] line_of(input logic [AW-1:0] a);
    logic [AW-1:0] base;
    logic [M_DW-1:0] l;
    base = a & ~AW'(LB-1);
    for (int i = 0; i < LB; i++) l[i*8 +: 8] = mem_byte(base + AW'(i));
    return l;
  endfunction

  function automatic logic [C_DW-1:0] expected(input logic [AW-1:0] a);
    logic [C_DW-1:0] e;
    for (int i = 0; i < CB; i++) e[i*8 +: 8] = mem_byte(a + AW'(i));
    return e;
  endfunction

  // private RNGs so the stimulus does NOT depend on DUT timing
  int unsigned rs_stim = 32'h2545F491;
  int unsigned rs_mem  = 32'h9E3779B9;
  function automatic int unsigned rnd();
    rs_stim ^= rs_stim << 13; rs_stim ^= rs_stim >> 17; rs_stim ^= rs_stim << 5;
    return rs_stim;
  endfunction
  function automatic int unsigned rnd_mem();
    rs_mem ^= rs_mem << 13; rs_mem ^= rs_mem >> 17; rs_mem ^= rs_mem << 5;
    return rs_mem;
  endfunction

  // ---------------- memory model (random latency, req must be held) ----------------
  int unsigned wait_cnt = 0, lat_q = 0;
  assign m_data = line_of(m_addr);
  assign m_gnt  = m_req && (wait_cnt >= lat_q);
  always @(posedge clk) begin
    if (m_req && !m_gnt) wait_cnt <= wait_cnt + 1;
    else begin wait_cnt <= 0; lat_q <= rnd_mem() % 4; end
  end

  // ---------------- protocol monitors ----------------
  int unsigned proto_err = 0;
  logic prev_m_req = 0, prev_m_gnt = 0;
  always @(negedge clk) if (arst_n) begin
    if (prev_m_req && !prev_m_gnt && !m_req) begin
      proto_err++; $display("[%0t] PROTO: m_req dropped before m_gnt", $time);
    end
    if (m_req && (m_addr & AW'(LB-1)) != 0) begin
      proto_err++; $display("[%0t] PROTO: m_addr not line aligned", $time);
    end
    if (m_req && !c_req) begin
      proto_err++; $display("[%0t] PROTO: m_req with no CPU request pending", $time);
    end
    if (c_gnt && !c_req) begin
      proto_err++; $display("[%0t] PROTO: spurious c_gnt (no request)", $time);
    end
    prev_m_req <= m_req; prev_m_gnt <= m_gnt;
  end

`ifdef TRACE
  always @(posedge clk) if ($time < 400)
    $display("[%0t] req=%b addr=%h gnt=%b state=%0d m_req=%b m_gnt=%b", $time, c_req, c_addr, c_gnt, dut.state, m_req, m_gnt);
`endif
  // ---------------- stimulus ----------------
  int unsigned total = 0, hits = 0, corrupt = 0, misaligned = 0, timeouts = 0;
  int unsigned lat_sum = 0;
  int mode = 0;
  localparam int NMODE = 6;                       // 0..4 = generated patterns, 5 = trace file
  int unsigned p_total [NMODE];
  int unsigned p_hits  [NMODE];
  int unsigned p_err   [NMODE];
  string mode_name [NMODE] = '{"wide random      ", "8 regions (random)", "hot set (64 lines)",
                               "same-set conflict ", "sequential walk  ", "trace file        "};
  logic [AW-1:0] trace_mem [0:199999];
  int trace_n = 0;

  function automatic logic [AW-1:0] pick_addr();
    logic [AW-1:0] a;
    int unsigned r;
    int OFFB = $clog2(LB);
    int IDXB = $clog2(CL/NW);
    case (mode)
      0: a = AW'(rnd());                                   // wide random
      1: a = AW'((rnd() % 8) * 4096 + (rnd() % 4096)); // 8 regions
      2: a = AW'((rnd() % 64) * LB + (rnd() % LB));    // hot working set
      3: begin                                                   // conflict: same index, many tags
           a = AW'(((rnd() % (NW+6)) << (OFFB+IDXB)) | (3 << OFFB) | (rnd() % LB));
         end
      default: begin                                              // sequential walk
           static logic [AW-1:0] seq = 0;
           seq = seq + AW'(1 + (rnd() % 3));
           a = seq;
         end
    endcase
    return a & ~AW'(CB-1);                                      // C_DW-aligned request
  endfunction

  initial begin
    logic [AW-1:0] a;
    int cur_mode;
    int unsigned gap, cyc;
    bit seen_m;
    begin
      string fname; int fd, rc; int unsigned v;
      if ($value$plusargs("trace=%s", fname)) begin
        fd = $fopen(fname, "r");
        while (!$feof(fd)) begin
          rc = $fscanf(fd, "%h\n", v);
          if (rc == 1) begin trace_mem[trace_n] = AW'(v); trace_n++; end
        end
        $fclose(fd);
      end
    end
    c_req = 0; c_addr = 'x;
    repeat (4) @(posedge clk);
    #1 arst_n = 1;
    repeat (2) @(posedge clk);
    #1;

    for (int n = 0; n < ((trace_n > 0) ? trace_n : N); n++) begin
      if (n % 400 == 0) mode = rnd() % 5;
      // idle gap (garbage address while req low)
      gap = rnd() % 4;
      if ((n % 3) == 0) gap = 0;               // plenty of back-to-back traffic
      repeat (gap) begin
        c_req = 0; c_addr = AW'(rnd());
        @(posedge clk); #1;
      end
      cur_mode = (trace_n > 0) ? 5 : mode;
      a = (trace_n > 0) ? trace_mem[n] : pick_addr();
      c_req = 1; c_addr = a;                   // changes 1ns after a posedge
      cyc = 0; seen_m = 0;
      forever begin
        @(negedge clk);                        // sample mid-cycle (stable)
        cyc++;
        if (m_req) seen_m = 1;
        if (c_gnt) begin
          total++;
          p_total[cur_mode]++;
          if (!seen_m) begin hits++; p_hits[cur_mode]++; end
          lat_sum += cyc;
          if (c_data !== expected(a)) begin
            // wrong byte from the right line => misaligned, otherwise corruption
            logic [M_DW-1:0] l = line_of(a);
            bit found = 0;
            for (int i = 0; i < LB; i += CB)
              if (c_data === l[i*8 +: C_DW]) found = 1;
            if (found) misaligned++; else corrupt++;
            p_err[cur_mode]++;
            if (corrupt + misaligned <= 5)
              $display("[%0t] DATA MISMATCH addr=%h got=%h exp=%h", $time, a, c_data, expected(a));
          end
          break;
        end
        if (cyc > 300) begin
          timeouts++; $display("[%0t] TIMEOUT addr=%h", $time, a);
          break;
        end
      end
      @(posedge clk); #1;                      // req stays high until the end of the gnt cycle
      if (timeouts >= 3) break;
    end
    c_req = 0;
    repeat (4) @(posedge clk);
    $display("--------------------------------------------");
    $display("%-18s %8s %8s %8s %7s %6s", "pattern", "requests", "hits", "misses", "hit%", "errors");
    for (int m = 0; m < NMODE; m++)
      if (p_total[m] != 0)
        $display("%-18s %8d %8d %8d %6.2f%% %6d", mode_name[m], p_total[m], p_hits[m],
                 p_total[m]-p_hits[m], 100.0*p_hits[m]/p_total[m], p_err[m]);
    $display("--------------------------------------------");
    $display("TOTAL requests=%0d  hits=%0d  misses=%0d  hit-rate=%0.2f%%", total, hits, total-hits,
             100.0*hits/(total==0?1:total));
    $display("corruption=%0d  misaligned=%0d  timeouts=%0d  proto_err=%0d", corrupt, misaligned, timeouts, proto_err);
    $display("avg latency (cycles) = %0.2f", 1.0*lat_sum/(total==0?1:total));
    $display("SCORE = Hits - Corruption - Misaligned = %0d - %0d - %0d = %0d",
             hits, corrupt, misaligned, int'(hits) - int'(corrupt) - int'(misaligned));
    $finish;
  end
endmodule