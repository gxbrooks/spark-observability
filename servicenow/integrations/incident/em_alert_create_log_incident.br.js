(function executeRule(current, previous /*null on insert*/) {
  if (current.source.toString() !== 'SGO-Dynatrace') {
    return;
  }

  var severity = parseInt(current.severity, 10);
  if (isNaN(severity) || severity > 3) {
    return;
  }

  var resolver = new ResolveApplicationService();

  // Prefer alert cmdb_ci; otherwise run the same generic entity bind as events.
  if (current.cmdb_ci.nil()) {
    var bind = resolver.applyEntityBinding(current);
    if (!bind.bound) {
      resolver.appendProcessingNote(
        current,
        'em-alert-create-log-incident: skipped incident create — no CI bound (' +
          (bind.note || 'unknown') +
          ')'
      );
      return;
    }
  }

  if (current.cmdb_ci.nil()) {
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: skipped incident create — cmdb_ci empty'
    );
    return;
  }

  var asSysId = current.cmdb_ci.toString();
  var shortDesc = 'Critical log event';
  var shortDescPrefix = 'Critical log event';

  function defaultCallerId() {
    var uid = gs.getUserID();
    if (uid) {
      return uid;
    }
    return '';
  }

  function linkAlertToIncident(incSysId) {
    current.incident = incSysId;
  }

  if (!current.incident.nil()) {
    var linkedInc = new GlideRecord('incident');
    if (
      linkedInc.get(current.incident.toString()) &&
      linkedInc.cmdb_ci.toString() !== asSysId
    ) {
      linkedInc.cmdb_ci = asSysId;
      linkedInc.work_notes =
        'Corrected CI from alert ' + current.number;
      linkedInc.update();
    }
    return;
  }

  var openInc = new GlideRecord('incident');
  openInc.addQuery('cmdb_ci', asSysId);
  openInc.addQuery('active', true);
  openInc.addQuery('short_description', 'STARTSWITH', shortDescPrefix);
  openInc.setLimit(1);
  openInc.query();
  if (openInc.next()) {
    openInc.work_notes =
      'Correlated alert ' +
      current.number +
      ': ' +
      current.description.toString().substring(0, 500);
    openInc.update();
    linkAlertToIncident(openInc.sys_id);
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: correlated existing incident ' +
        openInc.number
    );
    return;
  }

  var inc = new GlideRecord('incident');
  inc.initialize();
  inc.cmdb_ci = asSysId;
  inc.short_description = shortDesc;
  inc.description = current.description.toString().substring(0, 4000);
  inc.severity = current.severity;
  inc.impact = 2;
  inc.urgency = 2;
  inc.caller_id = defaultCallerId();
  inc.comments = 'Auto-created from Event Management alert ' + current.number;
  inc.work_notes = 'Source alert: ' + current.number;
  var incSysId = inc.insert();
  if (!incSysId) {
    gs.error(
      'em-alert-create-log-incident: insert failed for alert ' + current.number
    );
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: incident insert failed'
    );
    return;
  }
  linkAlertToIncident(incSysId);
  resolver.appendProcessingNote(
    current,
    'em-alert-create-log-incident: created incident sys_id=' + incSysId
  );
})(current, previous);
