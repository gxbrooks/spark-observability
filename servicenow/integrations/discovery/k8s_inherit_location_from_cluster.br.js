(function executeRule(current, previous /*null on insert*/) {
  if (!current.location.nil()) {
    return;
  }
  if (current.cluster.nil()) {
    return;
  }
  var cluster = current.cluster.getRefRecord();
  if (cluster.nil() || cluster.location.nil()) {
    return;
  }
  current.location = cluster.location;
})(current, previous);
