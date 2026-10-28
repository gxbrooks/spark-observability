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
plan shows `0 to add, 0 to destroy`. The 5 "to change" entries are the
live API omitting default-`false` boolean fields in its GET response that
the template includes explicitly — not a real divergence, confirmed by
inspecting the diff (every changed field is `+ field = false` where the
template already states `false`). Applying would just re-assert the same
values. Not yet applied — that's a live write, left for an explicit
decision rather than done automatically.

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
- Variable *values* (`dt_management_zone_name`, tag values, summary
  strings, etc.) are Terraform variable defaults in `variables.tf` right
  now, sourced by hand from the live tenant and `vars/contexts/dynatrace_ansible_vars.yml`
  for this proof of concept — not yet pulled from one shared source with
  Ansible's own variable resolution. Worth unifying before this goes further.

## Usage

```bash
cd terraform
terraform init
cp terraform.tfvars.example terraform.tfvars   # fill in dt_api_token
terraform plan
```

`terraform.tfvars` holds the live API token — gitignored, never commit it.
