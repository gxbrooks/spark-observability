var K8sLogPodCiBind = Class.create();
K8sLogPodCiBind.prototype = {
  initialize: function () {},

  resolvePodName: function (description, resource, node) {
    var text = description + ' ' + resource + ' ' + node;
    var regex = /\/(?:mnt|opt|var)\/[^/]+\/logs\/([^/\s*]+)\//g;
    var match;

    while ((match = regex.exec(text)) !== null) {
      if (
        !match[1] ||
        match[1].indexOf('*') !== -1 ||
        match[1] === 'spark-client'
      ) {
        continue;
      }
      var podGr = new GlideRecord('cmdb_ci_kubernetes_pod');
      podGr.addQuery('name', match[1]);
      podGr.setLimit(1);
      podGr.query();
      if (podGr.next()) {
        return match[1];
      }
    }

    return '';
  },

  /**
   * Bind gr (em_event or em_alert) to cmdb_ci_kubernetes_pod when the log path
   * segment matches a discovered pod CI name.
   * Returns true when cmdb_ci was set to a pod CI.
   * Does not run when the text encodes a spark-client path (Client-Side pattern
   * — use ResolveApplicationService.applySparkClientAlertBinding instead).
   */
  applyPodBinding: function (gr) {
    if (gr.source.toString() !== 'SGO-Dynatrace') {
      return false;
    }

    var combined =
      gr.description.toString() +
      ' ' +
      gr.resource.toString() +
      ' ' +
      gr.node.toString();
    if (
      combined.indexOf('/logs/spark-client/') !== -1 ||
      (combined.indexOf('Application log') !== -1 &&
        combined.indexOf('spark-client-') !== -1)
    ) {
      return false;
    }

    var podName = this.resolvePodName(
      gr.description.toString(),
      gr.resource.toString(),
      gr.node.toString()
    );
    if (!podName) {
      return false;
    }

    var podGr = new GlideRecord('cmdb_ci_kubernetes_pod');
    podGr.addQuery('name', podName);
    podGr.setLimit(1);
    podGr.query();
    if (!podGr.next()) {
      return false;
    }

    var podSysId = podGr.sys_id.toString();
    gr.cmdb_ci = podSysId;
    gr.node = podName;

    var text =
      gr.description.toString() +
      ' ' +
      gr.resource.toString() +
      ' ' +
      gr.node.toString();
    var podPathRe =
      new RegExp(
        '/(?:mnt|opt|var)/[^\\s]+/logs/' +
          podName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') +
          '/[^\\s]+\\.log'
      );
    var logPath = text.match(podPathRe);
    if (logPath) {
      gr.resource = logPath[0];
    } else if (gr.resource.toString().indexOf('/logs/') === -1) {
      gr.resource = '/mnt/spark/logs/' + podName + '/spark-app.log';
    }

    var messageKey = gr.message_key.toString();
    var podPrefix = 'K8sLog-' + podName + '-';
    if (messageKey.indexOf(podName) === -1) {
      gr.message_key = podPrefix + messageKey;
    }

    if (
      gr.isValidField('message') &&
      (gr.message.nil() ||
        gr.message.toString().indexOf('Log Errors') !== -1 ||
        gr.message.toString().indexOf('Event Log') !== -1)
    ) {
      var levelMatch = gr.description.toString().match(/\b(ERROR|WARN)\b/);
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

  /** Copy pod binding from em_event to related em_alert rows (same message_key). */
  propagateEventToAlerts: function (eventGr) {
    if (eventGr.cmdb_ci.nil()) {
      return;
    }

    var alert = new GlideRecord('em_alert');
    alert.addQuery('source', 'SGO-Dynatrace');
    alert.addQuery('message_key', eventGr.message_key);
    alert.query();
    while (alert.next()) {
      if (alert.cmdb_ci.toString() === eventGr.cmdb_ci.toString()) {
        continue;
      }
      alert.cmdb_ci = eventGr.cmdb_ci;
      alert.node = eventGr.node;
      alert.resource = eventGr.resource;
      alert.update();
    }
  },

  type: 'K8sLogPodCiBind',
};
