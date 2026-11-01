// -----------------------------------------------------------------------------
// simple_cache_pkg : shared types and helper functions for simple_cache.
// Compile this file FIRST. Per-instance values (widths derived from AW, NW ...)
// are NOT stored here - they are computed in the top module and passed down as
// parameters.
// -----------------------------------------------------------------------------
package simple_cache_pkg;

  // Control FSM states
  typedef enum logic {S_IDLE, S_REFILL} state_e;

  // clog2 that never returns 0, so zero-width vectors (1 set / 1 way) elaborate
  function automatic int unsigned clog2_min1(input int unsigned n);
    int unsigned c;
    c = $clog2(n);
    return (c < 1) ? 1 : c;
  endfunction

  function automatic bit is_pow2(input int unsigned n);
    return (n != 0) && ((n & (n - 1)) == 0);
  endfunction

  // Legal parameter combination check used by the top module
  function automatic bit params_legal(input int aw, input int c_dw, input int m_dw,
                                      input int cl,  input int nw);
    int off_w, idx_w;
    if (aw < 1)                                                   return 1'b0;
    if (!is_pow2(c_dw) || !is_pow2(m_dw) || !is_pow2(cl) || !is_pow2(nw)) return 1'b0;
    if ((c_dw < 8) || (m_dw < 16) || (m_dw < c_dw) || (cl < nw))  return 1'b0;
    off_w = $clog2(m_dw / 8);
    idx_w = $clog2(cl / nw);
    return ((aw - idx_w - off_w) >= 1);   // at least one tag bit
  endfunction

endpackage