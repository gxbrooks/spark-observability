# Mirrors ansible/playbooks/observability/dynatrace/tasks/resolve_k8s_cluster.yml:
# select the K8S_CLUSTERS entry flagged dynatrace: true and take its name.
locals {
  dt_enabled_clusters = [for c in var.K8S_CLUSTERS : c.name if try(c.dynatrace, false)]

  # one() errors out if there's more than one match (good -- same "exactly
  # one" assumption Ansible asserts); returns null on zero matches, which
  # surfaces downstream as a type error wherever k8s_dynatrace_cluster is
  # used as a string, rather than a message pointing at this file.
  k8s_dynatrace_cluster = one(local.dt_enabled_clusters)
}
