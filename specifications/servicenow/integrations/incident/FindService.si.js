/**
 * FindService — CI -> Service Instance / Dynamic CI Group -> Service Offering (BSO/TSO) -> Service,
 * with an alert-tag fallback when the CSDM graph comes up empty, writing the Incident's
 * service_offering and business_service as each hop resolves.
 *
 * Server-side (ES5, synchronous GlideRecord) implementation of findService.js (the design's
 * pseudocode). Same contract: no find*() method throws; each returns the record it found
 * (GlideRecord) or null, so the pipeline composes with plain `||`. The backbone, in
 * resolveServiceForAlert, is the pseudocode's expression:
 *
 *   var service = this.findService(alert, incident,
 *     this.findServiceOffering(alert, incident,
 *       this.findServiceInstance(alert, ci) || this.findDynamicCIGroup(alert, ci)));
 *
 * Differences from the pseudocode, for this instance's data model:
 *   - The Incident is not created here: the brooks-lab alert management rule creates it, and the
 *     business rule em-alert-find-service runs this pipeline the moment the alert gets its incident.
 *   - findServiceInstance accepts only service instances linked to an offering (CSDM-modelled).
 *     Dynatrace-generated calculated services (cmdb_ci_service_calculated, e.g. "My web
 *     application") also hold infrastructure CIs in svc_ci_assoc but belong to no offering;
 *     taking one would end the pipeline at a dead end and hide the Dynamic CI Group path.
 *     Skipped candidates are logged.
 *   - Dynamic CI Groups hang off their Technical offering with Contains::Contained by (CSDM 5,
 *     as sn-sync creates them), service instances with Depends on::Used by; findServiceOffering
 *     accepts both.
 *   - A Technical offering is recognised by service_classification = "Technical Service" (this
 *     instance's field; there is no consumer_type).
 *   - The activity log is collected and written once, as one work note on the alert and on the
 *     incident, instead of one journal entry per line.
 *
 * Properties: brooks_lab.find_service.default_service_instance (name or sys_id; empty = none).
 * Alert tags (additional_info): snow_service_offering, snow_business_service (display names).
 * Representation: specifications/servicenow/integrations/incident/FindService.si.js
 */
var FindService = Class.create();
FindService.ALERT_TAG_KEYS = {
  serviceOffering: 'snow_service_offering',
  businessService: 'snow_business_service',
};
FindService.REL_TYPES = ['Depends on::Used by', 'Contains::Contained by'];
FindService.prototype = {
  initialize: function () {
    this.lines = [];
  },

  // ---------------------------------------------------------------------------
  // Activity log: every happy and sad path writes one line, naming the source of
  // the value (CSDM graph, alert tag, configured default).
  // ---------------------------------------------------------------------------
  logActivity: function (alert, level, stage, message) {
    this.lines.push('[' + stage + '] ' + String(level).toUpperCase() + ': ' + message);
  },

  flushActivityLog: function (alert, incident) {
    if (this.lines.length === 0) {
      return;
    }
    var note = 'find-service:\n' + this.lines.join('\n');
    this.lines = [];
    var targets = [['em_alert', alert], ['incident', incident]];
    for (var i = 0; i < targets.length; i++) {
      var rec = targets[i][1];
      if (!rec) {
        continue;
      }
      if (rec.isNewRecord()) {
        rec.work_notes = note; // saved with the incident insert
        continue;
      }
      var gr = new GlideRecord(targets[i][0]);
      if (gr.get(rec.getUniqueValue())) {
        gr.work_notes = note;
        gr.update();
      }
    }
  },

  describe: function (gr) {
    return gr ? gr.getUniqueValue() + ' (' + gr.getDisplayValue() + ')' : 'none';
  },

  pickFirstAndLogIfAmbiguous: function (alert, stage, candidates, describe) {
    if (candidates.length > 1) {
      var names = [];
      for (var i = 0; i < candidates.length; i++) {
        names.push(describe(candidates[i]));
      }
      this.logActivity(
        alert, 'warn', stage,
        'Found ' + candidates.length + ' candidates (expected at most 1): ' + names.join(', ') +
        '. Using the first; this indicates a data-model integrity issue worth fixing upstream, ' +
        'not a legitimate tie to break silently.'
      );
    }
    return candidates[0];
  },

  /** The CI record in its own class (so instanceOf and class-specific fields work), or null. */
  getCi: function (sysId) {
    if (!sysId) {
      return null;
    }
    var base = new GlideRecord('cmdb_ci');
    if (!base.get(sysId)) {
      return null;
    }
    var gr = new GlideRecord(base.getValue('sys_class_name'));
    return gr.get(sysId) ? gr : null;
  },

  additionalInfo: function (alert) {
    try {
      return JSON.parse(alert.getValue('additional_info') || '{}') || {};
    } catch (e) {
      return {};
    }
  },

  relTypeIds: function () {
    if (this._relTypeIds) {
      return this._relTypeIds;
    }
    var ids = [];
    var rt = new GlideRecord('cmdb_rel_type');
    rt.addQuery('name', 'IN', FindService.REL_TYPES.join(','));
    rt.query();
    while (rt.next()) {
      ids.push(rt.getUniqueValue());
    }
    this._relTypeIds = ids;
    return ids;
  },

  /** Offering relationships (parent = service_offering, child = subject). */
  getOfferingRelationshipsFor: function (subjectSysId) {
    var rels = [];
    var rel = new GlideRecord('cmdb_rel_ci');
    rel.addQuery('child', subjectSysId);
    rel.addQuery('type', 'IN', this.relTypeIds().join(','));
    rel.addQuery('parent.sys_class_name', 'service_offering');
    rel.orderBy('sys_created_on');
    rel.query();
    while (rel.next()) {
      rels.push({ parent: rel.getValue('parent'), type: rel.type.getDisplayValue() });
    }
    return rels;
  },

  updateIncident: function (incident, fields) {
    if (!incident) {
      return;
    }
    if (incident.isNewRecord()) {
      // Called from the incident populator before insert: set the fields, the insert saves them.
      for (var k in fields) {
        if (fields.hasOwnProperty(k)) {
          incident.setValue(k, fields[k]);
        }
      }
      return;
    }
    var changed = false;
    for (var f in fields) {
      if (fields.hasOwnProperty(f) && incident.getValue(f) !== fields[f]) {
        incident.setValue(f, fields[f]);
        changed = true;
      }
    }
    if (changed) {
      incident.update();
    }
  },

  // ---------------------------------------------------------------------------
  // Alert-tag fallbacks (take only the alert).
  // ---------------------------------------------------------------------------
  findFallbackServiceOffering: function (alert) {
    var key = FindService.ALERT_TAG_KEYS.serviceOffering;
    var offeringName = this.additionalInfo(alert)[key];
    if (offeringName) {
      var offering = new GlideRecord('service_offering');
      if (offering.get('name', offeringName)) {
        this.logActivity(alert, 'warn', 'serviceOffering',
          'Resolved offering ' + this.describe(offering) + " from the '" + key +
          "' alert tag value '" + offeringName + "'.");
        return offering;
      } else {
        this.logActivity(alert, 'warn', 'serviceOffering',
          "'" + key + "' alert tag value '" + offeringName + "' did not match any Service Offering by name.");
        return null;
      }
    } else {
      this.logActivity(alert, 'info', 'serviceOffering',
        "No '" + key + "' tag present on the alert to fall back to.");
      return null;
    }
  },

  findFallbackService: function (alert) {
    var key = FindService.ALERT_TAG_KEYS.businessService;
    var serviceName = this.additionalInfo(alert)[key];
    if (serviceName) {
      var service = new GlideRecord('cmdb_ci_service');
      service.addQuery('name', serviceName);
      service.addQuery('sys_class_name', '!=', 'service_offering');
      service.setLimit(1);
      service.query();
      if (service.next()) {
        this.logActivity(alert, 'warn', 'service',
          'Resolved Business Service ' + this.describe(service) + " from the '" + key +
          "' alert tag value '" + serviceName + "'.");
        return service;
      } else {
        this.logActivity(alert, 'warn', 'service',
          "'" + key + "' alert tag value '" + serviceName + "' did not match any Business Service by name.");
        return null;
      }
    } else {
      this.logActivity(alert, 'info', 'service',
        "No '" + key + "' tag present on the alert to fall back to.");
      return null;
    }
  },

  // ---------------------------------------------------------------------------
  // Dynamic CI Group membership lookup only (svc_ci_assoc, service is a DCG).
  // ---------------------------------------------------------------------------
  findDynamicCIGroup: function (alert, ci) {
    if (!ci) {
      this.logActivity(alert, 'warn', 'dynamicCiGroup', 'Alert has no CI to check Dynamic CI Group membership for.');
      return null;
    } else {
      var groups = [];
      var assoc = new GlideRecord('svc_ci_assoc');
      assoc.addQuery('ci_id', ci.getUniqueValue());
      assoc.addQuery('service_id.sys_class_name', 'cmdb_ci_query_based_service');
      assoc.query();
      while (assoc.next()) {
        var g = this.getCi(assoc.getValue('service_id'));
        if (g) {
          groups.push(g);
        }
      }
      if (groups.length === 0) {
        this.logActivity(alert, 'info', 'dynamicCiGroup',
          'CI ' + this.describe(ci) + ' is not a member of any Dynamic CI Group.');
        return null;
      } else {
        var self = this;
        var group = this.pickFirstAndLogIfAmbiguous(alert, 'dynamicCiGroup', groups,
          function (x) { return 'group=' + self.describe(x); });
        this.logActivity(alert, 'info', 'dynamicCiGroup',
          'CI ' + this.describe(ci) + ' is a member of Dynamic CI Group ' + this.describe(group) + '.');
        return group;
      }
    }
  },

  // ---------------------------------------------------------------------------
  // findServiceInstance(alert, ci)
  //   1. svc_ci_assoc membership (ci_id = ci) in a service instance linked to an offering
  //   2. CI is itself a service instance (cmdb_ci_service_auto, not a Dynamic CI Group)
  //   3. the configured default service instance, or null
  // ---------------------------------------------------------------------------
  findServiceInstance: function (alert, ci) {
    if (!ci) {
      this.logActivity(alert, 'warn', 'serviceInstance', 'Alert has no CI to resolve a service instance from.');
      return null;
    } else {
      var linked = [];
      var unlinked = [];
      var seen = {};
      var assoc = new GlideRecord('svc_ci_assoc');
      assoc.addQuery('ci_id', ci.getUniqueValue());
      assoc.addQuery('service_id.sys_class_name', '!=', 'cmdb_ci_query_based_service');
      assoc.query();
      while (assoc.next()) {
        var sid = assoc.getValue('service_id');
        if (seen[sid]) {
          continue;
        }
        seen[sid] = true;
        var svc = this.getCi(sid);
        if (!svc) {
          continue;
        }
        (this.getOfferingRelationshipsFor(sid).length > 0 ? linked : unlinked).push(svc);
      }
      if (unlinked.length > 0) {
        var names = [];
        for (var i = 0; i < unlinked.length; i++) {
          names.push(this.describe(unlinked[i]));
        }
        this.logActivity(alert, 'info', 'serviceInstance',
          'Ignored ' + unlinked.length + ' service(s) holding CI ' + this.describe(ci) +
          ' that belong to no offering (not CSDM-modelled): ' + names.join(', ') + '.');
      }

      if (linked.length > 0) {
        var self = this;
        var serviceInstance = this.pickFirstAndLogIfAmbiguous(alert, 'serviceInstance', linked,
          function (x) { return 'service_id=' + self.describe(x); });
        this.logActivity(alert, 'info', 'serviceInstance',
          'Resolved CI ' + this.describe(ci) + ' to service instance ' + this.describe(serviceInstance) +
          ' via svc_ci_assoc.');
        return serviceInstance;
      } else {
        var isInstanceItself = ci.instanceOf('cmdb_ci_service_auto') && !ci.instanceOf('cmdb_ci_query_based_service');
        if (isInstanceItself) {
          this.logActivity(alert, 'info', 'serviceInstance',
            'CI ' + this.describe(ci) + ' is itself a service instance; using it directly.');
          return ci;
        } else {
          var defaultInstance = this.getDefaultServiceInstance();
          if (defaultInstance) {
            this.logActivity(alert, 'warn', 'serviceInstance',
              'CI ' + this.describe(ci) + ' has no svc_ci_assoc membership in a modelled service instance ' +
              'and is not itself a service instance; using the configured default service instance ' +
              this.describe(defaultInstance) + ' instead. This is a CSDM coverage gap worth closing, ' +
              'not a transient miss.');
          } else {
            this.logActivity(alert, 'info', 'serviceInstance',
              'CI ' + this.describe(ci) + ' has no svc_ci_assoc membership in a modelled service instance, ' +
              'is not itself a service instance, and no default service instance is configured either.');
          }
          return defaultInstance; // may be null: a valid, final answer here.
        }
      }
    }
  },

  getDefaultServiceInstance: function () {
    var ref = String(gs.getProperty('brooks_lab.find_service.default_service_instance', '') || '');
    if (!ref) {
      return null;
    }
    var gr = new GlideRecord('cmdb_ci_service_auto');
    if (gr.get(ref) || gr.get('name', ref)) {
      return this.getCi(gr.getUniqueValue());
    }
    return null;
  },

  // ---------------------------------------------------------------------------
  // CSDM 5 check: a Dynamic CI Group should relate only to a Technical offering.
  // ---------------------------------------------------------------------------
  warnIfDynamicCIGroupOfferingNotTechnical: function (alert, subject, offering) {
    var subjectIsDynamicCIGroup = subject.instanceOf('cmdb_ci_query_based_service');
    if (subjectIsDynamicCIGroup) {
      var isTechnicalOffering = String(offering.getValue('service_classification')) === 'Technical Service';
      if (isTechnicalOffering) {
        // Correctly a Technical offering: nothing to warn about.
      } else {
        this.logActivity(alert, 'warn', 'serviceOffering',
          'DCG_RELATED_TO_BSO_NOT_TSO: Dynamic CI Group ' + this.describe(subject) + ' is related to offering ' +
          this.describe(offering) + ', which is not a Technical Service offering. Per CSDM 5 a Dynamic CI ' +
          'Group should relate only to a technical offering; a data-quality issue on the relationship. ' +
          'The resolution itself still succeeded with this offering.');
      }
    } else {
      // Subject is a service instance: this check does not apply.
    }
  },

  // ---------------------------------------------------------------------------
  // findServiceOffering(alert, incident, subject): sets incident.service_offering.
  // ---------------------------------------------------------------------------
  findServiceOffering: function (alert, incident, subject) {
    if (!subject) {
      this.logActivity(alert, 'warn', 'serviceOffering',
        'No service instance or Dynamic CI Group was found for this CI; trying the alert-tag fallback directly.');
      var fallbackOffering = this.findFallbackServiceOffering(alert);
      if (fallbackOffering) {
        this.updateIncident(incident, { service_offering: fallbackOffering.getUniqueValue() });
        return fallbackOffering;
      } else {
        this.logActivity(alert, 'error', 'serviceOffering',
          'No subject was available for this alert, and the alert-tag fallback did not resolve a Service Offering either.');
        return null;
      }
    } else {
      var rels = this.getOfferingRelationshipsFor(subject.getUniqueValue());
      if (rels.length > 0) {
        var rel = this.pickFirstAndLogIfAmbiguous(alert, 'serviceOffering', rels,
          function (r) { return 'offering=' + r.parent; });
        var offering = new GlideRecord('service_offering');
        offering.get(rel.parent);
        this.logActivity(alert, 'info', 'serviceOffering',
          'Resolved ' + this.describe(subject) + ' to offering ' + this.describe(offering) +
          ' via the CSDM graph (' + rel.type + ').');
        this.warnIfDynamicCIGroupOfferingNotTechnical(alert, subject, offering);
        this.updateIncident(incident, { service_offering: offering.getUniqueValue() });
        return offering;
      } else {
        this.logActivity(alert, 'warn', 'serviceOffering',
          this.describe(subject) + ' has no BSO/TSO relationship via the CSDM graph; trying the alert-tag fallback.');
        var fallback = this.findFallbackServiceOffering(alert);
        if (fallback) {
          this.warnIfDynamicCIGroupOfferingNotTechnical(alert, subject, fallback);
          this.updateIncident(incident, { service_offering: fallback.getUniqueValue() });
          return fallback;
        } else {
          this.logActivity(alert, 'error', 'serviceOffering',
            this.describe(subject) + ' has no BSO/TSO relationship via the CSDM graph, and the alert-tag ' +
            'fallback did not resolve a Service Offering either.');
          return null;
        }
      }
    }
  },

  // ---------------------------------------------------------------------------
  // findService(alert, incident, serviceOffering): sets incident.business_service from the
  // offering's native parent field (a Business Service, or a Technology Management Service).
  // ---------------------------------------------------------------------------
  findService: function (alert, incident, serviceOffering) {
    if (!serviceOffering) {
      this.logActivity(alert, 'warn', 'service', 'No Service Offering was found; trying the alert-tag fallback directly.');
      var fallbackService = this.findFallbackService(alert);
      if (fallbackService) {
        this.updateIncident(incident, { business_service: fallbackService.getUniqueValue() });
        return fallbackService;
      } else {
        this.logActivity(alert, 'error', 'service',
          'No Service Offering was available for this alert, and the alert-tag fallback did not resolve a Business Service either.');
        return null;
      }
    } else {
      var parentSysId = serviceOffering.getValue('parent');
      if (parentSysId) {
        var service = this.getCi(parentSysId);
        this.logActivity(alert, 'info', 'service',
          'Resolved offering ' + this.describe(serviceOffering) + ' to service ' + this.describe(service) +
          ' via its parent field.');
        this.updateIncident(incident, { business_service: parentSysId });
        return service;
      } else {
        this.logActivity(alert, 'warn', 'service',
          'Offering ' + this.describe(serviceOffering) + ' has no parent service set; trying the alert-tag fallback.');
        var fallback = this.findFallbackService(alert);
        if (fallback) {
          this.updateIncident(incident, { business_service: fallback.getUniqueValue() });
          return fallback;
        } else {
          this.logActivity(alert, 'error', 'service',
            'Offering ' + this.describe(serviceOffering) + ' has no parent service set, and the alert-tag ' +
            'fallback did not resolve a Business Service either.');
          return null;
        }
      }
    }
  },

  /** The alert's CI (em_alert has one cmdb_ci), or null. */
  selectPrincipalCiForAlert: function (alert) {
    var ci = alert.cmdb_ci.nil() ? null : this.getCi(alert.getValue('cmdb_ci'));
    if (!ci) {
      this.logActivity(alert, 'warn', 'input', 'Alert has no associated CI at all.');
    }
    return ci;
  },

  /**
   * Main entry point: the alert and the incident the alert management rule created for it.
   * Returns { incident, service } (service may be null).
   */
  resolveServiceForAlert: function (alert, incident) {
    var ci = this.selectPrincipalCiForAlert(alert); // may be null

    var service = this.findService(alert, incident,
      this.findServiceOffering(alert, incident,
        this.findServiceInstance(alert, ci) || this.findDynamicCIGroup(alert, ci)));

    this.flushActivityLog(alert, incident);
    return { incident: incident, service: service };
  },

  type: 'FindService',
};
