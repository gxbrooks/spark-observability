(function executeRule(current, previous /*null on insert*/) {
  var binder = new K8sLogPodCiBind();
  binder.applyPodBinding(current);
})(current, previous);
