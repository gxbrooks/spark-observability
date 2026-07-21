var ResolveApplicationService = Class.create();
ResolveApplicationService.prototype = {
  initialize: function () {},

  /**
   * Resolve cmdb_ci_service_discovered sys_id from a workload CI (pod).
   * Pattern A / Service-side: cmdb_rel_ci Contains::Contained by where child = workload CI.
   *
   * Preconditions (Step 0): tag-based Service Mapping materialized the Contains
   * edge from Application Service (parent) to cmdb_ci_kubernetes_pod (child).
   */
  resolveFromInfrastructureCi: function (ciSysId) {
    if (!ciSysId) {
      return null;
    }

    var typeGr = new GlideRecord('cmdb_rel_type');
    typeGr.addQuery('name', 'Contains::Contained by');
    typeGr.setLimit(1);
    typeGr.query();
    if (!typeGr.next()) {
      return null;
    }

    var rel = new GlideRecord('cmdb_rel_ci');
    rel.addQuery('child', ciSysId);
    rel.addQuery('type', typeGr.sys_id.toString());
    rel.addQuery('parent.sys_class_name', 'cmdb_ci_service_discovered');
    rel.setLimit(1);
    rel.query();
    if (rel.next()) {
      return rel.parent.sys_id.toString();
    }

    return null;
  },

  /**
   * Spark client-mode logs: /mnt/spark/logs/spark-client/<instance>/spark-app*.log
   * maps directly to Application Service Spark Client (no pod CI).
   * Also accepts Davis event.name "Application log … on spark-client-<instance>"
   * when the problem payload omits the filesystem path.
   *
   * Lookup order: name (authoritative on optimizincdemo1), then identifier when
   * populated, then tag_list. Do NOT query identifier alone — on this instance
   * identifier is often empty and Glide queries return unrelated Application Services.
   */
  resolveFromSparkClientLogPath: function (text) {
    if (!this.isSparkClientLogText(text)) {
      return null;
    }

    var asByName = new GlideRecord('cmdb_ci_service_discovered');
    asByName.addQuery('name', 'Spark Client');
    asByName.setLimit(1);
    asByName.query();
    if (asByName.next()) {
      return asByName.sys_id.toString();
    }

    var asById = new GlideRecord('cmdb_ci_service_discovered');
    asById.addQuery('identifier', 'spark-client');
    asById.addNotNullQuery('identifier');
    asById.setLimit(1);
    asById.query();
    if (asById.next() && asById.identifier.toString() === 'spark-client') {
      return asById.sys_id.toString();
    }

    var asByTag = new GlideRecord('cmdb_ci_service_discovered');
    asByTag.addQuery('tag_list', 'CONTAINS', 'spark-client');
    asByTag.setLimit(1);
    asByTag.query();
    if (asByTag.next()) {
      return asByTag.sys_id.toString();
    }

    return null;
  },

  /** True when alert/event text encodes the Spark Client-Side Log Pattern. */
  isSparkClientLogText: function (text) {
    if (!text) {
      return false;
    }
    if (text.indexOf('/logs/spark-client/') !== -1) {
      return true;
    }
    // OpenPipeline Davis event.name: Application log WARN|ERROR on spark-client-<instance>
    if (
      text.indexOf('Application log') !== -1 &&
      text.indexOf('spark-client-') !== -1
    ) {
      return true;
    }
    return false;
  },

  /**
   * Bind em_event / em_alert to Application Service Spark Client when the log
   * path is client-mode. Prefer this over K8sLogPodCiBind (including when Davis
   * bundles client + service paths into one description).
   * Returns true when cmdb_ci was set to Spark Client AS.
   */
  applySparkClientAlertBinding: function (gr) {
    var source = gr.source.toString();
    // SGO-Dynatrace is preferred; Demo1 classic connector uses source=Dynatrace
    // for CUSTOM_DEVICE problems that still carry Application log spark-client-* text.
    if (source !== 'SGO-Dynatrace' && source !== 'Dynatrace') {
      return false;
    }

    var text =
      gr.description.toString() +
      ' ' +
      gr.resource.toString() +
      ' ' +
      gr.node.toString() +
      ' ' +
      (gr.short_description ? gr.short_description.toString() : '');
    if (!this.isSparkClientLogText(text)) {
      return false;
    }

    var asSysId = this.resolveFromSparkClientLogPath(text);
    if (!asSysId) {
      return false;
    }

    gr.cmdb_ci = asSysId;
    gr.node = 'Spark Client';

    var pathMatch = text.match(
      /\/(?:mnt|opt|var)\/[^\s]+\/logs\/spark-client\/[^\s/]+\/[^\s]+\.log/
    );
    if (pathMatch) {
      gr.resource = pathMatch[0];
    } else if (gr.resource.toString().indexOf('/logs/spark-client/') === -1) {
      gr.resource = '/mnt/spark/logs/spark-client/spark-app.log';
    }

    var messageKey = gr.message_key.toString();
    var clientPrefix = 'SparkClient-';
    if (messageKey.indexOf(clientPrefix) === -1) {
      gr.message_key = clientPrefix + messageKey;
    }

    if (
      gr.isValidField('message') &&
      (gr.message.nil() ||
        gr.message.toString().indexOf('Log Errors') !== -1 ||
        gr.message.toString().indexOf('Event Log') !== -1)
    ) {
      var levelMatch = gr.description.toString().match(/\b(ERROR|WARN)\b/);
      if (!levelMatch) {
        levelMatch = text.match(/\b(ERROR|WARN)\b/);
      }
      var severity = parseInt(gr.severity, 10);
      var logLevel = levelMatch
        ? levelMatch[1]
        : !isNaN(severity) && severity <= 2
          ? 'ERROR'
          : 'WARN';
      gr.message = 'Event Log ' + logLevel;
    }

    return true;
  },

  type: 'ResolveApplicationService',
};
