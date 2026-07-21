(function executeRule(current, previous /*null on insert*/) {
  var resolver = new ResolveApplicationService();
  if (resolver.applySparkClientAlertBinding(current)) {
    return;
  }

  var binder = new K8sLogPodCiBind();
  binder.applyPodBinding(current);
})(current, previous);
