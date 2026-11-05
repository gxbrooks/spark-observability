(function executeRule(current, previous /*null on insert*/) {
  // AMR shim: same product path as Flow action "Create incident from Alert"
  // (EvtMgmtIncidentHandler → EvtMgmtCustomIncidentPopulator).
  // autoOpen=false: locateRule is not required while L2I AMR stays inactive
  // (OOTB Create Incident subflow skips the populator; do not activate it).
  // After-insert so alert.sys_id exists; always update when incident is set
  // (populator returns false on correlate but still sets alert.incident).
  //
  // Incident promotion only: BR filter is
  // source=SGO-Dynatrace^severity<=3^incidentISEMPTY (see ensure_em_alert_create_incident_br.yml).
  // Do not put severity<=3 on the EM Event → Ready rule — Warning (4) and
  // OK/clear (5) must still reach alert processing to open/close alerts.
  if (String(current.source) !== 'SGO-Dynatrace') {
    return;
  }
  if (!current.incident.nil()) {
    return;
  }
  try {
    EvtMgmtIncidentHandler.createIncidentNoUpdate(current, false);
    if (!current.incident.nil()) {
      current.setWorkflow(false);
      current.update();
    }
  } catch (e) {
    gs.error('em-alert-create-log-incident: ' + e);
  }
})(current, previous);
