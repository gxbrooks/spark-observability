(function executeRule(current, previous /*null on insert*/) {
  if (current.cmdb_ci.nil()) {
    return;
  }

  var binder = new K8sLogPodCiBind();
  binder.propagateEventToAlerts(current);
})(current, previous);
