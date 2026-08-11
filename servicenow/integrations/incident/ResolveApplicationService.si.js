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
   * Parse sn-service_instance from description / additional_info JSON.
   * Legacy: sn.service_instance, l2i.service_instance, bare service_instance.
   */
  extractServiceInstance: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(
      /(?:^|[\s,{;])sn-service_instance\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
    );
    if (!m) {
      m = blob.match(
        /["']sn-service_instance["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    if (!m) {
      m = blob.match(
        /(?:^|[\s,{;])sn\.service_instance\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
      );
    }
    if (!m) {
      m = blob.match(
        /["']sn\.service_instance["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    if (!m) {
      m = blob.match(
        /(?:^|[\s,{;])l2i\.service_instance\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
      );
    }
    if (!m) {
      m = blob.match(
        /["']l2i\.service_instance["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    if (!m) {
      m = blob.match(
        /(?:^|[\s,{;])service_instance\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i
      );
    }
    if (!m) {
      m = blob.match(
        /["']service_instance["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
    }
    return m ? m[1] : null;
  },

  /**
   * Parse sn-log-signature (Class:Line) from OpenPipeline stamps.
   * Legacy: sn.log.signature, log.signature.
   */
  extractLogSignature: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(
      /(?:^|[\s,{;])sn-log-signature\s*[=:]\s*([A-Za-z_][\w$]*:\d+)/i
    );
    if (!m) {
      m = blob.match(
        /["']sn-log-signature["']\s*:\s*["']([A-Za-z_][\w$]*:\d+)["']/i
      );
    }
    if (!m) {
      m = blob.match(
        /(?:^|[\s,{;])sn\.log\.signature\s*[=:]\s*([A-Za-z_][\w$]*:\d+)/i
      );
    }
    if (!m) {
      m = blob.match(
        /["']sn\.log\.signature["']\s*:\s*["']([A-Za-z_][\w$]*:\d+)["']/i
      );
    }
    if (!m) {
      m = blob.match(
        /(?:^|[\s,{;])log\.signature\s*[=:]\s*([A-Za-z_][\w$]*:\d+)/i
      );
    }
    if (!m) {
      m = blob.match(
        /["']log\.signature["']\s*:\s*["']([A-Za-z_][\w$]*:\d+)["']/i
      );
    }
    return m ? m[1] : this.extractLogClassLineForIncident(gr);
  },

  /**
   * Parse k8s.pod.name from description / additional_info JSON.
   * Pattern: K8s App with short Log4j2 logs (Container Output / Davis stamp).
   */
  extractK8sPodName: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(/k8s\.pod\.name\s*[=:]\s*([A-Za-z0-9][\w.-]*)/i);
    if (!m) {
      m = blob.match(
        /["']k8s\.pod\.name["']\s*:\s*["']([A-Za-z0-9][\w.-]*)["']/i
      );
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
   * Service instance from service_instance stamp (K8s-sanitized display name).
   * Prefer exact name; also match when CMDB name sanitizes to the stamp
   * (Spark-Client ↔ Spark Client). Optional identifier column when isValidField.
   * Returns { sysId, how } or null.
   */
  resolveFromServiceInstance: function (stamp) {
    if (!stamp) {
      return null;
    }

    var candidates = [stamp];
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
                '" (service_instance=' +
                stamp +
                ')',
        };
      }
    }

    // Fallback: scan service instances for sanitized-name match.
    var scan = new GlideRecord('cmdb_ci_service_discovered');
    scan.setLimit(200);
    scan.query();
    while (scan.next()) {
      var nm = scan.name.toString();
      if (this.sanitizeServiceInstanceLabel(nm) === stamp) {
        return {
          sysId: scan.sys_id.toString(),
          how:
            'service instance name "' +
            nm +
            '" (sanitized match for service_instance=' +
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

  /**
   * Parse sn-event_kind from description / additional_info.
   * Dynatrace keeps event.type as a fixed enum; sn-event_kind carries the
   * ServiceNow semantic type (CRITICAL_LOG_EVENT / CPU_EVENT).
   * Legacy: sn.event_kind, log.event_kind.
   */
  extractLogEventKind: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(/sn-event_kind\s*[=:]\s*([A-Za-z0-9_]+)/i);
    if (!m) {
      m = blob.match(
        /["']sn-event_kind["']\s*:\s*["']([A-Za-z0-9_]+)["']/i
      );
    }
    if (!m) {
      m = blob.match(/sn\.event_kind\s*[=:]\s*([A-Za-z0-9_]+)/i);
    }
    if (!m) {
      m = blob.match(
        /["']sn\.event_kind["']\s*:\s*["']([A-Za-z0-9_]+)["']/i
      );
    }
    if (!m) {
      m = blob.match(/log\.event_kind\s*[=:]\s*([A-Za-z0-9_]+)/i);
    }
    if (!m) {
      m = blob.match(
        /["']log\.event_kind["']\s*:\s*["']([A-Za-z0-9_]+)["']/i
      );
    }
    return m ? m[1] : null;
  },

  /**
   * Remap em_event.type / em_alert.type from Dynatrace enum values to
   * sn-event_kind (CRITICAL_LOG_EVENT / CPU_EVENT). Leaves CPU_SATURATED alone.
   */
  applyLogEventTypeRename: function (gr) {
    if (!gr || !gr.isValidField('type')) {
      return;
    }
    var current = gr.type.toString();
    if (current === 'CPU_SATURATED') {
      return;
    }
    var kind = this.extractLogEventKind(gr);
    var next = null;

    if (kind === 'CRITICAL_LOG_EVENT') {
      next = 'CRITICAL_LOG_EVENT';
    } else if (kind === 'CPU_EVENT') {
      next = 'CPU_EVENT';
    } else if (
      current === 'ERROR_EVENT' &&
      (this.extractServiceInstance(gr) || this.extractK8sPodName(gr))
    ) {
      next = 'CRITICAL_LOG_EVENT';
    }

    if (next && next !== current) {
      gr.type = next;
      this.appendProcessingNote(
        gr,
        'em-entity-bind: type ' + current + ' → ' + next + ' (sn-event_kind rename)'
      );
    }
  },

  /**
   * True when sysId is a CSDM service instance (cmdb_ci_service_discovered hierarchy).
   */
  isServiceInstanceCi: function (sysId) {
    if (!sysId) {
      return false;
    }
    var asGr = new GlideRecord('cmdb_ci_service_discovered');
    return asGr.get(sysId);
  },

  /**
   * Resolve the Application Service (service instance) for incident ownership.
   * Does not mutate gr.cmdb_ci (alerts keep infrastructure CI).
   * Returns { sysId, how, stamp } or null.
   */
  resolveServiceInstanceForIncident: function (gr) {
    var serviceInstance = this.extractServiceInstance(gr);
    if (serviceInstance) {
      var asBind = this.resolveFromServiceInstance(serviceInstance);
      if (asBind && asBind.sysId) {
        return {
          sysId: asBind.sysId,
          how: asBind.how,
          stamp: serviceInstance,
        };
      }
    }

    var podName = this.extractK8sPodName(gr);
    if (podName) {
      var byPod = this.resolveFromCloudApplicationInstance(null, podName);
      if (byPod && byPod.asSysId) {
        return {
          sysId: byPod.asSysId,
          how: byPod.how,
          stamp: podName,
        };
      }
    }

    if (gr && !gr.cmdb_ci.nil()) {
      var ciId = gr.cmdb_ci.toString();
      if (this.isServiceInstanceCi(ciId)) {
        return {
          sysId: ciId,
          how: 'alert/event cmdb_ci is already a service instance',
          stamp: gr.cmdb_ci.getDisplayValue() || ciId,
        };
      }
      var fromInfra = this.resolveFromInfrastructureCi(ciId);
      if (fromInfra) {
        return {
          sysId: fromInfra,
          how: 'cmdb_ci→svc_ci_assoc service instance',
          stamp: gr.cmdb_ci.getDisplayValue() || ciId,
        };
      }
    }

    var entity = this.parsePrimaryImpactedEntity(gr);
    if (entity && entity.type === 'CLOUD_APPLICATION_INSTANCE') {
      var cai = this.resolveFromCloudApplicationInstance(
        entity.entityId,
        entity.name
      );
      if (cai && cai.asSysId) {
        return {
          sysId: cai.asSysId,
          how: cai.how,
          stamp: cai.podName || entity.name || '',
        };
      }
    }

    // Group Alert primary: inherit SI from a secondary/member SGO alert.
    if (gr && String(gr.source) === 'Group Alert') {
      return this.resolveServiceInstanceFromAlertGroup(gr);
    }

    return null;
  },

  /**
   * Walk secondary alerts under a Group Alert / primary and resolve SI + signature.
   * Returns { sysId, how, stamp, classLine } or null.
   */
  resolveServiceInstanceFromAlertGroup: function (primaryGr) {
    if (!primaryGr || primaryGr.sys_id.nil()) {
      return null;
    }
    var parentId = primaryGr.sys_id.toString();
    var child = new GlideRecord('em_alert');
    child.addQuery('parent', parentId);
    child.orderBy('sys_created_on');
    child.setLimit(25);
    child.query();
    while (child.next()) {
      var si = this.resolveServiceInstanceForIncident(child);
      if (si && si.sysId) {
        si.classLine = this.extractLogSignature(child);
        si.how = 'group member ' + child.number + ' → ' + si.how;
        return si;
      }
    }
    return null;
  },

  /**
   * True when this alert is an L2I critical log (OpenPipeline stamp).
   */
  isL2iCriticalLogAlert: function (gr) {
    if (!gr) {
      return false;
    }
    if (gr.type && gr.type.toString() === 'CRITICAL_LOG_EVENT') {
      return true;
    }
    var blob = this.collectSparkLookupBlob(gr);
    return blob.indexOf('sn-event_kind=CRITICAL_LOG_EVENT') !== -1 ||
      blob.indexOf('"sn-event_kind":"CRITICAL_LOG_EVENT"') !== -1 ||
      blob.indexOf('sn.event_kind=CRITICAL_LOG_EVENT') !== -1 ||
      blob.indexOf('"sn.event_kind":"CRITICAL_LOG_EVENT"') !== -1 ||
      blob.indexOf('log.event_kind=CRITICAL_LOG_EVENT') !== -1 ||
      blob.indexOf('"log.event_kind":"CRITICAL_LOG_EVENT"') !== -1;
  },

  /**
   * Log4j Class:Line for incident correlation (SI + class:line).
   * Prefer sn-log-class / sn-log-line; legacy dotted forms; Davis text.
   */
  extractLogClassLineForIncident: function (gr) {
    var blob = this.collectSparkLookupBlob(gr);
    var m = blob.match(/["']sn-log-class["']\s*:\s*["']([^"']+)["']/i);
    var lineM = blob.match(/["']sn-log-line["']\s*:\s*["']?(\d+)["']?/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    m = blob.match(/(?:^|[\s,{;])sn-log-class\s*[=:]\s*([A-Za-z_][\w$]*)/i);
    lineM = blob.match(/(?:^|[\s,{;])sn-log-line\s*[=:]\s*(\d+)/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    m = blob.match(/["']sn\.log\.class["']\s*:\s*["']([^"']+)["']/i);
    lineM = blob.match(/["']sn\.log\.line["']\s*:\s*["']?(\d+)["']?/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    m = blob.match(/(?:^|[\s,{;])sn\.log\.class\s*[=:]\s*([A-Za-z_][\w$]*)/i);
    lineM = blob.match(/(?:^|[\s,{;])sn\.log\.line\s*[=:]\s*(\d+)/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    m = blob.match(/["']log\.class["']\s*:\s*["']([^"']+)["']/i);
    lineM = blob.match(/["']log\.line["']\s*:\s*["']?(\d+)["']?/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    m = blob.match(/(?:^|[\s,{;])log\.class\s*[=:]\s*([A-Za-z_][\w$]*)/i);
    lineM = blob.match(/(?:^|[\s,{;])log\.line\s*[=:]\s*(\d+)/i);
    if (m && lineM) {
      return m[1] + ':' + lineM[1];
    }
    return this.extractLog4jClassLine(blob);
  },

  /**
   * Short description used to correlate open incidents: SI + class:line.
   */
  buildCriticalLogIncidentShortDescription: function (classLine) {
    if (classLine) {
      return 'Critical log event — ' + classLine;
    }
    return 'Critical log event';
  },

  /**
   * Generic entity → infrastructure CI bind for SGO-Dynatrace em_event / em_alert:
   *   1. k8s.pod.name → cmdb_ci_kubernetes_pod (K8s pattern; SI used only for incidents)
   *   2. service_instance stamp → prefer HOST ImpactedEntity for alert CI (Standalone)
   *   3. primary ImpactedEntity: HOST / CAI (pod CI, not SI)
   * Service instance ownership is resolved separately for incidents.
   * message_key stays the Dynatrace ProblemID (no class:line mutation).
   */
  applyEntityBinding: function (gr) {
    var result = { bound: false, kind: 'none', note: '', asSysId: '' };

    if (!gr || gr.source.toString() !== 'SGO-Dynatrace') {
      result.note = 'applyEntityBinding: skipped (source is not SGO-Dynatrace)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    this.applyLogEventTypeRename(gr);

    // 1) K8s short Log4j2: bind the pod CI for visibility (not the service instance).
    var podName = this.extractK8sPodName(gr);
    if (podName) {
      var byName = this.resolveFromCloudApplicationInstance(null, podName);
      gr.node = podName;
      gr.resource = 'k8s.pod.name:' + podName;
      this.enrichLogDescription(gr, 'K8s');
      if (byName && byName.podSysId) {
        gr.cmdb_ci = byName.podSysId;
        result.bound = true;
        result.kind = 'k8s_pod_name';
        result.asSysId = byName.asSysId || '';
        result.note =
          'em-entity-bind: k8s.pod.name=' +
          podName +
          ' → pod CI' +
          (byName.asSysId
            ? ' (service instance available via ' + byName.how + ')'
            : ' (' + (byName.how || 'no SI membership yet') + ')');
        this.appendProcessingNote(gr, result.note);
        return result;
      }
      result.kind = 'k8s_pod_name';
      result.note =
        'em-entity-bind: k8s.pod.name=' +
        podName +
        ' — ' +
        (byName && byName.how
          ? byName.how
          : 'no cmdb_ci_kubernetes_pod by name') +
        '; cmdb_ci left empty';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    // 2) Standalone short Log4j2: stamp identifies SI for incidents; alert CI = HOST.
    var serviceInstance = this.extractServiceInstance(gr);
    if (serviceInstance) {
      gr.node = serviceInstance;
      gr.resource = 'service_instance:' + serviceInstance;
      this.enrichLogDescription(gr, 'Standalone');
      var entitySi = this.parsePrimaryImpactedEntity(gr);
      if (entitySi && entitySi.type === 'HOST') {
        var hostSi = this.resolveFromHost(entitySi.entityId, entitySi.name);
        if (hostSi) {
          gr.cmdb_ci = hostSi.sysId;
          result.bound = true;
          result.kind = 'standalone_host';
          result.note =
            'em-entity-bind: service_instance=' +
            serviceInstance +
            ' stamped; alert CI=HOST via ' +
            hostSi.how +
            ' (SI reserved for incident)';
          this.appendProcessingNote(gr, result.note);
          return result;
        }
      }
      result.kind = 'standalone_host';
      result.note =
        'em-entity-bind: service_instance=' +
        serviceInstance +
        ' stamped; no HOST CI for alert (SI used only at incident create)';
      this.appendProcessingNote(gr, result.note);
      return result;
    }

    // 3) Primary ImpactedEntity (HOST for CPU; CAI → pod CI).
    var entity = this.parsePrimaryImpactedEntity(gr);
    if (!entity) {
      result.note =
        'em-entity-bind: no service_instance / k8s.pod.name and no primary impacted entity (HOST / CLOUD_APPLICATION_INSTANCE)';
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

    if (entity.type === 'CLOUD_APPLICATION_INSTANCE') {
      var pod = this.resolveFromCloudApplicationInstance(
        entity.entityId,
        entity.name
      );
      if (!pod || !pod.podSysId) {
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
        gr.resource = 'k8s.pod.name:' + pod.podName;
      }
      gr.cmdb_ci = pod.podSysId;
      result.bound = true;
      result.kind = 'cai';
      result.asSysId = pod.asSysId || '';
      result.note =
        'em-entity-bind: CAI→pod CI' +
        (pod.asSysId ? ' (' + pod.how + ')' : '');
      this.appendProcessingNote(gr, result.note);
      this.enrichLogDescription(gr, 'K8s');
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
      /[Cc]ritical\s+(?:WARN|ERROR)\s+(?:error\s+)?(?:at\s+)?([A-Za-z_][\w$]*):(\d+)/
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

  extractLogIdentity: function (text, patternHint) {
    var classLine = this.extractLog4jClassLine(text);
    if (!classLine) {
      return null;
    }
    var parts = classLine.split(':');
    var pattern = patternHint || '';
    if (!pattern) {
      return null;
    }
    return {
      pattern: pattern,
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
  buildLogDql: function (identity, window, maxLines) {
    maxLines = maxLines || 100;
    return (
      'fetch logs\n' +
      '| filter timestamp >= toTimestamp("' +
      window.fromIso +
      '") and timestamp <= toTimestamp("' +
      window.toIso +
      '")\n' +
      '| filter log.class == "' +
      identity.className +
      '" and log.line == ' +
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
  enrichLogDescription: function (gr, patternHint) {
    var marker = '--- Matching log lines (DQL) ---';
    var desc = gr.description ? gr.description.toString() : '';
    var stripFrom = desc.indexOf(marker);
    if (stripFrom === -1) {
      stripFrom = desc.indexOf('--- L2I enrichment ---');
    }
    if (stripFrom === -1) {
      stripFrom = desc.indexOf('--- Matching Spark log lines (DQL) ---');
    }
    if (stripFrom > 0) {
      desc = desc.substring(0, stripFrom).replace(/\s+$/, '');
    }

    var identity = this.extractLogIdentity(desc, patternHint);
    if (!identity) {
      return false;
    }

    var window = this.buildProblemTimeWindow(gr, 24);
    var block =
      marker +
      '\n' +
      this.buildLogDql(identity, window, 100) +
      '\n';
    var combined = desc + '\n\n' + block;
    if (combined.length > 4000) {
      combined = combined.substring(0, 3980) + '\n...[truncated]';
    }
    gr.description = combined;
    return true;
  },

  /**
   * Intentionally a no-op: em_event.message_key must remain the Dynatrace
   * ProblemID for OPEN/RESOLVED lifecycle. Incident correlation uses
   * service instance + class:line on short_description instead.
   */
  appendClassLineToMessageKey: function (/* gr, prefix */) {
    return;
  },

  type: 'ResolveApplicationService',
};
