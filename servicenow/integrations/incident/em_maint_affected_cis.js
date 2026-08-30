// Fallback only. Deploy uses non-advanced "Affected CIs in Change Window"
// (table=task_ci, ci_field=ci_item, planned-window filter).
// If you must use Advanced, return JSON.stringify(['sys_id', ...]).
(function findCisInMaint() {
  var cis = [];
  var seen = {};
  var now = new GlideDateTime();
  var chg = new GlideRecord('change_request');
  chg.addQuery('approval', 'approved');
  chg.addQuery('on_hold', 'false');
  chg.addQuery('state', 'IN', '-2,-1');
  chg.addQuery('start_date', '<=', now);
  chg.addQuery('end_date', '>=', now);
  chg.query();
  while (chg.next()) {
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
