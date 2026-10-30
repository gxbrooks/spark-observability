# Terraform (Phase 2 — in progress)

Peer to `ansible/`. Goal: one canonical representation file per config
object, readable by either Ansible or Terraform — not forked copies.
Background and the full scoping analysis: see `tmp/20261027_1720_terraform_port_analysis.md`
(project-local, gitignored) and the `terraform-ansible-template-port`
session memory.

## What's here

`dynatrace_settings.tf` — 9 Dynatrace Settings 2.0 objects (11 resources;
auto-tags fans out via `for_each`), each rendered via `templatefile()`
reading the **same** files under `../observability/dynatrace/` that
Ansible's `tf_template` action plugin renders (see `ansible/module_utils/tf_template_core.py`
and the Phase 1 commit). Every file is a complete `{schemaId, scope, value}`
document; decoded with `jsondecode()` and handed straight to
`dynatrace_generic_setting(schema, scope, value)`.

Validated 2026-10-28 against the live tenant: `terraform plan` succeeds,
and after `terraform import` of the 11 objects Ansible already created,
plan showed `0 to add, 0 to destroy`, 5 "to change" (the live API
omitting default-`false` boolean fields in its GET response that the
template includes explicitly — not a real divergence, confirmed by
inspecting the diff). Applied those 5 on 2026-10-28; `terraform plan`
immediately after reports **"No changes. Your infrastructure matches the
configuration."** — full proof, not just a plan-time claim.

`dynatrace_k8s.tf` — the Dynatrace Operator (`helm_release`, same chart
repo Ansible's `deploy_operator.yml` adds), the Dynakube token `Secret`,
and the DynaKube CR itself (`kubectl_manifest`, reading `dynakube.yaml.j2`
via `templatefile()` -- the same file Ansible's `apply_dynakube.yml`
renders). Uses `kubectl_manifest` (community `gavinbunney/kubectl`
provider) rather than the official `kubernetes_manifest` resource:
the latter needs the CRD already in its provider schema at plan time,
which breaks when the CRD is installed by the same apply's
`helm_release` (`installCRD=true`) -- a known chicken-and-egg problem for
exactly this pattern.

Also validated against the live cluster: all three resources imported
from the Operator/Dynakube Ansible already deployed, plan showed
`0 to add, 3 to change` (import-metadata artifacts -- `helm_release`
not capturing `repository`/`create_namespace` on import, the Secret's
`wait_for_service_account_token` provider default, and the DynaKube CR's
server-managed `.status` subresource appearing to "disappear" in the
diff). That last one wasn't taken on faith: a `kubectl apply
--dry-run=server` with the exact rendered manifest confirmed the live
status data (tenant UUID, OneAgent pod info, ActiveGate endpoints) comes
back fully intact -- status isn't touched by a normal apply/PATCH, so
the diff is a display artifact, not a real mutation. Applied 2026-10-30;
plan immediately after: "No changes. Your infrastructure matches the
configuration."

`dynatrace_lifecycle.tf` + `diagnostics.tf` -- stop/start/diagnose for
this slice, driven by one variable (`dynatrace_running`) rather than a
verb, since Terraform's model is "apply toward a desired state," not
"run this action." Mirrors
`ansible/playbooks/observability/dynatrace/stop.yml` and
`tasks/ensure_operator_webhook.yml` exactly:

- **stop**: `terraform apply -var="dynatrace_running=false"` -- disables
  the 6 K8s monitoring Settings objects (`k8s-monitoring/*-anomaly-disabled.json`,
  pure data, no templating) and scales `dynatrace-operator`/
  `dynatrace-webhook` to 0 replicas. OneAgent itself is correctly left
  alone (it's a separate DaemonSet the Operator created, not managed by
  the Operator's own replica count) -- same as Ansible's.
- **start**: `-var="dynatrace_running=true"` (or omit the flag --
  `true` is the default) -- re-enables the Settings objects, scales
  operator back to 1 and webhook to 2.
- Replica scaling uses a `null_resource` + `local-exec` running
  `kubectl scale`, not a `kubernetes_deployment` resource: the Helm
  chart has no `replicas` value to set (checked `helm show values` --
  nothing matches), and managing the same Deployment two ways (Helm's
  templates *and* a direct Terraform resource) would fight itself. This
  mirrors Ansible's own literal mechanism (same `kubectl scale` command)
  rather than forcing a "more Terraform-native" approach that doesn't
  actually fit what's being scaled.
- Not replicated: `ensure_operator_webhook.yml`'s webhook-TLS-cert
  renewal (~7 day TTL, won't expire inside a stop/start test cycle, but
  worth adding if this needs to survive a longer stopped period).
- **diagnose**: two complementary signals, not one. `terraform plan`
  is the config-drift half (do the managed resources match what they
  should be -- "No changes" is a clean bill of health). The `dynatrace_diagnose`
  output is the operational-health half plan alone can't show, since
  the Deployments/DaemonSets here aren't direct Terraform resources
  whose drift plan would already report: desired vs. ready replica
  counts for the operator and webhook, the OneAgent and CSI-driver
  DaemonSets' ready counts, the DynaKube CR's `.status.phase`, and the
  current `dynatrace_running` value. Read via `terraform output
  dynatrace_diagnose` (add `-json` for scripting). Built on
  `data "kubernetes_resource"` -- `hashicorp/kubernetes` has no typed
  data source for Deployment or DaemonSet (checked the provider's own
  schema), so this is its generic escape hatch: any apiVersion/kind/name,
  returns the live object including `.status`.

Validated as a full cycle against the live cluster, 2026-10-30: stop (operator/webhook
to 0, OneAgent stayed at 3/3 as expected) -> start (operator 1/1,
webhook 2/2 after a few seconds to schedule) -> `terraform plan` showed
zero drift and the diagnose output was fully green -> ran a Chapter 03
Spark load test (23s, succeeded) -> confirmed fresh data in both
Elasticsearch (the run's `SparkListenerApplicationEnd` event) and
Dynatrace (OneAgent `lastSeen` on Lab1/2/3 inside the test window).

## Not yet covered

- **l2i-openpipeline-routing-entries.json.j2** — Ansible merges these
  entries into an *existing* routing list rather than creating/replacing
  a whole object. Doesn't map to a single resource; needs either a
  dedicated merge step or re-modeling as its own managed list.
- **sgc-problem-notification-payload.json.j2** — a payload fragment that
  gets wrapped into a `builtin:problem.notifications` object by the
  caller; not a complete settings document on its own.
- **ServiceNow AMR files** (`em_alert_management_rule_*.json.j2`) —
  provider choice not yet settled; see the project memory for the
  `tylerhatton/terraform-provider-servicenow` vs. generic-REST-provider
  decision already made, not yet implemented here.
- **`dt_spark_hostgroup_entity_id`** (used by the service-response-time
  resource) is a hardcoded variable default right now, copied from the
  current live value. Ansible resolves this dynamically via an entities
  query; a real implementation should do the same here via a Dynatrace
  entities data source instead of a fixed value.
- Per-resource free-text values (tag names, alert/event summary strings,
  openpipeline display names/custom IDs, log-path patterns) are still
  inline in `dynatrace_settings.tf`'s `templatefile()` calls rather than
  pulled from `variables.yaml` -- only the broader tenant-partitioning
  values (host group, management zone, environment, owner, cluster
  registry, API URL/token) are centrally sourced so far. Worth extending
  the `dynatrace-terraform` context's variable tags to cover the rest.

## Working on this with Claude Code

`terraform apply` needs an explicit Bash permission rule to run
autonomously under Claude Code's auto mode -- the harness's own
auto-mode safety classifier blocks it by default as a broad category
(apply is the step that actually mutates real infrastructure, unlike the
always-read-only `plan`), separately from whatever a given change
actually does. `.claude/settings.local.json` in this repo already grants
it:

```json
{
  "permissions": {
    "allow": [
      "Bash(terraform apply:*)"
    ]
  }
}
```

That file is intentionally **not gitignored** here, despite the `.local`
naming convention usually implying a personal, untracked override --
anyone doing Terraform work on this project will hit the same block, so
the permission is checked in rather than left for each contributor to
rediscover and reconstruct. If you're setting this up fresh (the file's
missing, or you're in a different checkout), see the
`terraform-ansible-template-port` session memory or just recreate the
JSON above.

## Usage

Variable *values* (`DT_HOST_GROUP`, `DT_MANAGEMENT_ZONE`, `K8S_CLUSTERS`,
etc.) come from the same `vars/variables.yaml` Ansible uses, not
hand-maintained here -- regenerate after editing it:

```bash
generate-contexts --vars-dir ../vars dynatrace-terraform -f
```

That writes `../vars/contexts/dynatrace_terraform.auto.tfvars.json`
(gitignored, like every other generated context file -- it carries
DT_API_TOKEN in plaintext, same as `dynatrace_ansible_vars.yml` already
does). The `terraform_vars` writer that produces it lives in the sibling
`context-variables` project (`context_variables.generate.write_terraform_vars`),
alongside `ansible_vars`, `shell_env`, etc.

```bash
cd terraform
terraform init
terraform plan -var-file=../vars/contexts/dynatrace_terraform.auto.tfvars.json
# stop / start:
terraform apply -var-file=../vars/contexts/dynatrace_terraform.auto.tfvars.json -var="dynatrace_running=false"
terraform apply -var-file=../vars/contexts/dynatrace_terraform.auto.tfvars.json -var="dynatrace_running=true"
# diagnose:
terraform output dynatrace_diagnose
```

Variable names here match `vars/variables.yaml` exactly (`DT_HOST_GROUP`,
not `dt_host_group`) rather than conventional Terraform lower_snake_case
-- every context-variables writer passes keys through unchanged, so this
keeps the Terraform side a direct match instead of needing a rename/mapping
layer to stay in sync.
