# Manual steps common to Terraform and Ansible

This document covers the one-time, cross-tool setup this project's automation cannot do for
itself: minting Dynatrace credentials. Both `automation/terraform/` and `automation/ansible/`
read the same credentials from `vars/secrets.yaml` (see [`vars/README.md`](../../vars/README.md)
for how that file relates to `vars/variables.yaml`). Tool-specific manual steps — ones that only
Terraform or only Ansible needs — live in their own `docs/manual-steps.md` next to this one:
[`automation/terraform/docs/manual-steps.md`](../terraform/docs/manual-steps.md) and
[`automation/ansible/docs/manual-steps.md`](../ansible/docs/manual-steps.md).

Dynatrace token scopes are **immutable after creation** — "adding" a scope always means minting
a replacement token (classic `dt0c01.*` and platform `dt0s16.*` tokens alike).

## Every Dynatrace credential this project holds

All live in `vars/secrets.yaml` under the `dynatrace:` block unless noted otherwise. "Validation
status" means an Ansible task actually asserts/rotates on that scope list — not just checks the
value is present.

---

### DT_TOKEN_ADMIN_TOKEN

**Purpose**: Bootstrap authority — mints and rotates every other classic token below. Deliberately
separate from the tokens it mints, so a compromised automation token can't mint itself new scopes.

**Format**: `dt0c01.*` (classic API token)

**Scopes**:

| Scope | Comment |
| --- | --- |
| `apiTokens.read` | Look up an existing token's current scopes before deciding whether to rotate it |
| `apiTokens.write` | Mint a replacement token when a scope is missing |

**Validation status**: Not validated in-repo (presence-only check in
[`ensure_api_token_scopes.yml`](../ansible/playbooks/observability/dynatrace/tasks/ensure_api_token_scopes.yml),
[`deploy_operator.yml`](../ansible/playbooks/observability/dynatrace/tasks/deploy_operator.yml),
[`ensure_sgc_credential.yml`](../ansible/playbooks/servicenow/sgc/sources/dynatrace/tasks/ensure_sgc_credential.yml)).

---

### DT_API_TOKEN

**Purpose**: The main automation token — Settings 2.0 CRUD, entity/metric/problem reads, used by
both Ansible and Terraform. Also known as `spark-observability-api` in Dynatrace itself.

**Format**: `dt0c01.*`

**Scopes**:

| Scope | Comment |
| --- | --- |
| `entities.read` | Resolve Dynatrace entity IDs (hosts, process groups, etc.) referenced by specs |
| `entities.write` | Required by [`events/deploy.yml`](../ansible/playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml) for the Davis Bundling configuration — see [`Davis_Bundling_Issue.md`](../../specifications/servicenow/docs/Log_to_Incident/Davis_Bundling_Issue.md) |
| `settings.read` | Read an existing Settings 2.0 object before deciding whether an upsert is needed |
| `settings.write` | Create/update Settings 2.0 objects (OpenPipeline pipelines, management zone, auto-tags, alerting profile, etc.) |
| `metrics.read` | Dashboard tile and diagnostic metric queries |
| `problems.read` | Problem/alert diagnostics |
| `ReadConfig` | Legacy Config API v1 reads some older endpoints still need |
| `WriteConfig` | Legacy Config API v1 writes |

**Validation status**: Validated — auto-rotates on missing scopes in
[`ensure_api_token_scopes.yml:12`](../ansible/playbooks/observability/dynatrace/tasks/ensure_api_token_scopes.yml).

---

### DT_OPERATOR_TOKEN

**Purpose**: Dynakube secret `apiToken` — the Dynatrace Operator's own credential for OneAgent/
ActiveGate lifecycle management on Kubernetes. Kept separate from `DT_API_TOKEN` deliberately: this
token lives inside the cluster (in a Kubernetes Secret), so its blast radius if a pod is compromised
should not include `DT_API_TOKEN`'s broader settings/metrics/problems access.

**Format**: `dt0c01.*`

**Scopes**:

| Scope | Comment |
| --- | --- |
| `entities.read` | Operator's entity lookups during Dynakube reconciliation |
| `events.ingest` | OneAgent-injected workload event reporting |
| `settings.read` | Operator reads its own monitoring settings |
| `settings.write` | Operator updates monitoring settings for discovered workloads |
| `DataExport` | Classic data export used by the Operator/ActiveGate |
| `InstallerDownload` | Downloads the OneAgent/ActiveGate installer the Operator deploys |
| `activeGateTokenManagement.create` | Operator provisions its own ActiveGate token |

**Validation status**: Validated — auto-rotates on missing scopes in
[`deploy_operator.yml:18`](../ansible/playbooks/observability/dynatrace/tasks/deploy_operator.yml).

---

### DT_INGEST_TOKEN

**Purpose**: Dynakube secret `dataIngestToken` — metric/log/event ingest from workloads the
Operator injects.

**Format**: `dt0c01.*`

**Scopes**: Not defined in-repo — no task validates this one the way `DT_OPERATOR_TOKEN` gets
checked. Dynatrace Operator's own documentation calls for:

| Scope | Comment |
| --- | --- |
| `metrics.ingest` | Metric ingest from injected workloads |
| `logs.ingest` | Log ingest from injected workloads |
| `events.ingest` | Event ingest from injected workloads |

If traces get added to this project, `openTelemetryTrace.ingest` would join this list.

**Validation status**: Not validated — read and applied raw by
[`deploy_operator.yml:162`](../ansible/playbooks/observability/dynatrace/tasks/deploy_operator.yml),
no scope lookup/assert task exists for it.

---

### DT_PAAS_TOKEN

**Purpose**: OneAgent installer download for bare-metal/VM hosts (the Lab1/2/3 hosts), as opposed
to the Kubernetes Operator path above.

**Format**: `dt0c01.*`

**Scopes**:

| Scope | Comment |
| --- | --- |
| `InstallerDownload` | Classic installer endpoint (`/v1/deployment/installer/agent/...`) this project's OneAgent host install calls |

Deliberately not merged with `DT_OPERATOR_TOKEN` even though that token's scope set is a superset
that would technically work here too — a compromised Lab host shouldn't hold a token that also
carries `DataExport`/`settings.write`/`activeGateTokenManagement.create`.

**Validation status**: Not validated — presence-only check in
[`install-oneagent-host.yml`](../ansible/playbooks/oneagent/tasks/install-oneagent-host.yml).

---

### DT_PLATFORM_TOKEN

**Purpose**: Document API — creating/updating Dynatrace dashboards and Notebooks.

**Format**: `dt0s16.*` (platform token)

**Scopes**:

| Scope | Comment |
| --- | --- |
| `document:write` | Create/update dashboard and Notebook documents |

This project only writes dashboards, never reads them back programmatically, so `document:read`
has never been separately confirmed as needed or not.

**Validation status**: Not validated — presence-only check in
[`apply_spark_system_dashboard_new.yml`](../ansible/playbooks/observability/dynatrace/tasks/apply_spark_system_dashboard_new.yml)
and [`apply_dql_dashboards.yml`](../ansible/playbooks/observability/dynatrace/tasks/apply_dql_dashboards.yml).

---

### DT_PLATFORM_TOKEN_GRAIL

**Purpose**: Grail DQL `query:execute` — ad-hoc and validation log/entity/metric queries. Used as
a direct Bearer token against `{tenant}/platform/storage/query/v1/query:execute`; no OAuth exchange
needed since this is a long-lived platform token rather than an OAuth client.

**Format**: `dt0s16.*`

**Scopes**:

| Scope | Comment |
| --- | --- |
| `storage:metrics:read` | Per the in-repo comment, for the dashboard-tile metric probe |
| `storage:entities:read` | Per the in-repo comment, resolves entity names in DQL results |
| `storage:logs:read` *(inferred)* | Not in the original comment, but empirically required — this token successfully ran a `fetch logs` query on 2026-11-12 |
| `storage:buckets:read` *(inferred)* | Empirically required to resolve the Grail bucket backing any log query; Dynatrace's documented requirement for log DQL |

The exact granted scope list was never confirmed directly against the account — there's no
in-repo lookup task for platform tokens the way `ensure_api_token_scopes.yml` handles classic
ones. What's listed above is based on the original comment plus what was empirically exercised
successfully; treat it as a lower bound, not a confirmed exact set.

**Validation status**: Not validated — presence-only check in
[`probe_dql_dashboard_queries.yml:15`](../ansible/playbooks/observability/dynatrace/tasks/probe_dql_dashboard_queries.yml).

---

### dynatrace-servicenow-sgc-integration

**Purpose**: The Service Graph Connector's own credential — what ServiceNow uses to call
Dynatrace's API when importing CMDB topology. Not a `vars/secrets.yaml` key: it lives only in
ServiceNow's *Dynatrace API Key* credential record, minted and pushed there by Ansible, never
retrievable afterward.

**Format**: `dt0c01.*`

**Scopes**:

| Scope | Comment |
| --- | --- |
| `entities.read` | SGC resolves entity metadata during CMDB discovery import |
| `DataExport` | Classic data export the SGC connector uses to pull topology/metrics |
| `ReadConfig` | Legacy Config API reads for the SGC's configuration mirroring |

**Validation status**: Implicit — minted with exactly this scope list by
[`ensure_sgc_credential.yml`](../ansible/playbooks/servicenow/sgc/sources/dynatrace/tasks/ensure_sgc_credential.yml);
no separate drift check exists since Dynatrace never returns a token's value after creation.

---

## Credential simplification (2026-11-12)

**Removed `DT_DQL_OAUTH_TOKEN`.** This was a Dynatrace OAuth client (`dt0s02.*` client ID/secret,
exchanged for a 5-minute Bearer token via `grant_type=client_credentials` against
`sso.dynatrace.com/sso/oauth2/token`) set up specifically to unblock a Grail DQL check. It was
confirmed working — the exchange returned `storage:logs:read storage:buckets:read
storage:events:read` — but it turned out to do exactly what `DT_PLATFORM_TOKEN_GRAIL` (above)
already did, and `DT_PLATFORM_TOKEN_GRAIL` is the one actually wired into a committed task
(`probe_dql_dashboard_queries.yml`). Removed from `vars/secrets.yaml` and
`vars/secrets.example.yaml` rather than keeping two credentials that do the same job. If
`DT_PLATFORM_TOKEN_GRAIL` is ever retired in favor of OAuth clients project-wide (the credential
type Dynatrace is steering new integrations toward — short-lived tokens, no manual re-mint on
scope changes), re-create the OAuth client the same way and point `probe_dql_dashboard_queries.yml`
at it instead.

Checked for other overlaps and deliberately did **not** merge these, despite sharing a token
format:

- `DT_OPERATOR_TOKEN` and `DT_PAAS_TOKEN` (both `dt0c01.*`, `DT_OPERATOR_TOKEN`'s scopes are a
  strict superset including `InstallerDownload`) — different blast radius: one lives in a
  Kubernetes Secret, the other authenticates bare-metal host installs. Not the same identity.
- `DT_PLATFORM_TOKEN` and `DT_PLATFORM_TOKEN_GRAIL` (both `dt0s16.*`, non-overlapping scope
  domains — Document API vs. Grail storage) — could technically be minted as one platform token
  with both scope sets, which would reduce the credential count by one. Not done here because it
  requires minting a brand-new replacement token (scopes are immutable after creation) — an action
  only the account owner can take in the Dynatrace UI, not something this session should do
  unilaterally. Flagging as a worthwhile future consolidation.

## Who uses what — Ansible vs. Terraform

| Credential | Ansible | Terraform |
| --- | :-: | :-: |
| `DT_TOKEN_ADMIN_TOKEN` | ✓ | — |
| `DT_API_TOKEN` | ✓ | ✓ |
| `DT_OPERATOR_TOKEN` | ✓ | ✓ |
| `DT_INGEST_TOKEN` | ✓ | ✓ |
| `DT_PAAS_TOKEN` | ✓ | — |
| `DT_PLATFORM_TOKEN` | ✓ | — |
| `DT_PLATFORM_TOKEN_GRAIL` | ✓ | — |
| `dynatrace-servicenow-sgc-integration` | ✓ | — |

Terraform only ever declares the three it actually resources (`variables.tf`): `DT_API_TOKEN`
(provider auth, `providers.tf`), `DT_OPERATOR_TOKEN` and `DT_INGEST_TOKEN` (the Dynakube secret,
`dynatrace_k8s.tf`). Every credential Terraform uses is also used by Ansible — there is no
Terraform-only credential today. Ansible uses all eight.

**Unused credentials**: none, after removing `DT_DQL_OAUTH_TOKEN` above. Every remaining
credential has at least one real consumer in the repo.
