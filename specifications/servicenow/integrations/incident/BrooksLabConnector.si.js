/**
 * BrooksLabConnector — which events and alerts came through the brooks-lab Dynatrace connector.
 *
 * The connector is identified at the event, where it is unambiguous: an event that arrived on the
 * SGO-Dynatrace push receiver carrying one of brooks-lab's SGC connection ids in its payload
 * (additional_info.ConnectionId; the Dynatrace problem notification sends it). Such an event is
 * stamped with event_class = <connector class> (property brooks_lab.connector.event_class), and
 * the alert it creates keeps that class. Alert rules, correlation definitions and business rules
 * then filter on event_class instead of alert source: the alert source is not a reliable marker on
 * this shared instance (some SGO-Dynatrace events open alerts whose source reads "Dynatrace").
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

  /** em_event: arrived on the SGO-Dynatrace receiver with one of our connection ids. */
  isOurEvent: function (ev) {
    if (!ev || String(ev.source) !== BrooksLabConnector.RECEIVER_SOURCE) {
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

  /** Our alert joined a group: give the group alert our class (once). */
  stampGroupOf: function (alert) {
    if (!alert || alert.parent.nil() || String(alert.event_class) !== this.eventClass) {
      return false;
    }
    var group = new GlideRecord('em_alert');
    if (!group.get(alert.parent.toString())) {
      return false;
    }
    if (String(group.event_class) === this.eventClass) {
      return false;
    }
    group.event_class = this.eventClass;
    group.update();
    return true;
  },

  type: 'BrooksLabConnector',
};
