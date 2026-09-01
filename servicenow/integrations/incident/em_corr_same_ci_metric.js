// SUPERSEDED / kept inactive for reference — see
// em_alert_correlation_rule_same_ci_metric.json's description for why
// Advanced Correlation Rules don't fire on this instance. Log alert grouping
// now uses sn_em_tbac_l2i_definition.json (TBAC) +
// ResolveApplicationService.si.js#applyOpenIncidentJoin instead.
(function findCorrelatedAlerts(currentAlert) {
  var result = {};
  if (!currentAlert) {
    return JSON.stringify(result);
  }
  var metric = String(currentAlert.metric_name || '');
  // req 6 scope: open-incident join + same-signature clustering is for log
  // alerts only. CPU/other alert types now also carry non-empty metric_name
  // (req 2 backfill) and must not fall into this rule — they cluster via the
  // metric_class TBAC definition instead. em_alert.type is not a plain string
  // here (it reads back as an internal reference id outside the enrichment BR
  // that stamps it, so it cannot be compared against 'CRITICAL_LOG_EVENT'
  // reliably at this point in the pipeline) — metric_name's Log-Error: prefix
  // is the same reliable signal ResolveApplicationService.si.js already uses
  // (isL2iCriticalLogAlert) to identify log alerts.
  if (metric.indexOf('Log-Error:') !== 0) {
    return JSON.stringify(result);
  }
  var ci = currentAlert.cmdb_ci ? String(currentAlert.cmdb_ci) : '';
  if (!ci) {
    return JSON.stringify(result);
  }
  if (String(currentAlert.source || '') !== 'SGO-Dynatrace') {
    return JSON.stringify(result);
  }

  // req 6: an open incident already exists for this signature+CI — join it
  // directly, with no time limit, instead of creating a new one.
  var openPrimary = new GlideRecord('em_alert');
  openPrimary.addQuery('sys_id', '!=', currentAlert.sys_id);
  openPrimary.addQuery('cmdb_ci', ci);
  openPrimary.addQuery('metric_name', metric);
  openPrimary.addQuery('source', 'SGO-Dynatrace');
  openPrimary.addQuery('correlation_group', '1'); // 1 = Primary (see em_alert.correlation_group sys_choice)
  openPrimary.addNotNullQuery('incident');
  openPrimary.addQuery('incident.active', true);
  openPrimary.orderByDesc('sys_created_on');
  openPrimary.setLimit(1);
  openPrimary.query();
  if (openPrimary.next()) {
    result.SECONDARY = [openPrimary.getUniqueValue()];
    return JSON.stringify(result);
  }

  // No open-incident primary yet: seed a new Primary/Secondary pair from a
  // 1-hour lookback window (unchanged from the original behavior).
  var gr = new GlideRecord('em_alert');
  gr.addQuery('sys_id', '!=', currentAlert.sys_id);
  gr.addQuery('state', 'IN', 'Open,Reopen');
  gr.addQuery('cmdb_ci', ci);
  gr.addQuery('metric_name', metric);
  gr.addQuery('source', 'SGO-Dynatrace');
  var from = new GlideDateTime(currentAlert.sys_created_on);
  from.addSeconds(-3600);
  gr.addQuery('sys_created_on', '>=', from);
  gr.orderBy('sys_created_on');
  gr.query();

  var olderId = '';
  var newerIds = [];
  var cur = new GlideDateTime(currentAlert.sys_created_on);
  while (gr.next()) {
    if (!gr.parent.nil()) {
      continue;
    }
    var t = new GlideDateTime(gr.sys_created_on);
    if (t.compareTo(cur) < 0) {
      if (!olderId) {
        olderId = gr.getUniqueValue();
      }
    } else {
      newerIds.push(gr.getUniqueValue());
    }
  }
  if (olderId) {
    result.PRIMARY = [olderId];
  } else if (newerIds.length > 0) {
    result.SECONDARY = newerIds;
  }
  return JSON.stringify(result);
})();
