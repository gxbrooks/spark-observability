var L2ICreateIncidentFromAlert = Class.create();
L2ICreateIncidentFromAlert.prototype = {
  initialize: function () {},
  type: 'L2ICreateIncidentFromAlert',
};

/**
 * Invoke the product Create-incident-from-alert path
 * (EvtMgmtIncidentHandler → EvtMgmtCustomIncidentPopulator).
 * Prefer AMR → Flow action "Create incident from Alert" in production.
 * autoOpen=false while L2I AMR is inactive (autoOpen requires em_alert_rule).
 */
L2ICreateIncidentFromAlert.fromAlert = function (alert) {
  if (!alert) {
    return false;
  }
  try {
    if (!alert.incident.nil()) {
      return true;
    }
    EvtMgmtIncidentHandler.createIncidentNoUpdate(alert, false);
    if (!alert.incident.nil()) {
      alert.setWorkflow(false);
      alert.update();
      return true;
    }
    return false;
  } catch (e) {
    gs.error('L2ICreateIncidentFromAlert.fromAlert: ' + e);
    return false;
  }
};
