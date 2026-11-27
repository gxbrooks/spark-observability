(function executeRule(current, previous /*null on insert*/) {
  // Initial brooks-lab event processing (SGO-Dynatrace receiver): stamp the brooks-lab connector
  // class (BrooksLabConnector; only events carrying our SGC ConnectionId), then stamp
  // sn-impact / sn-urgency when Dynatrace omitted them, copy K8s dash-key aliases, bind workload
  // CI from k8s-workload-name (not a resurrected bind BR).
  try {
    if (!new BrooksLabConnector().stampEvent(current)) {
      return;
    }
    new ResolveApplicationService().enrichSgoRecord(current);
  } catch (e) {
    gs.error('em-event-enrich-sgo: ' + e);
  }
})(current, previous);
