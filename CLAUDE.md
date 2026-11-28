# Claude Code instructions for spark-observability

Project conventions also live in `.cursor/rules/`; follow them as well.

## Deep links to operational records

Whenever a reply, report or document mentions a specific operational record, make it a clickable
deep link, not a bare number. This covers Dynatrace problems, ServiceNow alerts, incidents, CIs,
services, offerings, dynamic CI groups, alert/management rules, and any other record with a URL.
Put the link on the record's human-facing ID (P-…, Alert…, INC…, CI name), and link every record
in tables too. If a sys_id or problem ID is not at hand, look it up before answering rather than
leaving the reference unlinked.

URL formats (take the hosts from the active instance and the Dynatrace vars; never guess them):

- Dynatrace problem: `<DT_UI_URL>/#problems/problemdetails;pid=<problemId>`
  (problemId is the long `…V2` ID, not the P-number)
- Dynatrace entity: `<DT_UI_URL>/#newservices/serviceOverview;id=<SERVICE-…>` for services,
  otherwise `<DT_UI_URL>/ui/entity/<ENTITY-ID>`
- ServiceNow record: `https://<instance>.service-now.com/nav_to.do?uri=<table>.do%3Fsys_id%3D<sys_id>`
  (em_alert, incident, cmdb_ci, cmdb_ci_service_auto, service_offering, cmdb_ci_query_based_service,
  em_alert_management_rule, …)
