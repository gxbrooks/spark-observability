(function executeRule(current, previous /*null on insert*/) {
  if (!current.location.nil()) {
    return;
  }
  var host = current.host.getRefRecord();
  if (!host.nil() && !host.location.nil()) {
    current.location = host.location;
  }
})(current, previous);
