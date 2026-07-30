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
   * Spark client-mode logs: /mnt/spark/client-logs/<instance>/spark-app*.log
   * maps directly to Application Service Spark Client (no pod CI).
   * Also accepts Davis event.name "Client error at Class:Line" (and legacy
   * "Client application log …") when the problem payload omits the filesystem path.
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

  /** True when alert/event text encodes the Spark Client log path or Davis Client event. */
  isSparkClientLogText: function (text) {
    if (!text) {
      return false;
    }
    if (text.indexOf('/client-logs/') !== -1) {
      return true;
    }
    // Legacy path (pre client-logs split)
    if (text.indexOf('/logs/spark-client/') !== -1) {
      return true;
    }
    // OpenPipeline Davis event.name: "{spark.mode} error at {class}:{line}"
    if (text.indexOf('Client error at') !== -1) {
      return true;
    }
    // Legacy OpenPipeline Davis event.name
    if (text.indexOf('Client application log') !== -1) {
      return true;
    }
    // Legacy Davis event.name
    if (
      text.indexOf('Application log') !== -1 &&
      text.indexOf('spark-client-') !== -1
    ) {
      return true;
    }
    return false;
  },

  /**
   * Log4j Class:Line from problem text. Prefer event.unique_identifier suffix;
   * fall back to the WARN/ERROR body (… ERROR SparkContext:99 - …).
   */
  extractLog4jClassLine: function (text) {
    if (!text) {
      return '';
    }
    // Current: event.unique_identifier Client|Class:Line or Cluster|Class:Line
    var uidMode = text.match(
      /event\.unique_identifier:\s*(?:Client|Cluster)\|([A-Za-z_][\w$]*):(\d+)/
    );
    if (uidMode) {
      return uidMode[1] + ':' + uidMode[2];
    }
    // Legacy: Client:host:driver|Class:Line (optional ERROR/WARN eaten into class)
    var uidLegacy = text.match(
      /event\.unique_identifier:\s*[^\s|]+\|((?:ERROR|WARN)\s+)?([A-Za-z_][\w$]*):(\d+)/
    );
    if (uidLegacy) {
      return uidLegacy[2] + ':' + uidLegacy[3];
    }
    // event.name: Client|Cluster error at Class:Line
    var ename = text.match(
      /\b(?:Client|Cluster) error at ([A-Za-z_][\w$]*):(\d+)/
    );
    if (ename) {
      return ename[1] + ':' + ename[2];
    }
    var body = text.match(/\b(?:ERROR|WARN)\s+([A-Za-z_][\w$]*):(\d+)\s+-/);
    if (body) {
      return body[1] + ':' + body[2];
    }
    return '';
  },

  /** Dynatrace Apps base URL (sys_property override, else deploy-time default). */
  dtAppsUrl: function () {
    var apps = gs.getProperty('spark.l2i.dt_apps_url', '');
    if (apps) {
      return apps.replace(/\/$/, '');
    }
    return '@@DT_TENANT_URL@@'.replace(/\/$/, '');
  },

  /** Grail/platform bearer (sys_property override, else deploy-time default). */
  dtPlatformToken: function () {
    var token = gs.getProperty('spark.l2i.dt_platform_token', '');
    if (token) {
      return token;
    }
    var embedded = '@@DT_PLATFORM_TOKEN_GRAIL@@';
    if (embedded.indexOf('@@') === 0) {
      return '';
    }
    return embedded;
  },

  /**
   * Parse spark.mode + Class:Line from Davis / log text.
   * Returns { mode, className, line, classLine, uid } or null.
   */
  extractSparkLogIdentity: function (text) {
    if (!text) {
      return null;
    }
    var m = text.match(
      /\b(Client|Cluster)\s+error\s+at\s+([A-Za-z_][\w$]*):(\d+)/
    );
    if (!m) {
      m = text.match(
        /event\.unique_identifier:\s*(Client|Cluster)\|([A-Za-z_][\w$]*):(\d+)/
      );
    }
    if (!m) {
      m = text.match(
        /\b(Client|Cluster)\s+(?:WARN|ERROR)\s+at\s+([A-Za-z_][\w$]*):(\d+)/
      );
    }
    if (!m) {
      return null;
    }
    return {
      mode: m[1],
      className: m[2],
      line: m[3],
      classLine: m[2] + ':' + m[3],
      uid: m[1] + '|' + m[2] + ':' + m[3],
    };
  },

  /** ProblemURL from additional_info JSON when SGO stored it. */
  extractProblemUrl: function (gr) {
    var raw = '';
    try {
      if (gr.isValidField('additional_info') && !gr.additional_info.nil()) {
        raw = gr.getValue('additional_info') || '';
        if (!raw) {
          raw = gr.additional_info.toString();
        }
      }
    } catch (e1) {
      raw = '';
    }
    if (raw) {
      try {
        var info = JSON.parse(raw);
        if (info.ProblemURL) {
          return String(info.ProblemURL);
        }
        if (info.problemURL) {
          return String(info.problemURL);
        }
        if (info.PID) {
          return (
            'https://pdt20158.live.dynatrace.com/#problems/problemdetails;pid=' +
            info.PID
          );
        }
      } catch (e2) {
        var m = raw.match(
          /https:\/\/[^\s\"']+(?:problems|problemdetails)[^\s\"']*/i
        );
        if (m) {
          return m[0];
        }
      }
    }
    // message_key: SparkClient-<pid>V2|Class:Line or K8sLog-<pod>-<pid>V2|…
    var mk = gr.message_key ? gr.message_key.toString() : '';
    var pm = mk.match(/(-?\d+_\d+V2)/);
    if (pm) {
      return (
        'https://pdt20158.live.dynatrace.com/#problems/problemdetails;pid=' +
        pm[1]
      );
    }
    return '';
  },

  /**
   * Dynatrace Logs app deep link (Apps URL + DQL for mode|class:line).
   */
  buildSparkLogsDeepLink: function (identity) {
    if (!identity) {
      return '';
    }
    var apps = this.dtAppsUrl();
    if (!apps || apps.indexOf('@@') === 0) {
      return '';
    }
    // Keep the link short and robust in Rhino (avoid fragile intent JSON encoding).
    return (
      apps +
      '/ui/apps/dynatrace.logs/#gtf=-2h&gf=all&sortDirection=desc' +
      '&spark.mode=' +
      identity.mode +
      '&spark.log.class=' +
      identity.className +
      '&spark.log.line=' +
      identity.line
    );
  },

  /**
   * Fetch recent matching Grail log contents for mode|class:line.
   * Requires spark.l2i.dt_apps_url + spark.l2i.dt_platform_token sys_properties.
   */
  fetchMatchingSparkLogLines: function (identity, maxLines) {
    var out = [];
    if (!identity) {
      return out;
    }
    var apps = this.dtAppsUrl();
    var token = this.dtPlatformToken();
    if (!apps || !token || apps.indexOf('@@') === 0) {
      return out;
    }
    maxLines = maxLines || 25;
    var dql =
      'fetch logs, from:now()-2h\n' +
      '| filter spark.mode == "' +
      identity.mode +
      '"\n' +
      '| filter spark.log.class == "' +
      identity.className +
      '" and spark.log.line == ' +
      identity.line +
      '\n' +
      '| fields timestamp, content, spark.driver.instance, spark.pod_name, loglevel\n' +
      '| sort timestamp desc\n' +
      '| limit ' +
      maxLines;
    try {
      var rm = new sn_ws.RESTMessageV2();
      rm.setHttpMethod('POST');
      rm.setEndpoint(
        apps + '/platform/storage/query/v1/query:execute'
      );
      rm.setRequestHeader('Authorization', 'Bearer ' + token);
      rm.setRequestHeader('Content-Type', 'application/json');
      rm.setRequestHeader('Accept', 'application/json');
      rm.setRequestBody(
        JSON.stringify({
          query: dql,
          requestTimeoutMilliseconds: 30000,
          maxResultRecords: maxLines,
          maxResultBytes: 2000000,
        })
      );
      var resp = rm.execute();
      var code = resp.getStatusCode();
      var body = resp.getBody();
      if (code < 200 || code >= 300) {
        gs.warn(
          'ResolveApplicationService.fetchMatchingSparkLogLines HTTP ' +
            code +
            ': ' +
            body.substring(0, 300)
        );
        return out;
      }
      var data = JSON.parse(body);
      var records = [];
      if (data.result && data.result.records) {
        records = data.result.records;
      } else if (data.requestToken) {
        // Async poll once (lab); skip long waits in BR path.
        var poll = new sn_ws.RESTMessageV2();
        poll.setHttpMethod('GET');
        poll.setEndpoint(
          apps +
            '/platform/storage/query/v1/query:poll?request-token=' +
            encodeURIComponent(data.requestToken) +
            '&request-timeout-milliseconds=30000'
        );
        poll.setRequestHeader('Authorization', 'Bearer ' + token);
        poll.setRequestHeader('Accept', 'application/json');
        // brief wait
        gs.sleep(1500);
        var presp = poll.execute();
        if (presp.getStatusCode() >= 200 && presp.getStatusCode() < 300) {
          var pdata = JSON.parse(presp.getBody());
          if (pdata.result && pdata.result.records) {
            records = pdata.result.records;
          }
        }
      }
      for (var i = 0; i < records.length; i++) {
        var c = records[i].content;
        if (c) {
          out.push(String(c).replace(/\r?\n/g, ' '));
        }
      }
    } catch (e) {
      gs.warn(
        'ResolveApplicationService.fetchMatchingSparkLogLines: ' + e
      );
    }
    return out;
  },

  /**
   * Append matching log-line bundle + Problem/Logs deep links to description.
   * Idempotent (skips when marker already present).
   */
  enrichSparkLogDescription: function (gr) {
    var marker = '--- Matching Spark log lines ---';
    var desc = gr.description ? gr.description.toString() : '';
    if (desc.indexOf(marker) !== -1) {
      return false;
    }
    var text =
      desc +
      ' ' +
      (gr.resource ? gr.resource.toString() : '') +
      ' ' +
      (gr.node ? gr.node.toString() : '');
    var identity = this.extractSparkLogIdentity(text);
    if (!identity) {
      return false;
    }

    var lines = this.fetchMatchingSparkLogLines(identity, 25);

    var links = [];
    var problemUrl = this.extractProblemUrl(gr);
    if (problemUrl) {
      links.push('Problem: ' + problemUrl);
    }
    var logsUrl = this.buildSparkLogsDeepLink(identity);
    if (logsUrl) {
      links.push('Logs: ' + logsUrl);
    }

    // Links first so a 4k description truncate does not drop deep links.
    var block = '';
    if (links.length) {
      block += links.join('\n') + '\n\n';
    }
    block += marker + '\n';
    if (lines.length) {
      block += lines.join('\n');
    } else {
      block +=
        '(Grail fetch unavailable or empty; open Logs deep link above)\n' +
        'DQL filter: spark.mode=="' +
        identity.mode +
        '" AND ' +
        identity.className +
        ':' +
        identity.line;
    }

    var combined = desc + '\n\n' + block;
    var maxLen = 4000;
    if (combined.length > maxLen) {
      combined = combined.substring(0, maxLen - 18) + '\n...[truncated]';
    }
    gr.description = combined;
    return true;
  },

  /**
   * Ensure optional prefix, then append |Class:Line for EM correlation granularity.
   * Keeps Dynatrace ProblemID (SGO message_key) so OPEN/RESOLVED still match.
   */
  appendClassLineToMessageKey: function (gr, prefix) {
    var mk = gr.message_key.toString();
    if (prefix && mk.indexOf(prefix) === -1) {
      mk = prefix + mk;
    }
    var classLine = this.extractLog4jClassLine(
      gr.description.toString() + ' ' + gr.resource.toString()
    );
    if (classLine && mk.indexOf('|' + classLine) === -1) {
      mk = mk + '|' + classLine;
    }
    gr.message_key = mk;
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
    // for CUSTOM_DEVICE problems that still carry Client application log text.
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
      /\/(?:mnt|opt|var)\/[^\s]+\/client-logs\/[^\s/]+\/[^\s]+\.log/
    );
    if (!pathMatch) {
      pathMatch = text.match(
        /\/(?:mnt|opt|var)\/[^\s]+\/logs\/spark-client\/[^\s/]+\/[^\s]+\.log/
      );
    }
    if (pathMatch) {
      gr.resource = pathMatch[0];
    } else if (
      gr.resource.toString().indexOf('/client-logs/') === -1 &&
      gr.resource.toString().indexOf('/logs/spark-client/') === -1
    ) {
      gr.resource = '/mnt/spark/client-logs/spark-app.log';
    }

    this.appendClassLineToMessageKey(gr, 'SparkClient-');
    this.enrichSparkLogDescription(gr);

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
