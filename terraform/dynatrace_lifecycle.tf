# "Stop"/"start" for the Dynatrace slice, mirroring exactly what
# ansible/playbooks/observability/dynatrace/stop.yml and
# tasks/ensure_operator_webhook.yml (the start-side restore) do:
#   stop:  disable K8s monitoring settings, scale operator to 0 replicas
#   start: enable K8s monitoring settings, scale operator to 1 / webhook to 2
#
# One var expresses the whole lifecycle state -- set false and apply to
# stop, true and apply to start/restart. This is the concrete answer to
# the open question in the Phase 2 scoping doc ("how does the automation
# standard's start/stop map onto Terraform, which only has plan/apply"):
# here, as a variable the resource graph is conditioned on, not a verb.
variable "dynatrace_running" {
  description = "false = stop.yml's Dynatrace scale-down state; true = running (start.yml's restored state)"
  type        = bool
  default     = true
}

# === K8s monitoring Settings objects (6 areas) ===
# Pure data files, no templating -- unlike dynatrace_settings.tf's
# upsert targets, Ansible's apply_k8s_monitoring_settings.yml picks
# between a whole enabled/disabled file pair per area rather than
# rendering one template two ways.
locals {
  k8s_mon_dir = "${path.module}/../observability/dynatrace/integrations/k8s-monitoring"
  k8s_mon_areas = {
    cluster          = "vu9U3hXa3q0AAAABACxidWlsdGluOmFub21hbHktZGV0ZWN0aW9uLmt1YmVybmV0ZXMuY2x1c3RlcgAGdGVuYW50AAZ0ZW5hbnQAJDNmMzgwNTQ3LTk1YWMtMzhmNC1iZmMxLTNhZmEyMDllOTE2Zb7vVN4V2t6t"
    namespace        = "vu9U3hXa3q0AAAABAC5idWlsdGluOmFub21hbHktZGV0ZWN0aW9uLmt1YmVybmV0ZXMubmFtZXNwYWNlAAZ0ZW5hbnQABnRlbmFudAAkZWU4MjM4YzYtM2Y4OS0zNjZkLTllMzEtZmI4MzVmNGVmZjU4vu9U3hXa3q0"
    node             = "vu9U3hXa3q0AAAABAClidWlsdGluOmFub21hbHktZGV0ZWN0aW9uLmt1YmVybmV0ZXMubm9kZQAGdGVuYW50AAZ0ZW5hbnQAJDNkNzc5YjlmLWY3MjAtM2M4OC1iNmM2LTk2M2JlMDgxNjJiN77vVN4V2t6t"
    workload         = "vu9U3hXa3q0AAAABAC1idWlsdGluOmFub21hbHktZGV0ZWN0aW9uLmt1YmVybmV0ZXMud29ya2xvYWQABnRlbmFudAAGdGVuYW50ACRjY2JhOTY3Yy0wNWFiLTNmMjItYTJkMC0yNzQ1OGIzYmZhN2K-71TeFdrerQ"
    pvc              = "vu9U3hXa3q0AAAABAChidWlsdGluOmFub21hbHktZGV0ZWN0aW9uLmt1YmVybmV0ZXMucHZjAAZ0ZW5hbnQABnRlbmFudAAkZmQ1MTE5NjAtYmVhZS0zN2Y5LWI5MDAtZjcwYjY4NDBmOTQ2vu9U3hXa3q0"
    cloud_monitoring = "vu9U3hXa3q0AAAABACNidWlsdGluOmNsb3VkLmt1YmVybmV0ZXMubW9uaXRvcmluZwAGdGVuYW50AAZ0ZW5hbnQAJGUwYjE3NzFiLTE3ZTktMzRhYi1hMzZkLWRhZGVmYTQ0ZTJjOb7vVN4V2t6t"
    # objectIds recorded here only to make `terraform import` reproducible
    # (see terraform/README.md) -- not referenced by the resources below.
  }
}

resource "dynatrace_generic_setting" "k8s_monitoring" {
  for_each = local.k8s_mon_areas

  schema = jsondecode(file("${local.k8s_mon_dir}/${each.key}-anomaly-${var.dynatrace_running ? "enabled" : "disabled"}.json")).schemaId
  scope  = jsondecode(file("${local.k8s_mon_dir}/${each.key}-anomaly-${var.dynatrace_running ? "enabled" : "disabled"}.json")).scope
  value = jsonencode(jsondecode(file(
    "${local.k8s_mon_dir}/${each.key}-anomaly-${var.dynatrace_running ? "enabled" : "disabled"}.json"
  )).value)
}

# === Operator / webhook replica count ===
# The Helm chart has no replicas value to set (checked: `helm show values`
# has nothing matching "replica") -- Ansible's own mechanism is a direct
# `kubectl scale`, outside the chart's values model entirely. Managing the
# same Deployment two ways in Terraform (a kubernetes_deployment_v1
# resource *and* the Helm release that templates it) would fight itself,
# so this mirrors Ansible's literal mechanism instead of forcing a more
# "Terraform-native" approach that doesn't actually fit what's being
# scaled. local-exec is deliberately the tool here, not a workaround --
# see the apply-permission discussion in terraform/README.md for why that
# gate exists in the first place.
resource "null_resource" "dynatrace_operator_scale" {
  triggers = {
    running = var.dynatrace_running
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n dynatrace scale deployment dynatrace-operator --replicas=${var.dynatrace_running ? 1 : 0}"
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n dynatrace scale deployment dynatrace-webhook --replicas=${var.dynatrace_running ? 2 : 0}"
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${pathexpand(var.kubeconfig_path)} -n dynatrace rollout status deployment/${var.dynatrace_running ? "dynatrace-operator" : "dynatrace-webhook"} --timeout=120s || true"
  }

  depends_on = [helm_release.dynatrace_operator]

  # Not replicated here: ensure_operator_webhook.yml's webhook-TLS-cert
  # renewal (~7 day TTL, won't expire inside a stop/start test cycle).
  # Flag if this needs to become a real long-lived stop/start cycle rather
  # than a short verification one.
}
