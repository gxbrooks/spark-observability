(function executeRule(current, previous /*null on insert*/) {
  var resolver = new ResolveApplicationService();

  // Keep infrastructure CI already on the alert (usually copied from the event).
  // Rebind when a prior revision left a service instance on the alert — SI belongs
  // on the incident only.
  if (!current.cmdb_ci.nil()) {
    var existing = current.cmdb_ci.toString();
    if (!resolver.isServiceInstanceCi(existing)) {
      resolver.applyLogEventTypeRename(current);
      resolver.appendProcessingNote(
        current,
        'em-alert-bind-entity-ci: kept existing infra cmdb_ci=' +
          (current.cmdb_ci.getDisplayValue() || existing)
      );
      return;
    }
    resolver.appendProcessingNote(
      current,
      'em-alert-bind-entity-ci: replacing service-instance cmdb_ci with infra CI'
    );
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
