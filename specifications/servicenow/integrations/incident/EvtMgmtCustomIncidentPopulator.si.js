var EvtMgmtCustomIncidentPopulator = Class.create();
EvtMgmtCustomIncidentPopulator.prototype = {
  initialize: function () {},
  type: 'EvtMgmtCustomIncidentPopulator',
};

/**
 * Called by EvtMgmtIncidentHandler (Create incident from Alert / createIncident).
 * L2I: incident.cmdb_ci = service instance; correlate by SI + sn-log-signature.
 * All SGO-Dynatrace alerts: sn-impact / sn-urgency drive SN priority.
 * Non-L2I alerts still create incidents (CPU / K8s); SI is set when resolvable.
 *
 * @return true to continue incident insert; false to abort (correlated / no SI).
 */
EvtMgmtCustomIncidentPopulator.populateFieldsFromAlert = function (
  alert,
  task,
  rule
) {
  try {
    if (!alert || !task) {
      return true;
    }

    var resolver = new ResolveApplicationService();
    var isL2i = resolver.isL2iCriticalLogAlert(alert);

    if (!isL2i) {
      resolver.applySnPriorityToTask(alert, task, false);
      var siOther = resolver.resolveServiceInstanceForIncident(alert);
      if (siOther && siOther.sysId) {
        task.cmdb_ci = siOther.sysId;
      }
      return true;
    }

    var corr = alert.correlation_group
      ? alert.correlation_group.toString()
      : '';
    if (corr === 'Secondary') {
      return false;
    }

    var si = resolver.resolveServiceInstanceForIncident(alert);
    if (!si || !si.sysId) {
      gs.info(
        'EvtMgmtCustomIncidentPopulator: abort L2I — no service instance on ' +
          alert.number
      );
      return false;
    }

    var classLine =
      si.classLine || resolver.extractLogSignature(alert) || '';
    var shortDesc = resolver.buildCriticalLogIncidentShortDescription(
      classLine
    );

    var openInc = new GlideRecord('incident');
    openInc.addQuery('cmdb_ci', si.sysId);
    openInc.addQuery('active', true);
    openInc.addQuery('short_description', shortDesc);
    openInc.setLimit(1);
    openInc.query();
    if (openInc.next()) {
      alert.incident = openInc.sys_id;
      resolver.applySnPriorityToTask(alert, openInc, true);
      openInc.work_notes =
        'Correlated alert ' +
        alert.number +
        ' via EvtMgmtCustomIncidentPopulator (' +
        si.how +
        '); sn-impact=' +
        (openInc.impact || '') +
        ' sn-urgency=' +
        (openInc.urgency || '');
      openInc.update();
      gs.info(
        'EvtMgmtCustomIncidentPopulator: linked ' +
          alert.number +
          ' → ' +
          openInc.number
      );
      return false;
    }

    task.cmdb_ci = si.sysId;
    task.short_description = shortDesc;
    resolver.applySnPriorityToTask(alert, task, false);
    if (task.isValidField('description') && alert.description) {
      var d = alert.description.toString();
      if (d.length > 4000) {
        d = d.substring(0, 3980) + '\n...[truncated]';
      }
      task.description = d;
    }
    gs.info(
      'EvtMgmtCustomIncidentPopulator: L2I CI=' +
        si.sysId +
        ' short=' +
        shortDesc +
        ' impact=' +
        (task.impact || '') +
        ' urgency=' +
        (task.urgency || '') +
        ' via ' +
        si.how
    );
    return true;
  } catch (e) {
    gs.error(
      'EvtMgmtCustomIncidentPopulator.populateFieldsFromAlert: ' + e
    );
    return true;
  }
};
