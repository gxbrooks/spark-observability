# Terraform-specific manual steps

For credential setup shared with Ansible (minting Dynatrace tokens), see
[`automation/docs/manual-steps.md`](../../docs/manual-steps.md).

Nothing Terraform-specific exists here yet. Terraform's own apply flow needs no manual step
beyond having `vars/contexts/dynatrace_terraform.auto.tfvars.json` and
`vars/contexts/elastic_terraform.auto.tfvars.json` generated (`generate-contexts --vars-dir
../../vars dynatrace-terraform elastic-terraform`) and passed with `-var-file` — both are
produced from the shared credentials above plus `vars/variables.yaml`, nothing Terraform has to
provision on its own.

If a future Terraform-only prerequisite shows up (a provider-specific bootstrap, a backend
configuration step, etc.), document it here rather than in `automation/docs/manual-steps.md`.
