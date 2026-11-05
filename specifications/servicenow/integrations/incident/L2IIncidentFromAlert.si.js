var L2IIncidentFromAlert = Class.create();
L2IIncidentFromAlert.prototype = {
  initialize: function () {},
  type: 'L2IIncidentFromAlert',
};

/**
 * Create/correlate L2I incidents via EvtMgmtIncidentHandler.createIncidentNoUpdate
 * → EvtMgmtCustomIncidentPopulator (same as Flow action Create incident from Alert).
 * autoOpen=false so an active em_alert_rule / AMR is not required.
 *
 * @param {GlideRecord} alert em_alert row
 * @param {{persist:boolean}=} opts persist:true forces alert.update()
 * @return {string|null} incident sys_id when linked/created
 */
L2IIncidentFromAlert.process = function (alert, opts) {
  opts = opts || {};
  if (!alert) {
    return null;
  }
  try {
    if (String(alert.source) !== 'SGO-Dynatrace') {
      return null;
    }
    if (!alert.incident.nil()) {
      return alert.incident.toString();
    }
    EvtMgmtIncidentHandler.createIncidentNoUpdate(alert, false);
    if (!alert.incident.nil() && opts.persist) {
      alert.setWorkflow(false);
      alert.update();
    }
    return alert.incident && !alert.incident.nil()
      ? alert.incident.toString()
      : null;
  } catch (e) {
    gs.error('L2IIncidentFromAlert.process: ' + e);
    return null;
  }
};

/**
 * Batch processor for scheduled job / reprocess playbooks.
 */
L2IIncidentFromAlert.processPending = function () {
  var gr = new GlideRecord('em_alert');
  gr.addQuery('source', 'SGO-Dynatrace');
  gr.addNullQuery('incident');
  gr.addQuery('description', 'CONTAINS', 'CRITICAL_LOG_EVENT');
  gr.addQuery('correlation_group', '!=', 'Secondary');
  gr.orderBy('sys_created_on');
  gr.setLimit(75);
  gr.query();
  var n = 0;
  while (gr.next()) {
    if (L2IIncidentFromAlert.process(gr, { persist: true })) {
      n++;
    }
  }
  if (n > 0) {
    gs.info('L2IIncidentFromAlert.processPending: handled ' + n);
  }
  return n;
};
