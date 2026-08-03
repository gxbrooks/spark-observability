(function executeRule(current, previous /*null on insert*/) {
  function ciLabel(gr) {
    if (gr.cmdb_ci.nil()) {
      return '(none) / (none)';
    }
    var name = gr.cmdb_ci.getDisplayValue() || gr.cmdb_ci.toString();
    var cls = '';
    if (gr.isValidField('cmdb_ci_type') && !gr.cmdb_ci_type.nil()) {
      cls = gr.cmdb_ci_type.toString();
    }
    if (!cls) {
      var ci = gr.cmdb_ci.getRefRecord();
      if (ci && ci.isValidRecord()) {
        cls = ci.getTableName() || ci.sys_class_name.toString();
      }
    }
    if (!cls) {
      cls = '(unknown class)';
    }
    return name + ' / ' + cls;
  }

  var beforeCi = ciLabel(current);
  var resolver = new ResolveApplicationService();
  var result = resolver.applyEntityBinding(current);
  var afterCi = ciLabel(current);

  resolver.appendProcessingNote(
    current,
    'em-event-bind-entity-ci: kind=' +
      result.kind +
      '; bound=' +
      result.bound +
      '; before CI/class=' +
      beforeCi +
      '; after CI/class=' +
      afterCi
  );
})(current, previous);
