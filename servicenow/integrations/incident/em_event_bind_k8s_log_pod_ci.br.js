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

  function appendProcessingNote(gr, note) {
    if (!gr.isValidField('processing_notes')) {
      return;
    }
    var existing = gr.processing_notes.toString();
    gr.processing_notes = existing ? existing + '\n' + note : note;
  }

  var beforeCi = ciLabel(current);
  var beforeSysId = current.cmdb_ci.nil() ? '' : current.cmdb_ci.toString();

  var resolver = new ResolveApplicationService();
  var bound = false;
  var path = 'none';
  if (resolver.applySparkClientAlertBinding(current)) {
    bound = true;
    path = 'spark-client Application Service';
  } else {
    var binder = new K8sLogPodCiBind();
    if (binder.applyPodBinding(current)) {
      bound = true;
      path = 'Application Service via kubernetes pod (or pod fallback)';
    }
  }

  var afterCi = ciLabel(current);
  var afterSysId = current.cmdb_ci.nil() ? '' : current.cmdb_ci.toString();
  var changed = beforeSysId !== afterSysId;

  appendProcessingNote(
    current,
    'em-event-bind-k8s-log-pod-ci: path=' +
      path +
      '; before CI/class=' +
      beforeCi +
      '; after CI/class=' +
      afterCi +
      (changed ? '; cmdb_ci updated' : '; cmdb_ci unchanged') +
      (bound ? '' : '; no lab rebind applied')
  );
})(current, previous);
