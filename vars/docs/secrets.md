# Secrets

What each secret in [`vars/secrets.yaml`](../secrets.yaml) is for, who holds it, and the exact
permissions it needs. [`vars/secrets.example.yaml`](../secrets.example.yaml) is the template with
the same keys and no values. Never paste a secret value into chat, a ticket or a commit; write new
values into `secrets.yaml` with a no-echo helper (for example `tmp/set_grail_token.py <file> <value-file> <KEY>`).

## Dynatrace

### Classes

Dynatrace tokens are grouped by **who holds the token**, not by which API it calls. A token is only
as safe as the place it is stored, so tokens that share a holder share a class, and tokens in
different places are never merged.

| Class | Tokens | Held by | Why it is its own class |
|---|---|---|---|
| 1. Automation | `DT_AUTOMATION_TOKEN`, `DT_AUTOMATION_PLATFORM_TOKEN` | `vars/secrets.yaml` on the controller; read by Ansible, Terraform and local tools | One identity with everything automation needs. Two tokens only because Dynatrace splits its APIs: the classic Environment API takes classic tokens, the platform APIs take platform tokens. |
| 2. In-cluster agents | `DT_OPERATOR_TOKEN`, `DT_INGEST_TOKEN` | Kubernetes secret of the Dynakube (`apiToken`, `dataIngestToken`); the OTel collector and GPU sampler | Lives on workload hosts. A compromised pod must not get settings-wide or token-minting rights. The Dynatrace Operator expects the two separate keys. |
| 3. ServiceNow → Dynatrace | `DT_SERVICENOW_TOKEN` | ServiceNow credential records, pushed there by Ansible | Lives in another system with other administrators. Read-only. |
| 4. Dynatrace → ServiceNow | none (a ServiceNow account) | Dynatrace ServiceNow app connection; source keys `servicenow.SN_DT_WEBHOOK_USER` / `SN_DT_WEBHOOK_PASSWORD` (suffix `_DEMO3` for Demo3) | Dynatrace calls ServiceNow with ServiceNow credentials, so no Dynatrace token is involved. Listed so the direction is not forgotten. |

There are two kinds of Dynatrace token, created in different places with different scope names:

| Kind | Prefix | Tokens | Where to create | Scope names look like |
|---|---|---|---|---|
| Classic access token | `dt0c01.` | `DT_AUTOMATION_TOKEN`, `DT_OPERATOR_TOKEN`, `DT_INGEST_TOKEN` | The environment's **Access Tokens** page (`https://<env-id>.live.dynatrace.com/ui/access-tokens`) → **Generate new token**; search each scope by its API name | `entities.write`, `settings.read`, `InstallerDownload` — dotted or single words, no prefix. These are the full names. |
| Platform token | `dt0s16.` | `DT_AUTOMATION_PLATFORM_TOKEN`, `DT_SERVICENOW_TOKEN` | **Account Management → My platform tokens** (pick the account and this environment) | `storage:logs:read`, `automation:workflows:write` — colon-separated with a service prefix |

Classic scopes do not exist on platform tokens and vice versa, so `entities.write` will never appear
in the platform token scope list. The scope tables below give each scope's exact name for its token
kind. Scopes cannot be changed after creation: adding a scope means creating a replacement token
and deleting the old one.

Tenant: `DT_TENANT_URL` (platform, `*.apps.dynatrace.com`) and `DT_API_URL` (classic,
`*.live.dynatrace.com/api`) in [`vars/variables.yaml`](../variables.yaml).

---

### Class 1 — Automation

#### `DT_AUTOMATION_TOKEN`

- **Type**: classic access token (`dt0c01.*`), created on the **Access Tokens** page. Dynatrace name: `spark-observability-automation`.
- **Used by**: every Ansible playbook under `automation/ansible/playbooks/observability/dynatrace/`,
  `oneagent/`, `servicenow/` (Settings 2.0 objects such as OpenPipeline, management zones,
  auto-tags, alerting profiles, problem notifications, the Dynatrace ServiceNow app connection
  `app:dynatrace.servicenow:connection`); the Terraform Dynatrace provider; the local tools
  `servicenow/sn_active_instance.py` and `servicenow/comparator/`.
- **Replaces**: `DT_API_TOKEN`, `DT_TOKEN_ADMIN_TOKEN`, `DT_PAAS_TOKEN`.

| Scope (UI name) | API scope | Why |
|---|---|---|
| Read settings | `settings.read` | Read Settings 2.0 objects before an upsert; read the Dynatrace ServiceNow app connection |
| Write settings | `settings.write` | Create/update Settings 2.0 objects (OpenPipeline, management zone, auto-tags, alerting, Kubernetes monitoring, ServiceNow app connection) |
| Read entities | `entities.read` | Resolve entity IDs (`/api/v2/entities`); comparator |
| Write entities | `entities.write` | Davis event bundling configuration |
| Read metrics | `metrics.read` | Metric probes (`/api/v2/metrics`) |
| Read problems | `problems.read` | Problem diagnostics |
| Read logs | `logs.read` | Log diagnostics |
| Read configuration | `ReadConfig` | Config API v1 (classic dashboards, management zones) |
| Write configuration | `WriteConfig` | Config API v1 writes (classic Spark system dashboard) |
| Read API tokens | `apiTokens.read` | Check the scopes of this token and `DT_OPERATOR_TOKEN` (`ensure_api_token_scopes.yml`, `deploy_operator.yml`) |
| Write API tokens | `apiTokens.write` | Mint the legacy SGC for Dynatrace's API key (`ensure-sgc-credential.yml`); drop when the legacy SGC is retired |
| PaaS integration – Installer download | `InstallerDownload` | OneAgent installer for the Lab hosts (`/api/v1/deployment/installer/agent/...`) |

The OneAgent installer must be downloaded on the controller and copied to the host, so this token
never reaches a Lab host.

#### `DT_AUTOMATION_PLATFORM_TOKEN`

- **Type**: platform token (`dt0s16.*`), created in **Account Management → My platform tokens**. Dynatrace name: `spark-observability-automation-platform`.
- **Used by**: dashboard and notebook playbooks (`apply_dql_dashboards.yml`,
  `apply_spark_system_dashboard_new.yml`), DQL probes (`probe_dql_dashboard_queries.yml`), and the
  Dynatrace Workflow that sends brooks-lab problems to the ServiceNow push connector paired with
  the SGC for Dynatrace SaaS.
- **Replaces**: `DT_PLATFORM_TOKEN`, `DT_PLATFORM_TOKEN_GRAIL`.

| Scope | Why |
|---|---|
| `document:documents:read` | Find an existing dashboard/notebook before updating it |
| `document:documents:write` | Create/update dashboards and notebooks |
| `automation:workflows:read` | Read the brooks-lab problem workflow before an upsert |
| `automation:workflows:write` | Create/update that workflow |
| `automation:workflows:run` | Run the workflow on demand in tests |
| `storage:buckets:read` | Required by every Grail query that reads a bucket |
| `storage:logs:read` | `fetch logs` probes |
| `storage:metrics:read` | `timeseries` probes behind dashboard tiles |
| `storage:entities:read` | `fetch dt.entity.*` |
| `storage:events:read` | `fetch dt.davis.problems` / events (problem checks in tests) |
| `storage:smartscape:read` | `smartscapeNodes` / `smartscapeEdges` (check what the SGC for Dynatrace SaaS imports) |

A workflow runs as its **actor** (the owning user), not as this token. The actor needs permission
to use the Dynatrace ServiceNow app and its connection, and must have granted the Workflows app
its permissions once (Workflows → Settings → **Authorization settings**). The token also lets
`servicenow/tasks/dt-problem-notifications.yml` and `servicenow/sn_active_instance.py` read and
switch the workflow trigger; it is exposed to the `dynatrace-ansible` context for that.

---

### Class 2 — In-cluster agents

#### `DT_OPERATOR_TOKEN`

- **Type**: classic access token (`dt0c01.*`), created on the **Access Tokens** page. Dynatrace name: `spark-observability-operator`.
- **Used by**: Dynakube secret key `apiToken` (`deploy_operator.yml`, Terraform `dynatrace_k8s.tf`).
  The Dynatrace Operator uses it to manage OneAgent and ActiveGate in the cluster.

| Scope (UI name) | API scope | Why |
|---|---|---|
| Read entities | `entities.read` | Operator entity lookups during reconciliation |
| Read settings | `settings.read` | Operator reads its Kubernetes monitoring settings |
| Write settings | `settings.write` | Operator registers the cluster's Kubernetes connection |
| Ingest events | `events.ingest` | Operator/OneAgent workload events |
| Access problem and event feed, metrics, and topology | `DataExport` | Operator status and topology calls |
| PaaS integration – Installer download | `InstallerDownload` | Operator downloads the OneAgent/ActiveGate images and installer |
| Create ActiveGate tokens | `activeGateTokenManagement.create` | Operator creates the in-cluster ActiveGate's token |

#### `DT_INGEST_TOKEN`

- **Type**: classic access token (`dt0c01.*`), created on the **Access Tokens** page. Dynatrace name: `spark-observability-ingest`.
- **Used by**: Dynakube secret key `dataIngestToken`; the OTel collector dual feed
  (`merge_otel_dual_feed.yml`, `otel-collector-dynatrace.snippet.yaml`); the GPU sampler
  (`install_gpu_sampler.yml`, OTLP metrics).

| Scope (UI name) | API scope | Why |
|---|---|---|
| Ingest metrics | `metrics.ingest` | OneAgent/OTLP metrics, GPU sampler |
| Ingest logs | `logs.ingest` | OTel collector log feed |
| Ingest events | `events.ingest` | Workload events |
| Ingest OpenTelemetry traces | `openTelemetryTrace.ingest` | OTel collector trace feed |

---

### Class 3 — ServiceNow → Dynatrace

#### `DT_SERVICENOW_TOKEN`

- **Type**: platform token (`dt0s16.*`), read-only, created in **Account Management → My platform tokens**. Dynatrace name: `servicenow-brooks-lab`.
- **Held by**: ServiceNow, in two places written by Ansible:
  - the SGC for Dynatrace SaaS connection's API key credential (`api_key_credentials`, raw token,
    no `Bearer` prefix) — `playbooks/servicenow/sgc/sources/dynatrace-saas/deploy.yml`;
  - the log-to-incident Grail properties used by `ResolveApplicationService` —
    `playbooks/servicenow/incident/tasks/ensure-l2i-dt-sys-properties.yml`.
- **Replaces**: `DT_PLATFORM_TOKEN_SGC_SAAS`, and the copy of `DT_PLATFORM_TOKEN_GRAIL` pushed to
  ServiceNow. The legacy SGC's own API key (Dynatrace name `dynatrace-servicenow-sgc-integration`)
  is retired together with the legacy SGC for Dynatrace.

| Scope | Why |
|---|---|
| `storage:smartscape:read` | SGC for Dynatrace SaaS topology import (`smartscapeNodes`, `smartscapeEdges`) |
| `storage:buckets:read` | Required by every Grail query that reads a bucket |
| `storage:logs:read` | `ResolveApplicationService` `fetch logs` lookups for log-to-incident |

---

### Retired Dynatrace keys

Delete these tokens in Dynatrace **after** the automation reads the new keys (until then the
playbooks still read the old names; deleting first breaks them):

| Old key | Replaced by |
|---|---|
| `DT_API_TOKEN` | `DT_AUTOMATION_TOKEN` |
| `DT_TOKEN_ADMIN_TOKEN` | `DT_AUTOMATION_TOKEN` |
| `DT_PAAS_TOKEN` | `DT_AUTOMATION_TOKEN` |
| `DT_PLATFORM_TOKEN` | `DT_AUTOMATION_PLATFORM_TOKEN` |
| `DT_PLATFORM_TOKEN_GRAIL` | `DT_AUTOMATION_PLATFORM_TOKEN` (automation) and `DT_SERVICENOW_TOKEN` (ServiceNow copy) |
| `DT_PLATFORM_TOKEN_SGC_SAAS` | `DT_SERVICENOW_TOKEN` |
| ServiceNow credential `dynatrace-servicenow-sgc-integration` (not in `secrets.yaml`) | none — retired with the legacy SGC for Dynatrace |
