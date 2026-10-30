# Terraform-native "diagnose": read-only data sources reporting live
# operational status, surfaced as a single `terraform output`. Mirrors
# ansible/playbooks/observability/dynatrace/diagnose.yml's intent (what
# is the current state, what's wrong) without replicating its exact
# checks -- `terraform plan` is the config-drift half of "diagnose" (do
# the managed resources match what they should be); these data sources
# are the operational-health half (are the pods actually up) that plan
# alone doesn't show for the pieces not managed as direct Terraform
# resources (Deployments templated by Helm, the DaemonSets the Operator
# creates, the DynaKube CR's server-managed .status).
#
# hashicorp/kubernetes has no typed data source for Deployment/DaemonSet
# (checked the provider's own schema -- only a handful of core types get
# one). kubernetes_resource is its generic escape hatch: any
# apiVersion/kind/name, returns the live object including status.

data "kubernetes_resource" "operator_deployment" {
  api_version = "apps/v1"
  kind        = "Deployment"
  metadata {
    name      = "dynatrace-operator"
    namespace = "dynatrace"
  }
  depends_on = [null_resource.dynatrace_operator_scale]
}

data "kubernetes_resource" "webhook_deployment" {
  api_version = "apps/v1"
  kind        = "Deployment"
  metadata {
    name      = "dynatrace-webhook"
    namespace = "dynatrace"
  }
  depends_on = [null_resource.dynatrace_operator_scale]
}

data "kubernetes_resource" "oneagent_daemonset" {
  api_version = "apps/v1"
  kind        = "DaemonSet"
  metadata {
    name      = "dynakube-oneagent"
    namespace = "dynatrace"
  }
}

data "kubernetes_resource" "oneagent_csi_daemonset" {
  api_version = "apps/v1"
  kind        = "DaemonSet"
  metadata {
    name      = "dynatrace-oneagent-csi-driver"
    namespace = "dynatrace"
  }
}

data "kubernetes_resource" "activegate" {
  api_version = "apps/v1"
  kind        = "StatefulSet"
  metadata {
    name      = "dynakube-activegate"
    namespace = "dynatrace"
  }
}

data "kubernetes_resource" "dynakube" {
  api_version = "dynatrace.com/v1beta6"
  kind        = "DynaKube"
  metadata {
    name      = "dynakube"
    namespace = "dynatrace"
  }
  depends_on = [kubectl_manifest.dynakube]
}

output "dynatrace_diagnose" {
  description = "Operational health snapshot -- `terraform output dynatrace_diagnose` (add -json for scripting)"
  value = {
    dynatrace_running_var = var.dynatrace_running
    k8s_monitoring_mode   = var.dynatrace_running ? "enabled" : "disabled"

    operator = {
      desired_replicas = data.kubernetes_resource.operator_deployment.object.spec.replicas
      # coalesce, not try(): at 0 desired replicas the API returns this
      # field as JSON null (present, not absent) -- try() only catches
      # evaluation errors, not a successfully-resolved null, so it was
      # passing the null straight through as `tonumber(null)`.
      ready_replicas = coalesce(try(data.kubernetes_resource.operator_deployment.object.status.readyReplicas, null), 0)
    }
    webhook = {
      desired_replicas = data.kubernetes_resource.webhook_deployment.object.spec.replicas
      ready_replicas   = coalesce(try(data.kubernetes_resource.webhook_deployment.object.status.readyReplicas, null), 0)
    }
    activegate = {
      # StatefulSet status has no per-container restart count (that's a
      # Pod-level field, not aggregated up) -- ready_replicas is enough
      # to catch "crash-looping, never becomes ready" from here.
      desired_replicas = data.kubernetes_resource.activegate.object.spec.replicas
      ready_replicas   = coalesce(try(data.kubernetes_resource.activegate.object.status.readyReplicas, null), 0)
    }
    oneagent = {
      desired = data.kubernetes_resource.oneagent_daemonset.object.status.desiredNumberScheduled
      ready   = try(data.kubernetes_resource.oneagent_daemonset.object.status.numberReady, 0)
    }
    oneagent_csi_driver = {
      desired = data.kubernetes_resource.oneagent_csi_daemonset.object.status.desiredNumberScheduled
      ready   = try(data.kubernetes_resource.oneagent_csi_daemonset.object.status.numberReady, 0)
    }
    dynakube_phase = try(data.kubernetes_resource.dynakube.object.status.phase, "unknown")
  }
}
