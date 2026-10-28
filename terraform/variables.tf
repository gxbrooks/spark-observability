variable "dt_api_url" {
  description = "Dynatrace classic API base URL, e.g. https://xxxxx.live.dynatrace.com/api"
  type        = string
}

variable "dt_api_token" {
  description = "Dynatrace API token (settings.read, settings.write scopes)"
  type        = string
  sensitive   = true
}

variable "dt_host_group" {
  description = "Dynatrace host group name partitioning this project's hosts"
  type        = string
  default     = "spark-observability"
}

variable "dt_management_zone_name" {
  description = "Dynatrace management zone display name"
  type        = string
  default     = "Spark Observability"
}

variable "dt_environment" {
  description = "Environment label stamped into tags/alerts (sn-environment, etc.)"
  type        = string
  default     = "lab"
}

variable "dt_owned_by" {
  description = "Owner tag value"
  type        = string
  default     = "gbrooks"
}

variable "k8s_dynatrace_cluster" {
  description = "Dynatrace-registered Kubernetes cluster name (from K8S_CLUSTERS)"
  type        = string
  default     = "brooks-lab"
}

variable "dt_spark_hostgroup_entity_id" {
  description = <<-EOT
    Dynatrace HOST_GROUP entity ID for dt_host_group, e.g. HOST_GROUP-xxxxxxxx.
    Ansible resolves this dynamically via an entities query; a real
    implementation here should use a Dynatrace entities data source instead
    of a fixed default. Left as a variable, not re-derived, for this first
    pass -- current live value queried directly for the proof-of-concept.
  EOT
  type        = string
  default     = "HOST_GROUP-23B2C0C9E7BEAC79"
}
