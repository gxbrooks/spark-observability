(function findCorrelatedAlerts(currentAlert) {
  var result = {};
  if (!currentAlert) {
    return result;
  }
  var metric = String(currentAlert.metric_name || '');
  if (!metric) {
    return result;
  }
  var ci = currentAlert.cmdb_ci ? String(currentAlert.cmdb_ci) : '';
  if (!ci) {
    return result;
  }
  if (String(currentAlert.source || '') !== 'SGO-Dynatrace') {
    return result;
  }

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
  return result;
})();
