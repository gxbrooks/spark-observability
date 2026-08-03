(function executeRule(current, previous /*null on insert*/) {
  // DISABLED by design: CI must bind correctly on first insert (event BR /
  // alert BR). Propagation was a temporary safety net for race conditions.
  // Kept inactive for reference; do not re-enable without revisiting generic
  // entity bind ordering.
})(current, previous);
