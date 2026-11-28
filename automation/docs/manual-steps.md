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

## Dynatrace credentials

The Dynatrace tokens are created by a person in the Dynatrace UI; automation only checks their
scopes and never mints replacements. Their classes, holders, the exact scopes each needs, and where
to create them are documented in [`vars/docs/secrets.md`](../../vars/docs/secrets.md):

| Token | Kind | Ansible | Terraform |
| --- | --- | :-: | :-: |
| `DT_AUTOMATION_TOKEN` | classic access token | ✓ | ✓ (provider auth) |
| `DT_AUTOMATION_PLATFORM_TOKEN` | platform token | ✓ | — |
| `DT_OPERATOR_TOKEN` | classic access token | ✓ | ✓ (Dynakube secret) |
| `DT_INGEST_TOKEN` | classic access token | ✓ | ✓ (Dynakube secret) |
| `DT_SERVICENOW_TOKEN` | platform token | ✓ (pushed into ServiceNow) | — |
