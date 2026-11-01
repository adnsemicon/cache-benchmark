package cache_pkg;

  // Safe width helper: $clog2(1) is zero, but packed vectors need >= 1 bit.
  function automatic integer clog2_safe(input integer value);
    if (value <= 1) clog2_safe = 1;
    else            clog2_safe = $clog2(value);
  endfunction

  typedef enum logic [1:0] {
    ARC_T1 = 2'b00, // recently seen once
    ARC_T2 = 2'b01  // seen repeatedly
  } arc_list_e;

endpackage