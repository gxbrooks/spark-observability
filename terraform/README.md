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

## Not yet covered

- **DynaKube CR** (`dynakube.yaml.j2`) — a Kubernetes object, not a
  Dynatrace tenant setting. Needs the `kubernetes`/`helm` providers
  (Operator via `helm_release`, CR via `kubernetes_manifest` +
  `yamldecode(templatefile(...))`), not `dynatrace_generic_setting`.
  Same shared-file principle applies, different provider.
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
