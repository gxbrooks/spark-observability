var EvtMgmtCustomIncidentPopulator = Class.create();
EvtMgmtCustomIncidentPopulator.prototype = {
  initialize: function () {},
  type: 'EvtMgmtCustomIncidentPopulator',
};

/**
 * Called by EvtMgmtIncidentHandler (Create incident from Alert / createIncident).
 * L2I: incident.cmdb_ci = service instance; correlate by SI + sn-log-signature.
 * Non-L2I alerts unchanged (return true).
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
    if (!resolver.isL2iCriticalLogAlert(alert)) {
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
      openInc.work_notes =
        'Correlated alert ' +
        alert.number +
        ' via EvtMgmtCustomIncidentPopulator (' +
        si.how +
        ')';
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
