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
the diff is a display artifact, not a real mutation. Not yet applied.

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
```

Variable names here match `vars/variables.yaml` exactly (`DT_HOST_GROUP`,
not `dt_host_group`) rather than conventional Terraform lower_snake_case
-- every context-variables writer passes keys through unchanged, so this
keeps the Terraform side a direct match instead of needing a rename/mapping
layer to stay in sync.
