# Dynatrace SGC source — manual deployment steps

This document covers the configuration that `deploy.yml` (in this directory)
**cannot** automate. Everything else — the SNC.ImpactManager script copy, the
Dynatrace credential (token minting + push), management-zone resolution and
scoping, and scheduled-import activation — is handled by the playbook,
idempotently and on-needed.

Run order for this source:

1. `playbooks/servicenow/sgc/install.yml` — installs the scoped app
   (`sn_dynatrace_integ`) and prerequisites. See `../../../docs/install.md`.
2. **Manual step 1 below** — grant `connection_admin` (one-time).
3. `playbooks/servicenow/sgc/sources/dynatrace/deploy.yml` — automated
   topology configuration, credential, and connection Hostname.
4. **Manual step 2 below** — first import execution (one-time).
5. `playbooks/servicenow/sgc/test.yml` / `diagnose.yml` — verification.

## Dynatrace tokens (who holds what)

Dynatrace token scopes are **immutable after creation** — "adding" a scope
always means minting a replacement token. Three tokens are involved:

| Token (name in Dynatrace) | Held in | Scopes | Purpose |
| ------------------------- | ------- | ------ | ------- |
| `DT_TOKEN_ADMIN_TOKEN` | `vars/secrets.yaml` (`dynatrace:` block) | `apiTokens.read`, `apiTokens.write` | Mints/rotates other tokens; used by this `deploy.yml` and by `observability/dynatrace` token rotation |
| `spark-observability-api` (variable `DT_API_TOKEN`) | `vars/secrets.yaml` | `entities.read`, `settings.read`, `settings.write`, `metrics.read`, `ReadConfig`, `WriteConfig` | Ansible automation against the Dynatrace settings/entities APIs; needs **no** SGC or apiTokens scopes |
| `dynatrace-servicenow-sgc-integration` | **ServiceNow only** (the *Dynatrace API Key* credential) | `entities.read`, `DataExport`, `ReadConfig` | The SGC connection; minted and pushed by `deploy.yml` (`tasks/ensure_sgc_credential.yml`), never written to `vars/secrets.yaml` |

`deploy.yml` mints the SGC token on first run. On-needed: when the token
already exists the play skips with an informational message (token values are
not retrievable after creation). Rotate any time with
`-e sgc_rotate_token=true` — deletes, re-mints, validates, re-pushes.

## Guided Setup map (app v1.14.x)

The wizard at **All → Dynatrace Observability → Setup** ("Service Graph
Connector for Observability Dynatrace Setup") presents six cards. Mechanics:
click **Get Started** on a card to expose its tasks; each task then offers
**Configure** / **Mark as Complete** controls. The progress tracker is
cosmetic — the connector runs off the underlying records, which the playbooks
manage.

| Card | Action |
| ---- | ------ |
| Enable Access To SNC.ImpactManager | **Skip** — automated by `deploy.yml` (`tasks/ensure_impactmanager_script.yml` copies the mediator script to Global scope via the Table API). The card's *Verify script is copied properly* list shows the Global record once `deploy.yml` has run. |
| Basic | **Skip** — automated by `deploy.yml` (`tasks/ensure_sgc_credential.yml`): mints the Dynatrace token, pushes it into the *Dynatrace API Key* credential with the `api-token ` prefix, and sets the connection Hostname (needs `connection_admin` — manual step 1). Optionally run the card's *Test Connection* task afterwards as a sanity check. *Create Default Notification Payload Template*: the record already exists (`deploy.yml` verifies it) — Mark as Complete without re-running. *Upgrade Source Native Keys*: upgrade-from-1st-gen task; not applicable — Mark as Complete. |
| Configure Dynatrace Grail OAuth | **Skip** (optional; only for Grail-enabled tenants ingesting logs/metrics via OAuth). Opening its Configure tasks while the picker is in Global scope shows a scope-mismatch error — close the tab and click the card's **Skip**. |
| Advanced (locked until Basic completes) | **Skip** — especially **Configure Problem Notification**: `events/deploy.yml` manages the Dynatrace problem notification idempotently; running the wizard task would create a duplicate notification and rotate the `DynatraceAPI` user's password. |
| Add Multiple Instances | **Skip** (single Dynatrace instance). This card is where the *Update Data Source / Scheduled Data Import / Value Access* and *Clear Cache* tasks live in this app version — they are only needed for additional connections. |
| Set up scheduled import jobs (locked until Basic completes) | **Skip** — `deploy.yml` activates the SGO-Dynatrace Hosts schedule. |

> Older ServiceNow docs (the v1.13 onboarding guide) describe "Update variable
> value access" and "Enable script access for event management" as
> prerequisite steps; in v1.14 these correspond to the *Add Multiple
> Instances* tasks and the *Enable Access To SNC.ImpactManager* card
> respectively. Verify the automated script copy at any time with
> `/sys_script_include_list.do?sysparm_query=name%3DEvtMgmtImpactManagerMediator`
> — there must be a record in the **Global** application with
> **Accessible from = All application scopes**, alongside the app-scope
> original.

## Manual step 1 — grant connection_admin (one-time)

`deploy.yml` provisions the credential itself (the `api_key_credentials`
table is writable by the automation user), but the **Hostname** lives on an
`http_connection` record gated by the `connection_admin` role. Grant it once
— in **ServiceNow**, not Dynatrace (`admin_brooks_lab` is a ServiceNow user):

1. **All → User Administration → Users**, open `admin_brooks_lab`.
2. **Roles** related list → **Edit** → add `connection_admin` → **Save**.
3. Re-run `deploy.yml`; it sets the Hostname automatically.

After deploy, optionally run the Basic card's **Test Connection** task in
Guided Setup as a sanity check.

### Manual fallback — configure the connection via Guided Setup

Only needed when `DT_TOKEN_ADMIN_TOKEN` or the role grant is unavailable.
Use the **Basic** card (**Get Started**). If a form complains "…but Global is
the current application", switch the application picker to the connector app.

1. Generate the token in Dynatrace (**Access Tokens** →
   `https://<env-id>.live.dynatrace.com/ui/access-tokens` → **Generate new
   token**): name `dynatrace-servicenow-sgc-integration`, **Template: None**,
   scopes `entities.read`, `DataExport`, `ReadConfig`. Copy the
   `dt0c01.…` value immediately — it is shown only once.
2. **Configure Auth Token for Dynatrace** — in the pre-created *Dynatrace API
   Key* record, overwrite **API Key** with the literal text `api-token`, one
   space, then the token value (a bare token fails with 401 "invalid
   Api-Token", KB2288188). Leave **API Key Header**/**Prefix** empty and all
   other fields at their defaults; click **Update**.
3. **Configure HTTP Connection for Dynatrace** — **Hostname** = the classic
   environment URL `https://<env-id>.live.dynatrace.com` (no trailing
   `/api`; never a `*.apps.dynatrace.com` platform URL).
4. **Test Connection** — must report success.

For the remaining two Basic tasks (*Create Default Notification Payload
Template*, *Upgrade Source Native Keys*), see the Guided Setup map above —
Mark as Complete without running them.

## Manual step 2 — first import execution (one-time)

`deploy.yml` activates the **SGO-Dynatrace Hosts** scheduled import (child
imports for processes, services, and relationships chain after it), but the
integration user is not authorized to trigger an immediate run.

1. Navigate to **Dynatrace Observability → Scheduled Data Imports**.
2. Open **SGO-Dynatrace Hosts** and click **Execute Now**.
3. Monitor **Concurrent Import Sets** until all child imports complete.

Subsequent runs happen on the schedule; no further manual action is needed.

## Verification

- `sources/dynatrace/deploy.yml` prints a topology configuration summary
  (management zone, connection row status, schedule state).
- `sgc/diagnose.yml` reports CMDB rows with `discovery_source=SGO-Dynatrace`
  and `sys_object_source` rows used for event CI binding.
- In the UI: **CMDB Workspace** → filter by discovery source `SGO-Dynatrace`.

## Related documents

- `../../../docs/install.md` §7 — Store app and plugin installation, roles
  (including `connection_admin`), and the CI/CD bootstrap sequence.
- `events/` — Dynatrace problem-notification (event) deployment for this
  source (`events/deploy.yml`).
