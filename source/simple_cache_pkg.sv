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

  // Legal parameter combination check used by the top module
  function automatic bit params_legal(input int aw, input int c_dw, input int m_dw,
                                      input int cl,  input int nw);
    if (aw < 1 || c_dw < 8 || m_dw < 8 || cl < 1 || nw < 1) return 1'b0;
    if ((c_dw % 8) != 0 || (m_dw % 8) != 0) return 1'b0;
    if ((m_dw < c_dw) || ((m_dw % c_dw) != 0)) return 1'b0;
    if ((cl < nw) || ((cl % nw) != 0)) return 1'b0;
    return 1'b1;
  endfunction

endpackage
