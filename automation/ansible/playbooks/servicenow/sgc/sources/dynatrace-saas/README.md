# SGC for Observability - Dynatrace SaaS (`sn_dynatrace_saas`)

Brooks-lab's topology feed from the Dynatrace 3rd-generation platform. The connector runs
`smartscapeNodes` / `smartscapeEdges` DQL with a platform token and writes CIs with discovery source
**SGO-Dynatrace SaaS**. It replaces the legacy SGC's topology imports (`sources/dynatrace/`).

The legacy app (`sn_dynatrace_integ`) stays installed for two reasons:
- Its push listener "Dynatrace Observability" (source SGO-Dynatrace) still receives Dynatrace problem events
  for instances on the classic notification path (see "Event path" below).
- `sources/dynatrace/stop.yml` only deactivates its root imports.

| Playbook | Verb | What it does |
| --- | --- | --- |
| `deploy.yml` | deploy | Points the app's default connection (alias `sn_dynatrace_saas.Dynatrace_SaaS`) at the tenant (`DT_TENANT_URL`); writes the platform token into its credential; sets the connection properties; activates the root imports hourly. It checks the token before any write. |
| `start.yml` | start | Runs Execute Now on the root imports (SaaS Host, SaaS K8s Cluster), waits for the import sets, and restores the hourly cadence. |
| `test.yml` | test | Checks the connection status is Success, the roots are active, and fresh SaaS CIs exist for the cluster and the eShop/Spark deployments. |
| `diagnose.yml` | diagnose | Read-only report: app version, connection, token check, roots (SaaS and legacy), and CI counts by source. |

Order: `deploy.yml` → `start.yml` → `test.yml` → `../dynatrace/stop.yml`, which disables the legacy topology imports.

## Event path: Dynatrace workflow → brooks-lab push connector

The event path paired with this connector replaces the classic problem notification to the legacy
SGO-Dynatrace receiver. It is used for instances with `SN_INSTANCES[].dt_event_path: workflow`
(`vars/variables.yaml`); `deploy.yml` then also creates:

| Where | Record | Representation / task |
| --- | --- | --- |
| ServiceNow | push connector instance `brooks-lab` on the "Dynatrace Monitor Push Connector" listener, `connection_sys_id` = the SaaS connection, so alerts bind to SaaS-imported CIs | `tasks/ensure-push-connector.yml` |
| Dynatrace | ITOM event connection `dt_itom_connection_name` (Dynatrace ServiceNow app) to that instance's URL, as the `SN_DT_WEBHOOK_*` account | `tasks/ensure-dt-problem-workflow.yml` |
| Dynatrace | workflow `dt_problem_workflow_name`: every problem of the brooks-lab alerting profile, open and close → DQL for the problem's Davis event properties (`sn-*`, `k8s-*`) → "Send ITOM event" (`dynatrace.servicenow:snow-send-event`) | `specifications/dynatrace/integrations/sn-problem-workflow.json.j2` |

The instance's classic notification stays disabled, and `servicenow/tasks/target.yml` switches the
workflow trigger (`isActive`) when the active instance changes; `servicenow/sn_active_instance.py`
reads it too.

**One manual step.** A workflow runs as its actor, the Dynatrace user who owns
`DT_AUTOMATION_PLATFORM_TOKEN`. That user must grant the Workflows app its permissions once:
Workflows → Settings → **Authorization settings** (at least `app-engine:apps:run`,
`storage:events:read`, `storage:buckets:read`, `app-settings:objects:read`). Until then every run
fails with "Please ensure Authorization Settings are configured for this user".

Cut-over (per instance): grant the authorization, set `dt_event_path: workflow`, run `deploy.yml`,
verify a problem reaches an incident, then deactivate the legacy SGC's connections.

Prerequisites:

- `sn_dynatrace_saas` installed and active. Demo1 has 1.2.0. Demo3's install is broken; ServiceNow is investigating.
- `vars/secrets.yaml` → `dynatrace.DT_SERVICENOW_TOKEN`: the read-only platform token ServiceNow holds
  (class 3 in [`vars/docs/secrets.md`](../../../../../../../vars/docs/secrets.md)); the connector needs
  `storage:smartscape:read`.
  Platform tokens are created in the Dynatrace UI (Account Management, or the tenant's Settings > Access tokens > Platform tokens).
  No API in this repo can mint them.

Other connections on the instance, such as people's own SGC Central connections with their own aliases and
schedule sets, are not touched.

Scope: `segment_id` is empty, so the connector imports the whole tenant. A brooks-lab Dynatrace segment would
narrow it, the way the management zone does for the legacy connector.

## Behaviour confirmed on Demo1 (2026-11-26)

- `http_connection.connection_url` is rebuilt from `protocol` + `host` on save, so `deploy.yml` sets
  `host`; a PATCH of `connection_url` alone is silently overwritten.
- The connection's `status`/`message` come from ServiceNow's scheduled connection check
  (`last_check_on`), not from the imports. Right after a change it can still show the previous
  check's result (here "Malformed url" from the `<hostname>` placeholder); `test.yml` treats a
  check older than the HTTP connection's last update as stale.
- `discovery_source` keeps the source that first created a CI. CIs the legacy connector created
  stay "SGO-Dynatrace" after the SaaS connector refreshes them; `test.yml` therefore checks the
  SaaS connector's `sys_object_source` rows (name "SGO-Dynatrace SaaS").
- First full cascade: 14 imports, about 13 minutes, no errors; about 1,000 CI inserts/updates
  across hosts, services, pods, containers, workloads and Kubernetes relationships.
