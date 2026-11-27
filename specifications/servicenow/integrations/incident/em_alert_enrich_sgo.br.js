(function executeRule(current, previous /*null on insert*/) {
  // Initial brooks-lab alert processing (order 90, before create BR). Same enrichment as
  // em-event-enrich-sgo so alerts created without the event's stamped keys still get sn-* and
  // K8s CI. Keys on the brooks-lab connector class (BrooksLabConnector), not on alert source,
  // and gives a group alert our class when this alert joins one.
  try {
    var connector = new BrooksLabConnector();
    if (!connector.isOurRecord(current)) {
      return;
    }
    new ResolveApplicationService().enrichSgoRecord(current);
    connector.stampGroupOf(current);
  } catch (e) {
    gs.error('em-alert-enrich-sgo: ' + e);
  }
})(current, previous);
