var ResolveApplicationService = Class.create();
ResolveApplicationService.prototype = {
  initialize: function () {},

  /**
   * Resolve cmdb_ci_service_discovered sys_id from a workload CI (pod).
   * Pattern A only: cmdb_rel_ci Contains::Contained by where child = workload CI.
   *
   * Preconditions (Step 0): tag-based Service Mapping materialized the Contains
   * edge from Application Service (parent) to cmdb_ci_kubernetes_pod (child).
   */
  resolveFromInfrastructureCi: function (ciSysId) {
    if (!ciSysId) {
      return null;
    }

    var rel = new GlideRecord('cmdb_rel_ci');
    rel.addQuery('child', ciSysId);
    rel.addQuery('type', 'Contains::Contained by');
    rel.addQuery('parent.sys_class_name', 'cmdb_ci_service_discovered');
    rel.setLimit(1);
    rel.query();
    if (rel.next()) {
      return rel.parent.sys_id.toString();
    }

    return null;
  },

  type: 'ResolveApplicationService',
};
