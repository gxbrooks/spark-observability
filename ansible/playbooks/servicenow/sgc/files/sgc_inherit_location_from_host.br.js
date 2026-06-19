(function executeRule(current, previous /*null on insert*/) {
  if (!current.location.nil()) {
    return;
  }
  if (current.host.nil()) {
    return;
  }
  var source = current.discovery_source.toString();
  if (source.indexOf('SGO-Dynatrace') === -1) {
    return;
  }
  // CSDM: location applies to infrastructure CIs only — not processes/services.
  var infraClasses = {
    cmdb_ci_linux_server: true,
    cmdb_ci_win_server: true,
    cmdb_ci_computer: true,
    cmdb_ci_vm_instance: true,
    cmdb_ci_vmware_instance: true,
    cmdb_ci_kubernetes_node: true,
    cmdb_ci_kubernetes_cluster: true,
    cmdb_ci_docker_container: true,
    cmdb_ci_cloud_host: true,
  };
  if (!infraClasses[current.sys_class_name.toString()]) {
    return;
  }
  var host = current.host.getRefRecord();
  if (!host.nil() && !host.location.nil()) {
    current.location = host.location;
  }
})(current, previous);
