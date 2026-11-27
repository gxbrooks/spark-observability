(function executeRule(current, previous /*null when async*/) {
  // brooks-lab alert just got its incident (from the brooks-lab alert management rule):
  // resolve CI -> service instance / dynamic CI group -> offering -> service and write the
  // incident's service_offering and business_service (FindService). Alerts from other
  // connectors are left alone (BrooksLabConnector: event_class marker).
  try {
    if (!new BrooksLabConnector().isOurRecord(current)) {
      return;
    }
    var incident = new GlideRecord('incident');
    if (!incident.get(current.getValue('incident'))) {
      return;
    }
    new FindService().resolveServiceForAlert(current, incident);
  } catch (e) {
    gs.error('em-alert-find-service: ' + e);
  }
})(current, previous);
