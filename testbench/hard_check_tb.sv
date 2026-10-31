module hard_check_tb;

  //==================================================
  // Parameters
  //==================================================
  localparam int AW      = 16;
  localparam int C_DW    = 8;
  localparam int M_DW    = 128;
  localparam int CL      = 512;
  localparam int NW      = 4;
  localparam int VC_SIZE = 16;
  localparam int REPL    = 1;          // 0:LRU() 1:DRRIP() 2:PLRU() 3:BRRIP()


  localparam int LINE_BYTES  = M_DW / 8;
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int TOTAL_MEM   = 1 << AW;        // 64KB
  localparam int NUM_REQ     = 30000;

  //==================================================
  // Signals
  //==================================================
  logic             clk;
  logic             arst_n;

  logic [AW-1:0]    c_addr;
  logic             c_req;
  logic [C_DW-1:0]  c_data;
  logic             c_gnt;

  logic [AW-1:0]    m_addr;
  logic             m_req;
  logic [M_DW-1:0]  m_data;
  logic             m_gnt;

  //==================================================
  // DUT
  //==================================================
  simple_cache #(
    .AW(AW), .C_DW(C_DW), .M_DW(M_DW),
    .CL(CL), .NW(NW), .VC_SIZE(VC_SIZE),
    .REPL(REPL)     // BRRIP
  ) dut (
    .arst_ni(arst_n), .clk_i(clk),
    .c_addr_i(c_addr), .c_req_i(c_req),
    .c_data_o(c_data), .c_gnt_o(c_gnt),
    .m_addr_o(m_addr), .m_req_o(m_req),
    .m_data_i(m_data), .m_gnt_i(m_gnt)
  );

  //==================================================
  // Clock
  //==================================================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  //==================================================
  // Golden Memory
  //==================================================
  logic [7:0] mem [0:TOTAL_MEM-1];

  initial begin
    for (int i = 0; i < TOTAL_MEM; i++)
      mem[i] = $urandom_range(0,255);
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      m_gnt  <= 0;
      m_data <= '0;
    end else begin
      m_gnt <= 0;
      if (m_req) begin
        for (int b = 0; b < LINE_BYTES; b++)
          m_data[b*8 +: 8] <= mem[(m_addr + b) % TOTAL_MEM];
        m_gnt <= 1;
      end
    end
  end

  //==================================================
  // Counters
  //==================================================
  int hit_cnt=0, miss_cnt=0, corrupt_cnt=0, misalign_cnt=0;
  logic mem_was_req;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) mem_was_req <= 0;
    else begin
      if (m_req) mem_was_req <= 1;
      if (c_gnt) begin
        if (mem_was_req) miss_cnt++;
        else             hit_cnt++;
        mem_was_req <= 0;
      end
    end
  end

  //==================================================
  // HARD Workload (Official Trace Style)
  //==================================================
  initial begin
    $display("========================================");
    $display(" HARD Workload (Official-like) Started");
    $display("========================================");

    arst_n = 0;
    c_req  = 0;
    c_addr = 0;
    repeat(20) @(posedge clk);
    arst_n = 1;
    repeat(10) @(posedge clk);

    for (int i = 0; i < NUM_REQ; i++) begin
      logic [AW-1:0] addr;
      logic [C_DW-1:0] expected;

      // -------- Hard Pattern (very low locality) --------
      // 70% : Large random (almost whole memory)
      // 15% : Medium random
      // 10% : Long stride (no sequential)
      //  5% : Small hot (very little)
      randcase
        70: addr = $urandom_range(0, TOTAL_MEM-1);              // Full random
        15: addr = $urandom_range(0, 16384);                   // 16KB region
        10: addr = ((i * 64) + $urandom_range(0,15)) & (TOTAL_MEM-1); // stride
         5: addr = $urandom_range(0, 512);                     // tiny hot
      endcase

      // Force different line most of the time
      addr = (addr & ~(LINE_BYTES-1)) | $urandom_range(0, LINE_BYTES-1);

      expected = mem[addr];

      @(posedge clk);
      c_req  <= 1;
      c_addr <= addr;

      do @(posedge clk); while (!c_gnt);

      if (c_data !== expected) begin
        corrupt_cnt++;
        if (corrupt_cnt <= 8)
          $display("[CORRUPT] addr=0x%0h exp=%02h got=%02h", addr, expected, c_data);
      end

      c_req <= 0;

      if (i % 5000 == 0)
        $display("Progress: %0d / %0d", i, NUM_REQ);
    end

    //==================================================
    // Report
    //==================================================
    $display("\n========================================");
    $display("           FINAL REPORT (HARD)");
    $display("========================================");
    $display("Total Requests : %0d", NUM_REQ);
    $display("Hit            : %0d", hit_cnt);
    $display("Miss           : %0d", miss_cnt);
    $display("Corrupt        : %0d", corrupt_cnt);
    $display("Misaligned     : %0d", misalign_cnt);
    $display("----------------------------------------");
    $display("Hit Rate       : %0.2f%%", (hit_cnt * 100.0) / NUM_REQ);
    $display("Score          : %0d", hit_cnt - corrupt_cnt - misalign_cnt);
    $display("========================================\n");

    if (corrupt_cnt == 0) $display("DATA INTEGRITY : PASSED");
    else                  $display("DATA INTEGRITY : FAILED");

    $finish;
  end

  initial begin
    #200_000_000;
    $display("TIMEOUT");
    $finish;
  end

endmodule