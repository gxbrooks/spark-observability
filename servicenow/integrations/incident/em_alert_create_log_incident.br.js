(function executeRule(current, previous /*null on insert*/) {
  if (current.source.toString() !== 'SGO-Dynatrace') {
    return;
  }

  var severity = parseInt(current.severity, 10);
  if (isNaN(severity) || severity > 3) {
    return;
  }

  var resolver = new ResolveApplicationService();

  // Ensure infrastructure CI on the alert when missing (pod / HOST).
  if (current.cmdb_ci.nil()) {
    var bind = resolver.applyEntityBinding(current);
    if (!bind.bound) {
      resolver.appendProcessingNote(
        current,
        'em-alert-create-log-incident: alert infra CI unbound (' +
          (bind.note || 'unknown') +
          '); continuing for service-instance incident resolve'
      );
    }
  }

  // Incident ownership: service instance (support group), not the alert pod/HOST.
  var si = resolver.resolveServiceInstanceForIncident(current);
  if (!si || !si.sysId) {
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: skipped incident create — no service instance resolved'
    );
    return;
  }

  var classLine = resolver.extractLogClassLineForIncident(current);
  var shortDesc = resolver.buildCriticalLogIncidentShortDescription(classLine);
  var asSysId = si.sysId;

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
    if (linkedInc.get(current.incident.toString())) {
      var changed = false;
      if (linkedInc.cmdb_ci.toString() !== asSysId) {
        linkedInc.cmdb_ci = asSysId;
        changed = true;
      }
      if (
        linkedInc.short_description.toString() !== shortDesc &&
        classLine
      ) {
        linkedInc.short_description = shortDesc;
        changed = true;
      }
      if (changed) {
        linkedInc.work_notes =
          'Aligned incident CI/short description from alert ' +
          current.number +
          ' (SI via ' +
          si.how +
          ')';
        linkedInc.update();
      }
    }
    return;
  }

  // Correlate: one open incident per service instance + class:line.
  var openInc = new GlideRecord('incident');
  openInc.addQuery('cmdb_ci', asSysId);
  openInc.addQuery('active', true);
  openInc.addQuery('short_description', shortDesc);
  openInc.setLimit(1);
  openInc.query();
  if (openInc.next()) {
    openInc.work_notes =
      'Correlated alert ' +
      current.number +
      ' (alert CI=' +
      (current.cmdb_ci.getDisplayValue() || current.cmdb_ci.toString() || 'none') +
      '; resource=' +
      (current.resource ? current.resource.toString() : '') +
      '): ' +
      current.description.toString().substring(0, 500);
    openInc.update();
    linkAlertToIncident(openInc.sys_id);
    resolver.appendProcessingNote(
      current,
      'em-alert-create-log-incident: correlated existing incident ' +
        openInc.number +
        ' (SI + ' +
        (classLine || 'no-class-line') +
        ')'
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
  inc.comments =
    'Auto-created from Event Management alert ' +
    current.number +
    ' (service instance via ' +
    si.how +
    ')';
  inc.work_notes =
    'Source alert: ' +
    current.number +
    '; alert CI=' +
    (current.cmdb_ci.getDisplayValue() || 'none') +
    '; resource=' +
    (current.resource ? current.resource.toString() : '') +
    (classLine ? '; signature=' + classLine : '');
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
    'em-alert-create-log-incident: created incident sys_id=' +
      incSysId +
      ' cmdb_ci=SI short_description=' +
      shortDesc
  );
})(current, previous);
