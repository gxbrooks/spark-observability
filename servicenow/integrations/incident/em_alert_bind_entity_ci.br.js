(function executeRule(current, previous /*null on insert*/) {
  var resolver = new ResolveApplicationService();

  // Prefer CI already stamped on the alert (typically copied from the event).
  if (!current.cmdb_ci.nil()) {
    resolver.appendProcessingNote(
      current,
      'em-alert-bind-entity-ci: kept existing cmdb_ci=' +
        (current.cmdb_ci.getDisplayValue() || current.cmdb_ci.toString())
    );
    return;
  }

  var result = resolver.applyEntityBinding(current);
  resolver.appendProcessingNote(
    current,
    'em-alert-bind-entity-ci: kind=' +
      result.kind +
      '; bound=' +
      result.bound
  );
})(current, previous);
