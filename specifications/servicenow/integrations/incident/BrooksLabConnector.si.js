/**
 * BrooksLabConnector — which events and alerts came through the brooks-lab Dynatrace connector.
 *
 * The connector is identified at the event, where it is unambiguous. Two receivers:
 *   - the brooks-lab push connector instance (Dynatrace Monitor Push Connector, source
 *     "Dynatrace"), fed by the brooks-lab Dynatrace workflow: the listener sets event_class to the
 *     instance name, which is the connector class, and the payload carries sn_source "dynatrace";
 *   - legacy: the SGO-Dynatrace push receiver, fed by the classic problem notification, when the
 *     event carries one of brooks-lab's SGC connection ids (additional_info.ConnectionId). Such an
 *     event is stamped with event_class = <connector class>.
 * The class is property brooks_lab.connector.event_class; the alert an event creates keeps it.
 * Alert rules, correlation definitions and business rules then filter on event_class instead of
 * alert source: the alert source is not a reliable marker on this shared instance (some
 * SGO-Dynatrace events open alerts whose source reads "Dynatrace").
 *
 * Group alerts carry no class of their own; when one of our alerts joins a group, the group is
 * stamped too, so the primary-alert rule can be scoped the same way.
 *
 * Properties (set by playbooks/servicenow/incident/deploy.yml):
 *   brooks_lab.connector.event_class        e.g. "brooks-lab"
 *   brooks_lab.connector.sgc_connection_ids comma-separated connection alias sys_ids (legacy SGC
 *                                           and SGC SaaS); empty = any SGO-Dynatrace event
 * Representation: specifications/servicenow/integrations/incident/BrooksLabConnector.si.js
 */
var BrooksLabConnector = Class.create();
BrooksLabConnector.RECEIVER_SOURCE = 'SGO-Dynatrace';
BrooksLabConnector.PUSH_SOURCE = 'Dynatrace';
BrooksLabConnector.prototype = {
  initialize: function () {
    this.eventClass = String(gs.getProperty('brooks_lab.connector.event_class', 'brooks-lab'));
    var ids = String(gs.getProperty('brooks_lab.connector.sgc_connection_ids', ''));
    this.connectionIds = ids ? ids.split(/\s*,\s*/) : [];
  },

  /** Parsed additional_info of an event or alert ({} when empty or not JSON). */
  additionalInfo: function (gr) {
    try {
      return JSON.parse(gr.getValue('additional_info') || '{}') || {};
    } catch (e) {
      return {};
    }
  },

  /**
   * em_event: arrived on the brooks-lab push connector instance (its name is our class), or on the
   * SGO-Dynatrace receiver with one of our connection ids.
   */
  isOurEvent: function (ev) {
    if (!ev) {
      return false;
    }
    if (String(ev.source) === BrooksLabConnector.PUSH_SOURCE) {
      return String(ev.event_class) === this.eventClass &&
        String(this.additionalInfo(ev).sn_source || '') === 'dynatrace';
    }
    if (String(ev.source) !== BrooksLabConnector.RECEIVER_SOURCE) {
      return false;
    }
    if (this.connectionIds.length === 0) {
      return true;
    }
    var connectionId = String(this.additionalInfo(ev).ConnectionId || '');
    return this.connectionIds.indexOf(connectionId) !== -1;
  },

  /** em_event before insert/update: stamp our connector class. Returns true for our events. */
  stampEvent: function (ev) {
    if (!this.isOurEvent(ev)) {
      return false;
    }
    if (String(ev.event_class) !== this.eventClass) {
      ev.event_class = this.eventClass;
    }
    return true;
  },

  /**
   * em_alert (or em_event): ours when it carries our connector class. A group alert is ours when
   * it was stamped, or when any of its member alerts carries our class.
   */
  isOurRecord: function (gr) {
    if (!gr) {
      return false;
    }
    if (gr.getTableName() === 'em_event') {
      return this.isOurEvent(gr) || String(gr.event_class) === this.eventClass;
    }
    if (String(gr.event_class) === this.eventClass) {
      return true;
    }
    if (String(gr.source) === 'Group Alert') {
      var member = new GlideRecord('em_alert');
      member.addQuery('parent', gr.getUniqueValue());
      member.addQuery('event_class', this.eventClass);
      member.setLimit(1);
      member.query();
      return member.hasNext();
    }
    return false;
  },

  /**
   * Our alert joined a group: give the group alert our class (once), and when a member already has
   * an incident and the group has none, attach the group to that incident. Without this the
   * primary-alert rule (incidentISEMPTY) opens a second incident for the group of an alert that was
   * ticketed before the grouping job ran. Both changes land in one update, so the rule never sees
   * a group with our class and no incident.
   */
  stampGroupOf: function (alert) {
    if (!alert || alert.parent.nil() || String(alert.event_class) !== this.eventClass) {
      return false;
    }
    var group = new GlideRecord('em_alert');
    if (!group.get(alert.parent.toString())) {
      return false;
    }
    if (group.getUniqueValue() === alert.getUniqueValue()) {
      return false; // an alert is never its own group
    }
    var changed = false;
    if (String(group.event_class) !== this.eventClass) {
      group.event_class = this.eventClass;
      changed = true;
    }
    if (group.incident.nil()) {
      var incidentId = alert.incident.nil() ? '' : alert.incident.toString();
      if (!incidentId) {
        var member = new GlideRecord('em_alert');
        member.addQuery('parent', group.getUniqueValue());
        member.addNotNullQuery('incident');
        member.addQuery('incident.active', true);
        member.addQuery('incident.state', '<', 6); // not Resolved/Closed/Canceled
        member.orderBy('sys_created_on');
        member.setLimit(1);
        member.query();
        if (member.next()) {
          incidentId = member.getValue('incident');
        }
      }
      if (incidentId) {
        group.incident = incidentId;
        group.work_notes = 'brooks-lab: attached to incident of member alert ' + alert.number +
          ' (no second incident for the group).';
        changed = true;
      }
    }
    if (changed) {
      group.update();
    }
    return changed;
  },

  type: 'BrooksLabConnector',
};
