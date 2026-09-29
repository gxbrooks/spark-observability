// Fallback only. Deploy uses non-advanced "Affected CIs in Change Window"
// (table=task_ci, ci_field=ci_item). Time gate matches OOTB CI in Change Window:
// planned start/end OR actual work_start/work_end (open-ended if work_end empty).
// If you must use Advanced, return JSON.stringify(['sys_id', ...]).
(function findCisInMaint() {
  var cis = [];
  var seen = {};
  var now = new GlideDateTime();

  function inWindow(chg) {
    var plannedStart = chg.start_date.getGlideObject();
    var plannedEnd = chg.end_date.getGlideObject();
    if (
      plannedStart &&
      plannedEnd &&
      plannedStart.compareTo(now) <= 0 &&
      plannedEnd.compareTo(now) >= 0
    ) {
      return true;
    }
    if (chg.work_start.nil()) {
      return false;
    }
    var actualStart = chg.work_start.getGlideObject();
    if (!actualStart || actualStart.compareTo(now) > 0) {
      return false;
    }
    if (chg.work_end.nil()) {
      return true;
    }
    var actualEnd = chg.work_end.getGlideObject();
    return actualEnd && actualEnd.compareTo(now) >= 0;
  }

  var chg = new GlideRecord('change_request');
  chg.addQuery('approval', 'approved');
  chg.addQuery('on_hold', 'false');
  // Scheduled (-2) and Implement (-1) only — matches OOTB ImpactManager for
  // change.cmdb_ci on this instance (New/-5 does not put the primary in maint).
  chg.addQuery('state', 'IN', '-2,-1');
  chg.query();
  while (chg.next()) {
    if (!inWindow(chg)) {
      continue;
    }
    var primary = chg.getValue('cmdb_ci');
    if (primary && !seen[primary]) {
      seen[primary] = true;
      cis.push(primary);
    }
    var tci = new GlideRecord('task_ci');
    tci.addQuery('task', chg.getUniqueValue());
    tci.query();
    while (tci.next()) {
      var id = tci.getValue('ci_item');
      if (id && !seen[id]) {
        seen[id] = true;
        cis.push(id);
      }
    }
  }
  return JSON.stringify(cis);
})();
