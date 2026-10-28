# Variable names here deliberately match vars/variables.yaml exactly
# (DT_HOST_GROUP, not dt_host_group) rather than conventional Terraform
# lower_snake_case. vars/contexts.yaml's "dynatrace-terraform" context
# (generate-contexts, context_variables.generate.write_terraform_vars)
# produces vars/contexts/dynatrace_terraform.auto.tfvars.json with these
# same names, unchanged, exactly like every other context writer in that
# project (ansible_vars, shell_env, etc. don't rename keys either) --
# load it with `terraform plan -var-file=../vars/contexts/dynatrace_terraform.auto.tfvars.json`.
# Regenerate after editing vars/variables.yaml:
#   generate-contexts --vars-dir ../vars dynatrace-terraform -f

variable "DT_API_URL" {
  description = "Dynatrace classic API base URL, e.g. https://xxxxx.live.dynatrace.com/api"
  type        = string
}

variable "DT_API_TOKEN" {
  description = "Dynatrace API token (settings.read, settings.write scopes)"
  type        = string
  sensitive   = true
}

variable "DT_HOST_GROUP" {
  description = "Dynatrace host group name partitioning this project's hosts"
  type        = string
}

variable "DT_MANAGEMENT_ZONE" {
  description = "Dynatrace management zone display name"
  type        = string
}

variable "DT_ENVIRONMENT" {
  description = "Environment label stamped into tags/alerts (sn-environment, etc.)"
  type        = string
}

variable "DT_OWNED_BY" {
  description = "Owner tag value"
  type        = string
}

variable "K8S_CLUSTERS" {
  description = <<-EOT
    Registry of every Kubernetes cluster known to the shared ServiceNow
    instance (same list Ansible's K8S_CLUSTERS drives). Entries vary in
    which optional fields they carry, so typed loosely; the Dynatrace-
    enabled cluster name is derived from this in locals.tf, mirroring
    the filter Ansible's resolve_k8s_cluster.yml task applies.
  EOT
  type        = list(any)
}

variable "dt_spark_hostgroup_entity_id" {
  description = <<-EOT
    Dynatrace HOST_GROUP entity ID for DT_HOST_GROUP, e.g. HOST_GROUP-xxxxxxxx.
    Not in variables.yaml: it's not a static config value, Ansible
    resolves it dynamically via an entities query. A real implementation
    here should do the same via a Dynatrace entities data source instead
    of a fixed default. Current live value, queried directly, for this
    proof of concept.
  EOT
  type        = string
  default     = "HOST_GROUP-23B2C0C9E7BEAC79"
}
