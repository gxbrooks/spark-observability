# Terraform-native "diagnose"/"test" for Elasticsearch/Kibana, mirroring
# diagnostics.tf/checks.tf's role for Dynatrace: `terraform plan` on
# elasticsearch_kibana.tf's resources is the config-drift half of
# "diagnose" (do the managed ILM/template/pipeline/transform/dataview
# objects match their spec files); this file is the operational-health
# half (is the cluster actually reachable and green) that plan alone
# doesn't show.
#
# elastic/elasticstack has no cluster-health data source (checked --
# elasticstack_elasticsearch_info only returns name/uuid/version, not
# status/unassigned_shards). hashicorp/http is the generic escape hatch
# here, the same role data.kubernetes_resource plays for Dynatrace: an
# arbitrary REST endpoint Terraform can read and assert against.

data "http" "es_cluster_health" {
  url      = "${var.ES_URL}/_cluster/health"
  insecure = true
  request_headers = {
    Authorization = "Basic ${base64encode("${var.ES_USER}:${var.ES_PASSWORD}")}"
  }
}

locals {
  es_cluster_health = jsondecode(data.http.es_cluster_health.response_body)
}

check "es_cluster_not_red" {
  assert {
    condition     = local.es_cluster_health.status != "red"
    error_message = "Elasticsearch cluster status is 'red' (expected green/yellow)."
  }
}

check "es_no_pending_tasks_backlog" {
  assert {
    # A persistently large pending-task queue (not just transiently
    # non-zero) is the drift signal worth gating on here; a handful of
    # in-flight ILM/cluster-state tasks is normal.
    condition     = local.es_cluster_health.number_of_pending_tasks < 50
    error_message = "Elasticsearch has ${local.es_cluster_health.number_of_pending_tasks} pending cluster tasks (expected < 50)."
  }
}

output "elasticsearch_diagnose" {
  description = "Operational health snapshot -- `terraform output elasticsearch_diagnose` (add -json for scripting)"
  value = {
    cluster_name            = local.es_cluster_health.cluster_name
    status                  = local.es_cluster_health.status
    number_of_nodes         = local.es_cluster_health.number_of_nodes
    number_of_data_nodes    = local.es_cluster_health.number_of_data_nodes
    active_shards_percent   = local.es_cluster_health.active_shards_percent_as_number
    unassigned_shards       = local.es_cluster_health.unassigned_shards
    number_of_pending_tasks = local.es_cluster_health.number_of_pending_tasks
  }
}
