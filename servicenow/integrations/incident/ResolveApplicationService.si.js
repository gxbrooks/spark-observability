var ResolveApplicationService = Class.create();
ResolveApplicationService.prototype = {
  initialize: function () {},

  /**
   * Append a line to em_event / em_alert processing_notes (never silent).
   */
  appendProcessingNote: function (gr, note) {
    if (!gr || !note) {
      return;
    }
    if (!gr.isValidField('processing_notes')) {
      return;
    }
    var existing = gr.processing_notes.toString();
    var line = String(note);
    if (existing && existing.indexOf(line) !== -1) {
      return;
    }
    gr.processing_notes = existing ? existing + '\n' + line : line;
  },

  /**
   * Resolve the Service Instance (Application Service) that a workload CI
   * belongs to via svc_ci_assoc — the membership table maintained by
   * tag-based Service Mapping (servicenow.com/service-instance tags).
   * No cmdb_rel_ci ownership edges are used (CSDM 5.0 model).
   */
  resolveFromInfrastructureCi: function (ciSysId) {
    if (!ciSysId) {
      return null;
    }

    var assoc = new GlideRecord('svc_ci_assoc');
    assoc.addQuery('ci_id', ciSysId);
    // Tag-populated services are cmdb_ci_service_by_tags, a child class of
    // cmdb_ci_service_discovered — match the whole hierarchy.
    assoc.addQuery(
      'service_id.sys_class_name',
      'IN',
      'cmdb_ci_service_discovered,cmdb_ci_service_calculated,cmdb_ci_service_by_tags'
    );
    assoc.setLimit(1);
    assoc.query();
    if (assoc.next()) {
      return assoc.getValue('service_id');
    }

    return null;
  },

  /**
   * Classify a Dynatrace entity id / type string into HOST | CUSTOM_DEVICE |
   * CLOUD_APPLICATION_INSTANCE | other.
   */
  classifyEntityType: function (type, entityId) {
    var t = String(type || '');
    var id = String(entityId || '');
    if (t === 'HOST' || id.indexOf('HOST-') === 0) {
      return 'HOST';
    }
    if (t === 'CUSTOM_DEVICE' || id.indexOf('CUSTOM_DEVICE-') === 0) {
      return 'CUSTOM_DEVICE';
    }
    if (
      t === 'CLOUD_APPLICATION_INSTANCE' ||
      id.indexOf('CLOUD_APPLICATION_INSTANCE-') === 0
    ) {
      return 'CLOUD_APPLICATION_INSTANCE';
    }
    return t || 'UNKNOWN';
  },

  /**
   * Parse the primary Dynatrace impacted entity from SGO additional_info.
   * Prefers singular ImpactedEntity, else first ImpactedEntities entry, else
   * resource/node fields. Returns { type, entityId, name } or null.
   */
  parsePrimaryImpactedEntity: function (gr) {
    var fromParts = function (type, entityId, name) {
      if (!entityId) {
        return null;
      }
      return {
        type: this.classifyEntityType(type, entityId),
        entityId: String(entityId),
        name: name ? String(name) : '',
      };
    }.bind(this);

    try {
      if (gr.isValidField('additional_info') && !gr.additional_info.nil()) {
        var raw = gr.getValue('additional_info') || gr.additional_info.toString();
        var info = JSON.parse(raw);

        if (info.ImpactedEntity && typeof info.ImpactedEntity === 'object') {
          var primary = fromParts(
            info.ImpactedEntity.type,
            info.ImpactedEntity.entity || info.ImpactedEntity.entityId,
            info.ImpactedEntity.name
          );
          if (primary) {
            return primary;
          }
        }

        var list = info.ImpactedEntities || info.impactedEntities || [];
        if (list.length) {
          var e0 = list[0] || {};
          var first = fromParts(
            e0.type,
            e0.entity || e0.entityId,
            e0.name || e0.entityName
          );
          if (first) {
            return first;
          }
        }
      }
    } catch (e0) {
      /* ignore malformed JSON */
    }

    var resource = gr.resource ? gr.resource.toString() : '';
    var node = gr.node ? gr.node.toString() : '';
    if (resource) {
      var fromResource = fromParts('', resource, node);
      if (
        fromResource &&
        (fromResource.type === 'HOST' ||
          fromResource.type === 'CUSTOM_DEVICE' ||
          fromResource.type === 'CLOUD_APPLICATION_INSTANCE')
      ) {
        return fromResource;
      }
    }

    var blob =
      resource +
      ' ' +
      node +
      ' ' +
      (gr.description ? gr.description.toString() : '') +
      ' ' +
      (gr.short_description ? gr.short_description.toString() : '');
    var cd = blob.match(/\b(CUSTOM_DEVICE-[A-F0-9]+)\b/);
    if (cd) {
      return fromParts('CUSTOM_DEVICE', cd[1], node);
    }
    var cai = blob.match(/\b(CLOUD_APPLICATION_INSTANCE-[A-F0-9]+)\b/);
    if (cai) {
      return fromParts('CLOUD_APPLICATION_INSTANCE', cai[1], node);
    }
    var host = blob.match(/\b(HOST-[A-F0-9]+)\b/);
    if (host) {
      return fromParts('HOST', host[1], node);
    }

    return null;
  },

  /**
   * Look up CMDB target for a Dynatrace entity id via SGO-Dynatrace sys_object_source.
   */
  lookupSysObjectSourceTarget: function (entityId, targetTable) {
    if (!entityId) {
      return null;
    }
    var sos = new GlideRecord('sys_object_source');
    sos.addQuery('name', 'SGO-Dynatrace');
    sos.addQuery('id', 'CONTAINS', entityId);
    if (targetTable) {
      sos.addQuery('target_table', targetTable);
    }
    sos.orderByDesc('sys_updated_on');
    sos.setLimit(1);
    sos.query();
    if (sos.next()) {
      return {
        sysId: sos.target_sys_id.toString(),
        table: sos.target_table.toString(),
      };
    }
    return null;
  },

  /**
   * HOST → host CI (SOS or name match). Returns { sysId, how } or null.
   */
  resolveFromHost: function (entityId, hostName) {
    var sos = this.lookupSysObjectSourceTarget(entityId, null);
    if (sos && sos.sysId) {
      return { sysId: sos.sysId, how: 'sys_object_source→HOST CI' };
    }

    if (hostName) {
      var hostGr = new GlideRecord('cmdb_ci_computer');
      hostGr.addQuery('name', hostName);
      hostGr.setLimit(1);
      hostGr.query();
      if (hostGr.next()) {
        return {
          sysId: hostGr.sys_id.toString(),
          how: 'cmdb_ci_computer name matches HOST display name',
        };
      }
    }

    return null;
  },

  /**
   * CUSTOM_DEVICE → Application Service with the same display name.
   * Also tries SOS / cmdb_key_value when present.
   */
  resolveApplicationServiceFromCustomDevice: function (entityId, deviceName) {
    var sos = this.lookupSysObjectSourceTarget(
      entityId,
      'cmdb_ci_service_discovered'
    );
    if (sos) {
      return { sysId: sos.sysId, how: 'sys_object_source→Application Service' };
    }

    var kv = new GlideRecord('cmdb_key_value');
    kv.addQuery('key', 'Dynatrace Instance');
    kv.addQuery('value', entityId);
    kv.setLimit(1);
    kv.query();
    if (kv.next() && !kv.configuration_item.nil()) {
      var ci = kv.configuration_item.getRefRecord();
      if (ci && ci.isValidRecord()) {
        if (ci.getTableName() === 'cmdb_ci_service_discovered') {
          return {
            sysId: ci.sys_id.toString(),
            how: 'cmdb_key_value Dynatrace Instance→Application Service',
          };
        }
        var asFromCi = this.resolveFromInfrastructureCi(ci.sys_id.toString());
        if (asFromCi) {
          return {
            sysId: asFromCi,
            how: 'cmdb_key_value→CI→svc_ci_assoc Application Service',
          };
        }
      }
    }

    if (deviceName) {
      var asByName = new GlideRecord('cmdb_ci_service_discovered');
      asByName.addQuery('name', deviceName);
      asByName.setLimit(1);
      asByName.query();
      if (asByName.next()) {
        return {
          sysId: asByName.sys_id.toString(),
          how: 'Application Service name matches CUSTOM_DEVICE display name',
        };
      }
    }

    return null;
  },

  /**
   * Map spark-* pod names to lab Application Service display names when the
   * svc_ci_assoc membership row is missing (e.g. Service Mapping has not yet
   * recomputed after a new Deployment worker pod appeared).
   */
  resolveSparkAsNameFromPodName: function (podName) {
    var n = String(podName || '');
    if (n.indexOf('spark-master') === 0) {
      return 'Spark Master';
    }
    if (n.indexOf('spark-worker') === 0) {
      return 'Spark Worker';
    }
    if (n.indexOf('spark-history') === 0) {
      return 'Spark History Server';
    }
    return null;
  },

  /**
   * CLOUD_APPLICATION_INSTANCE → pod CI → Application Service via svc_ci_assoc.
   * Fallback: spark-master/worker/history pod name → AS by display name.
   * Returns { asSysId, podSysId, podName, how } or null when nothing maps.
   */
  resolveFromCloudApplicationInstance: function (entityId, podName) {
    var sos = this.lookupSysObjectSourceTarget(
      entityId,
      'cmdb_ci_kubernetes_pod'
    );
    var podSysId = sos ? sos.sysId : null;

    if (!podSysId && podName) {
      var podGr = new GlideRecord('cmdb_ci_kubernetes_pod');
      podGr.addQuery('name', podName);
      podGr.setLimit(1);
      podGr.query();
      if (podGr.next()) {
        podSysId = podGr.sys_id.toString();
      }
    }

    var name = podName;
    if (!name && podSysId) {
      var p = new GlideRecord('cmdb_ci_kubernetes_pod');
      if (p.get(podSysId)) {
        name = p.name.toString();
      }
    }

    if (podSysId) {
      var asSysId = this.resolveFromInfrastructureCi(podSysId);
      if (asSysId) {
        return {
          podSysId: podSysId,
          asSysId: asSysId,
          podName: name || '',
          how: 'CAI→pod→svc_ci_assoc Application Service',
        };
      }
    }

    var asName = this.resolveSparkAsNameFromPodName(name);
    if (asName) {
      var asByName = new GlideRecord('cmdb_ci_service_discovered');
      asByName.addQuery('name', asName);
      asByName.setLimit(1);
      asByName.query();
      if (asByName.next()) {
        return {
          podSysId: podSysId,
          asSysId: asByName.sys_id.toString(),
          podName: name || '',
          how:
            'pod name ' +
            (name || '') +
            ' → Application Service name "' +
            asName +
            '" (svc_ci_assoc row missing)',
        };
      }
    }

    if (podSysId) {
      return {
        podSysId: podSysId,
        asSysId: null,
        podName: name || '',
        how: 'CAI→pod found but no svc_ci_assoc Application Service',
      };
    }

    return null;
  },

  /**
   * Collect description / additional_info / resource / node text for Spark
   * metadata field parsing (OpenPipeline stamps into Davis description + props).
   */
  collectSparkLookupBlob: function (gr) {
    var blob = '';
    try {
      if (gr.isValidField('additional_info') && !gr.additional_info.nil()) {
        blob +=
          ' ' +
          (gr.getValue('additional_info') || gr.additional_info.toString());
      }
    } catch (e0) {
      /* ignore */
    }
    if (gr.description) {
      blob += ' ' + gr.description.toString();
    }
    if (gr.short_description) {
      blob += ' ' + gr.short_description.toString();
    }
    if (gr.resource) {
      blob += ' ' + gr.resource.toString();
    }
    if (gr.node) {
      blob += ' ' + gr.node.toString();
    }
    return blob;
  },

  /**
   * Parse spark.service_instance from description / additional_info JSON.
   * Value is a K8s-sanitized service instance display name (e.g. Spark-Client).
   * Also accepts legacy spark.as_identifier for in-flight problems.
   * Returns the stamp string or null.
   */
  extractSparkServiceInstance: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(
      /spark\.service_instance\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
    );
    if (!m) {
      m = blob.match(
        /["']spark\.service_instance["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    // Legacy field name from pre-rename OpenPipeline stamps.
    if (!m) {
      m = blob.match(/spark\.as_identifier\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i);
    }
    if (!m) {
      m = blob.match(
        /["']spark\.as_identifier["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    return m ? m[1] : null;
  },

  /** @deprecated Use extractSparkServiceInstance */
  extractSparkAsIdentifier: function (gr) {
    return this.extractSparkServiceInstance(gr);
  },


  /**
   * Parse spark.pod_identifier from description / additional_info JSON.
   * Returns the pod name string or null.
   */
  extractSparkPodIdentifier: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(
      /spark\.pod_identifier\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
    );
    if (!m) {
      m = blob.match(
        /["']spark\.pod_identifier["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    if (!m) {
      // Container Output / PGI display: "(Worker spark-worker-lab1-…)" / "(Master spark-master-0)"
      m = blob.match(
        /\(\s*(?:Worker|Master|Driver|Executor)\s+(spark-[A-Za-z0-9][\w.-]*)\s*\)/i
      );
    }
    if (!m) {
      // Legacy Cluster file-tail path segment
      m = blob.match(/\/mnt\/spark\/logs\/([A-Za-z0-9][\w.-]*)\//);
    }
    return m ? m[1] : null;
  },

  /**
   * Sanitize a service instance display name the same way CSDM / K8s labels do:
   * illegal chars → '-', strip leading/trailing -._
   */
  sanitizeServiceInstanceLabel: function (name) {
    if (!name) {
      return '';
    }
    var s = String(name).replace(/[^A-Za-z0-9._-]+/g, '-');
    s = s.replace(/^[-._]+|[-._]+$/g, '');
    return s;
  },

  /**
   * Service instance from spark.service_instance (K8s-sanitized display name).
   * Prefer name match; also match when CMDB name sanitizes to the stamp
   * (Spark-Client ↔ Spark Client). Legacy stamp spark-client still maps to
   * Spark Client. Optional identifier column only when isValidField.
   * Returns { sysId, how } or null.
   */
  resolveFromServiceInstance: function (stamp) {
    if (!stamp) {
      return null;
    }

    var candidates = [stamp];
    // Legacy OpenPipeline value before display-name alignment.
    if (stamp === 'spark-client' || stamp === 'Spark-Client') {
      candidates.push('Spark Client');
    }
    var spaced = String(stamp).replace(/-/g, ' ');
    if (spaced !== stamp) {
      candidates.push(spaced);
    }

    var seen = {};
    for (var i = 0; i < candidates.length; i++) {
      var preferredName = candidates[i];
      if (seen[preferredName]) {
        continue;
      }
      seen[preferredName] = true;

      var asByName = new GlideRecord('cmdb_ci_service_discovered');
      asByName.addQuery('name', preferredName);
      asByName.setLimit(1);
      asByName.query();
      if (asByName.next()) {
        return {
          sysId: asByName.sys_id.toString(),
          how:
            preferredName === stamp
              ? 'service instance name=' + preferredName
              : 'service instance name "' +
                preferredName +
                '" (spark.service_instance=' +
                stamp +
                ')',
        };
      }
    }

    // Fallback: scan recent service instances for sanitized-name match.
    var scan = new GlideRecord('cmdb_ci_service_discovered');
    scan.addQuery('name', 'STARTSWITH', 'Spark');
    scan.setLimit(50);
    scan.query();
    while (scan.next()) {
      var nm = scan.name.toString();
      if (this.sanitizeServiceInstanceLabel(nm) === stamp) {
        return {
          sysId: scan.sys_id.toString(),
          how:
            'service instance name "' +
            nm +
            '" (sanitized match for spark.service_instance=' +
            stamp +
            ')',
        };
      }
    }

    var probe = new GlideRecord('cmdb_ci_service_discovered');
    if (probe.isValidField('identifier')) {
      var asById = new GlideRecord('cmdb_ci_service_discovered');
      asById.addQuery('identifier', stamp);
      asById.setLimit(1);
      asById.query();
      if (
        asById.next() &&
        String(asById.getValue('identifier') || '') === String(stamp)
      ) {
        return {
          sysId: asById.sys_id.toString(),
          how: 'service instance identifier=' + stamp,
        };
      }
    }

    return null;
  },

  /** @deprecated Use resolveFromServiceInstance */
  resolveFromAsIdentifier: function (asIdentifier) {
    return this.resolveFromServiceInstance(asIdentifier);
  },

  /**
   * Parse spark.event_kind from description / additional_info.
   */
  extractSparkEventKind: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(/spark\.event_kind\s*[=:]\s*([A-Za-z0-9_]+)/i);
    if (!m) {
      m = blob.match(
        /["']spark\.event_kind["']\s*:\s*["']([A-Za-z0-9_]+)["']/i
      );
    }
    return m ? m[1] : null;
  },

  /**
   * Dynatrace Settings API only allows enum event.type values (ERROR_EVENT,
   * CUSTOM_ALERT, …). Lab stamps spark.event_kind and remaps em_event.type
   * (and em_alert.type) so SN UI shows CRITICAL_LOG_EVENT / CPU_EVENT.
   * Leaves CPU_SATURATED and other built-ins alone.
   */
  applySparkEventTypeRename: function (gr) {
    if (!gr || !gr.isValidField('type')) {
      return;
    }
    var current = gr.type.toString();
    if (current === 'CPU_SATURATED') {
      return;
    }
    var kind = this.extractSparkEventKind(gr);
    var blob = this.collectSparkLookupBlob(gr);
    var next = null;

    if (kind === 'CRITICAL_LOG_EVENT') {
      next = 'CRITICAL_LOG_EVENT';
    } else if (kind === 'CPU_EVENT') {
      next = 'CPU_EVENT';
    } else if (
      current === 'ERROR_EVENT' &&
      (this.extractSparkServiceInstance(gr) ||
        this.extractSparkPodIdentifier(gr))
    ) {
      next = 'CRITICAL_LOG_EVENT';
    } else if (
      current === 'CUSTOM_ALERT' &&
      /Host\s+.*CPU\s+above\s+80%|CPU usage in management zone/i.test(blob)
    ) {
      next = 'CPU_EVENT';
    }

    if (next && next !== current) {
      gr.type = next;
      this.appendProcessingNote(
        gr,
        'em-entity-bind: type ' + current + ' → ' + next + ' (spark.event_kind rename)'
      );
    }
  },

  /**
   * Generic entity → CI bind for SGO-Dynatrace em_event / em_alert:
   *   1. spark.service_instance → service instance by display name (ignore HOST)
   *   2. spark.pod_identifier → pod name → svc_ci_assoc SI (ignore HOST)
   *   3. primary ImpactedEntity: HOST / CUSTOM_DEVICE / CAI
   *   else leave cmdb_ci empty and note failure
   *
   * Stamps: resource = spark.* key or entityId; node = display name.
   * Returns { bound: boolean, kind: string, note: string }.
   */
  applyEntityBinding: function (gr) {
    var result = { bound: false, kind: 'none', note: '' };

    if (!gr || gr.source.toString() !== 'SGO-Dynatrace') {
      result.note = 'applyEntityBinding: skipped (source is not SGO-Dynatrace)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    this.applySparkEventTypeRename(gr);

    // 1) Client log path: OpenPipeline stamps spark.service_instance (ignore HOST).
    var serviceInstance = this.extractSparkServiceInstance(gr);
    if (serviceInstance) {
      var asBind = this.resolveFromServiceInstance(serviceInstance);
      if (asBind && asBind.sysId) {
        gr.node = serviceInstance;
        gr.resource = 'spark.service_instance:' + serviceInstance;
        gr.cmdb_ci = asBind.sysId;
        result.bound = true;
        result.kind = 'service_instance';
        result.note =
          'em-entity-bind: spark.service_instance=' +
          serviceInstance +
          ' → service instance via ' +
          asBind.how;
        this.appendProcessingNote(gr, result.note);
        this.appendClassLineToMessageKey(gr, 'SvcInst-');
        this.enrichSparkLogDescription(gr, 'Client');
        return result;
      }
      result.kind = 'service_instance';
      result.note =
        'em-entity-bind: spark.service_instance=' +
        serviceInstance +
        ' — no service instance by name/identifier; cmdb_ci left empty (HOST ImpactedEntity ignored)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    // 2) Cluster log path: OpenPipeline stamps spark.pod_identifier (ignore HOST).
    var podIdentifier = this.extractSparkPodIdentifier(gr);
    if (podIdentifier) {
      var byName = this.resolveFromCloudApplicationInstance(null, podIdentifier);
      if (byName && byName.asSysId) {
        gr.node = podIdentifier;
        gr.resource = 'spark.pod_identifier:' + podIdentifier;
        gr.cmdb_ci = byName.asSysId;
        result.bound = true;
        result.kind = 'pod_identifier';
        result.note =
          'em-entity-bind: spark.pod_identifier=' +
          podIdentifier +
          ' → Application Service via ' +
          byName.how;
        this.appendProcessingNote(gr, result.note);
        this.appendClassLineToMessageKey(gr, 'K8sPod-');
        this.enrichSparkLogDescription(gr, 'Cluster');
        return result;
      }
      result.kind = 'pod_identifier';
      result.note =
        'em-entity-bind: spark.pod_identifier=' +
        podIdentifier +
        ' — ' +
        (byName && byName.how
          ? byName.how
          : 'no cmdb_ci_kubernetes_pod by name') +
        '; cmdb_ci left empty (HOST ImpactedEntity ignored)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    // 3) Primary ImpactedEntity (HOST for CPU; CUSTOM_DEVICE / CAI when present).
    var entity = this.parsePrimaryImpactedEntity(gr);
    if (!entity) {
      result.note =
        'em-entity-bind: no spark.service_instance / spark.pod_identifier and no primary impacted entity (HOST / CUSTOM_DEVICE / CLOUD_APPLICATION_INSTANCE)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    gr.resource = entity.entityId;
    if (entity.name) {
      gr.node = entity.name;
    }

    if (entity.type === 'HOST') {
      var host = this.resolveFromHost(entity.entityId, entity.name);
      if (!host) {
        result.kind = 'host';
        result.note =
          'em-entity-bind: HOST ' +
          entity.entityId +
          ' (' +
          (entity.name || 'unnamed') +
          ') found but no CMDB host CI (SOS / name match failed); cmdb_ci left empty';
        this.appendProcessingNote(gr, result.note);
        return result;
      }
      gr.cmdb_ci = host.sysId;
      result.bound = true;
      result.kind = 'host';
      result.note = 'em-entity-bind: HOST→CI via ' + host.how;
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    if (entity.type === 'CUSTOM_DEVICE') {
      var client = this.resolveApplicationServiceFromCustomDevice(
        entity.entityId,
        entity.name
      );
      if (!client) {
        result.kind = 'custom_device';
        result.note =
          'em-entity-bind: CUSTOM_DEVICE ' +
          entity.entityId +
          ' (' +
          (entity.name || 'unnamed') +
          ') found but no Application Service mapped; cmdb_ci left empty';
        this.appendProcessingNote(gr, result.note);
        return result;
      }
      gr.cmdb_ci = client.sysId;
      result.bound = true;
      result.kind = 'custom_device';
      result.note =
        'em-entity-bind: CUSTOM_DEVICE→Application Service via ' + client.how;
      this.appendProcessingNote(gr, result.note);
      this.appendClassLineToMessageKey(gr, 'Device-');
      this.enrichSparkLogDescription(gr, 'Client');
      return result;
    }

    if (entity.type === 'CLOUD_APPLICATION_INSTANCE') {
      var pod = this.resolveFromCloudApplicationInstance(
        entity.entityId,
        entity.name
      );
      if (!pod || !pod.asSysId) {
        result.kind = 'cai';
        result.note =
          'em-entity-bind: CLOUD_APPLICATION_INSTANCE ' +
          entity.entityId +
          ' (' +
          (entity.name || 'unnamed') +
          ') — ' +
          (pod && pod.how
            ? pod.how
            : 'no cmdb_ci_kubernetes_pod via SOS or name') +
          '; cmdb_ci left empty';
        this.appendProcessingNote(gr, result.note);
        return result;
      }
      if (pod.podName) {
        gr.node = pod.podName;
      }
      gr.cmdb_ci = pod.asSysId;
      result.bound = true;
      result.kind = 'cai';
      result.note = 'em-entity-bind: ' + pod.how;
      this.appendProcessingNote(gr, result.note);
      this.appendClassLineToMessageKey(gr, 'K8sPod-');
      this.enrichSparkLogDescription(gr, 'Cluster');
      return result;
    }

    result.note =
      'em-entity-bind: unsupported primary entity type ' +
      entity.type +
      '; cmdb_ci left empty';
    this.appendProcessingNote(gr, result.note);
    return result;
  },

  /** Log4j Class:Line from Davis event text for message_key granularity. */
  extractLog4jClassLine: function (text) {
    if (!text) {
      return '';
    }
    var m = text.match(
      /Spark\s+(?:\w+\s+)?[Cc]ritical\s+(?:WARN|ERROR)\s+error\s+(?:at\s+)?([A-Za-z_][\w$]*):(\d+)/
    );
    if (m) {
      return m[1] + ':' + m[2];
    }
    m = text.match(/\b(?:ERROR|WARN)\s+([A-Za-z_][\w$]*):(\d+)\s+-/);
    if (m) {
      return m[1] + ':' + m[2];
    }
    return '';
  },

  extractSparkLogIdentity: function (text, modeHint) {
    var classLine = this.extractLog4jClassLine(text);
    if (!classLine) {
      return null;
    }
    var parts = classLine.split(':');
    var mode = modeHint || '';
    if (!mode) {
      return null;
    }
    return {
      mode: mode,
      className: parts[0],
      line: parts[1],
      classLine: classLine,
      uid: classLine,
    };
  },

  pad2: function (n) {
    return n < 10 ? '0' + n : String(n);
  },

  formatUtcIso: function (ms) {
    var d = new Date(ms);
    return (
      d.getUTCFullYear() +
      '-' +
      this.pad2(d.getUTCMonth() + 1) +
      '-' +
      this.pad2(d.getUTCDate()) +
      'T' +
      this.pad2(d.getUTCHours()) +
      ':' +
      this.pad2(d.getUTCMinutes()) +
      ':' +
      this.pad2(d.getUTCSeconds()) +
      '.000Z'
    );
  },

  extractProblemCenterMs: function (gr) {
    var candidates = [];
    if (gr.message_key) {
      candidates.push(gr.message_key.toString());
    }
    try {
      if (gr.isValidField('additional_info') && !gr.additional_info.nil()) {
        var raw = gr.getValue('additional_info') || gr.additional_info.toString();
        candidates.push(raw);
        try {
          var info = JSON.parse(raw);
          if (info.PID) {
            candidates.push(String(info.PID));
          }
        } catch (e0) {
          /* ignore */
        }
      }
    } catch (e1) {
      /* ignore */
    }
    if (gr.description) {
      candidates.push(gr.description.toString());
    }
    for (var i = 0; i < candidates.length; i++) {
      var pm = String(candidates[i]).match(/_(\d{10,})V2/);
      if (pm) {
        var ms = parseInt(pm[1], 10);
        if (ms > 1000000000000 && ms < 4102444800000) {
          return ms;
        }
      }
    }
    return new Date().getTime();
  },

  buildProblemTimeWindow: function (gr, padMinutes) {
    var pad = (padMinutes || 24) * 60 * 1000;
    var centerMs = this.extractProblemCenterMs(gr);
    return {
      centerMs: centerMs,
      fromMs: centerMs - pad,
      toMs: centerMs + pad,
      fromIso: this.formatUtcIso(centerMs - pad),
      toIso: this.formatUtcIso(centerMs + pad),
    };
  },

  /** DQL text only — never execute against Grail on the BR critical path. */
  buildSparkLogDql: function (identity, window, maxLines) {
    maxLines = maxLines || 100;
    return (
      'fetch logs\n' +
      '| filter timestamp >= toTimestamp("' +
      window.fromIso +
      '") and timestamp <= toTimestamp("' +
      window.toIso +
      '")\n' +
      '| filter spark.mode == "' +
      identity.mode +
      '"\n' +
      '| filter spark.log.class == "' +
      identity.className +
      '" and spark.log.line == ' +
      identity.line +
      '\n' +
      '| sort timestamp desc\n' +
      '| limit ' +
      maxLines
    );
  },

  /**
   * Append DQL for matching log lines to description. No URL, no Grail fetch.
   */
  enrichSparkLogDescription: function (gr, modeHint) {
    var marker = '--- Matching Spark log lines (DQL) ---';
    var desc = gr.description ? gr.description.toString() : '';
    var stripFrom = desc.indexOf(marker);
    if (stripFrom === -1) {
      stripFrom = desc.indexOf('--- L2I enrichment ---');
    }
    if (stripFrom === -1) {
      stripFrom = desc.indexOf('--- Matching Spark log lines ---');
    }
    if (stripFrom > 0) {
      desc = desc.substring(0, stripFrom).replace(/\s+$/, '');
    }

    var identity = this.extractSparkLogIdentity(desc, modeHint);
    if (!identity) {
      return false;
    }

    var window = this.buildProblemTimeWindow(gr, 24);
    var block =
      marker +
      '\n' +
      this.buildSparkLogDql(identity, window, 100) +
      '\n';
    var combined = desc + '\n\n' + block;
    if (combined.length > 4000) {
      combined = combined.substring(0, 3980) + '\n...[truncated]';
    }
    gr.description = combined;
    return true;
  },

  appendClassLineToMessageKey: function (gr, prefix) {
    var mk = gr.message_key ? gr.message_key.toString() : '';
    if (prefix && mk.indexOf(prefix) === -1) {
      mk = prefix + mk;
    }
    var classLine = this.extractLog4jClassLine(
      (gr.description ? gr.description.toString() : '') +
        ' ' +
        (gr.resource ? gr.resource.toString() : '')
    );
    if (classLine && mk.indexOf('|' + classLine) === -1) {
      mk = mk + '|' + classLine;
    }
    gr.message_key = mk;
  },

  type: 'ResolveApplicationService',
};
