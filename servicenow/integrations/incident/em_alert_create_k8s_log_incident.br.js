(function executeRule(current, previous /*null on insert*/) {
  if (current.source.toString() !== 'SGO-Dynatrace') {
    return;
  }

  if (!current.incident.nil()) {
    return;
  }

  var severity = parseInt(current.severity, 10);
  if (isNaN(severity) || severity > 3) {
    return;
  }

  var desc = current.description.toString();
  if (
    desc.indexOf('/logs/') === -1 &&
    desc.indexOf('application.log') === -1 &&
    !desc.match(/\b(ERROR|WARN)\b/)
  ) {
    return;
  }

  if (current.cmdb_ci.nil()) {
    return;
  }

  var resolver = new ResolveApplicationService();
  var asSysId = resolver.resolveFromInfrastructureCi(current.cmdb_ci.toString());
  if (!asSysId) {
    return;
  }

  var levelMatch = desc.match(/\b(ERROR|WARN)\b/);
  var logLevel = levelMatch
    ? levelMatch[1]
    : severity <= 2
      ? 'ERROR'
      : 'WARN';
  var shortDesc = 'Event Log ' + logLevel;
  var shortDescPrefix = 'Event Log';

  function defaultCallerId() {
    var uid = gs.getUserID();
    if (uid) {
      return uid;
    }
    var userGr = new GlideRecord('sys_user');
    userGr.addQuery('user_name', 'gbrooks');
    userGr.setLimit(1);
    userGr.query();
    if (userGr.next()) {
      return userGr.sys_id.toString();
    }
    return '';
  }

  function linkAlertToIncident(incSysId) {
    current.incident = incSysId;
  }

  var backfillInc = new GlideRecord('incident');
  backfillInc.addQuery('active', true);
  backfillInc.addQuery('short_description', 'STARTSWITH', shortDescPrefix);
  backfillInc.addEncodedQuery('cmdb_ciISEMPTY');
  backfillInc.orderBy('sys_created_on');
  backfillInc.setLimit(1);
  backfillInc.query();
  if (backfillInc.next()) {
    backfillInc.cmdb_ci = asSysId;
    backfillInc.short_description = shortDesc;
    backfillInc.work_notes =
      'Set Configuration item from alert ' +
      current.number +
      ' (Application Service resolved via Contains traversal from pod CI).';
    backfillInc.update();
    linkAlertToIncident(backfillInc.sys_id);
    return;
  }

  var openInc = new GlideRecord('incident');
  openInc.addQuery('cmdb_ci', asSysId);
  openInc.addQuery('active', true);
  openInc.addQuery('short_description', 'CONTAINS', shortDescPrefix);
  openInc.addQuery('short_description', 'CONTAINS', logLevel);
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
      'em-alert-create-k8s-log-incident: insert failed for alert ' + current.number
    );
    return;
  }
  linkAlertToIncident(incSysId);
})(current, previous);
