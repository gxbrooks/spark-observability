(function executeRule(current, previous /*null on insert*/) {
  // Initial SGO-Dynatrace alert processing (order 5000, before create BR).
  // Same enrichment as em-event-enrich-sgo so alerts that SGO copies
  // without the event's stamped keys still get sn-* and K8s CI.
  if (String(current.source) !== 'SGO-Dynatrace') {
    return;
  }
  try {
    new ResolveApplicationService().enrichSgoRecord(current);
  } catch (e) {
    gs.error('em-alert-enrich-sgo: ' + e);
  }
})(current, previous);
