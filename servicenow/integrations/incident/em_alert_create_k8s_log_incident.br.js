(function executeRule(current, previous /*null on insert*/) {
  var source = current.source.toString();
  if (source !== 'SGO-Dynatrace' && source !== 'Dynatrace') {
    return;
  }

  var severity = parseInt(current.severity, 10);
  if (isNaN(severity) || severity > 3) {
    return;
  }

  var desc = current.description.toString();
  var shortDescField = current.short_description
    ? current.short_description.toString()
    : '';
  var alertText =
    desc +
    ' ' +
    current.resource.toString() +
    ' ' +
    current.node.toString() +
    ' ' +
    shortDescField;

  var resolver = new ResolveApplicationService();
  // Client-side: bind from path or Davis event.name even when source is Dynatrace.
  if (!resolver.isSparkClientLogText(alertText)) {
    if (source !== 'SGO-Dynatrace') {
      return;
    }
    if (
      desc.indexOf('/logs/') === -1 &&
      desc.indexOf('spark-app.log') === -1 &&
      desc.indexOf('application.log') === -1 &&
      !desc.match(/\b(ERROR|WARN)\b/)
    ) {
      return;
    }
  }

  var asSysId = resolver.resolveFromSparkClientLogPath(alertText);
  var asSource = 'spark-client log path';

  if (!asSysId && !current.cmdb_ci.nil()) {
    asSysId = resolver.resolveFromInfrastructureCi(current.cmdb_ci.toString());
    asSource = 'Contains traversal from pod CI';
  }

  // Service-side fallback: alert may still be HOST; resolve pod from log path then Contains.
  if (!asSysId) {
    var binder = new K8sLogPodCiBind();
    var podName = binder.resolvePodName(
      desc,
      current.resource.toString(),
      current.node.toString()
    );
    if (podName) {
      var podGr = new GlideRecord('cmdb_ci_kubernetes_pod');
      podGr.addQuery('name', podName);
      podGr.setLimit(1);
      podGr.query();
      if (podGr.next()) {
        if (current.cmdb_ci.toString() !== podGr.sys_id.toString()) {
          current.cmdb_ci = podGr.sys_id.toString();
          current.node = podName;
        }
        asSysId = resolver.resolveFromInfrastructureCi(podGr.sys_id.toString());
        asSource = 'Contains traversal from pod CI (path fallback)';
      }
    }
  }

  if (!asSysId) {
    return;
  }

  // Client-side: alert CI may be HOST — align to Spark Client AS.
  // Service-side: keep alert on pod CI; only the incident gets the Application Service.
  if (asSource.indexOf('spark-client') !== -1) {
    if (current.cmdb_ci.toString() !== asSysId) {
      current.cmdb_ci = asSysId;
      current.node = 'Spark Client';
    }
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

  // Bundled Davis problems may pre-link alerts to an incident on the wrong AS.
  // When spark-client path resolves Spark Client AS, correct the linked incident CI.
  if (!current.incident.nil()) {
    var linkedInc = new GlideRecord('incident');
    if (
      linkedInc.get(current.incident.toString()) &&
      linkedInc.cmdb_ci.toString() !== asSysId
    ) {
      linkedInc.cmdb_ci = asSysId;
      linkedInc.short_description = shortDesc;
      linkedInc.work_notes =
        'Corrected Application Service from alert ' +
        current.number +
        ' (' +
        asSource +
        ').';
      linkedInc.update();
    }
    return;
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
      ' (Application Service resolved via ' +
      asSource +
      ').';
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
  inc.work_notes =
    'Source alert: ' + current.number + ' (Application Service via ' + asSource + ')';
  var incSysId = inc.insert();
  if (!incSysId) {
    gs.error(
      'em-alert-create-k8s-log-incident: insert failed for alert ' + current.number
    );
    return;
  }
  linkAlertToIncident(incSysId);
})(current, previous);
