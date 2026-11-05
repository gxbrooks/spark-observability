(function executeRule(current, previous /*null on insert*/) {
  // Initial SGO-Dynatrace event processing: stamp sn-impact / sn-urgency
  // when Dynatrace omitted them, copy K8s dash-key aliases, bind workload
  // CI from k8s-workload-name (not a resurrected bind BR).
  if (String(current.source) !== 'SGO-Dynatrace') {
    return;
  }
  try {
    new ResolveApplicationService().enrichSgoRecord(current);
  } catch (e) {
    gs.error('em-event-enrich-sgo: ' + e);
  }
})(current, previous);
