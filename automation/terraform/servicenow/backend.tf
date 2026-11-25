# ServiceNow configuration has its own state (separate from ../ Dynatrace/Elastic): no resource
# crosses the two, and Dynatrace plans must not need ServiceNow credentials. Same Kubernetes
# backend and locking as ../backend.tf (automation standard, Terraform statements 1-2).
terraform {
  backend "kubernetes" {
    secret_suffix = "servicenow-spark-observability"
    namespace     = "default"
    config_path   = "~/.kube/config"
  }
}
