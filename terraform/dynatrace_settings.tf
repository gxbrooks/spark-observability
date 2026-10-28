# Dynatrace Settings 2.0 objects, rendered from the same representation
# files Ansible uses (ansible/action_plugins/tf_template.py renders the
# identical files for Ansible; Terraform reads them natively here via
# templatefile()). Each file is already a complete {schemaId, scope, value}
# document -- jsondecode() it and hand schema/scope/value straight to
# dynatrace_generic_setting, matching exactly what the Ansible upsert tasks
# POST/PUT today.
#
# Deliberately not covered yet (need more than a straight templatefile ->
# generic_setting mapping -- see tmp/ port analysis for why):
#   - l2i-openpipeline-routing-entries.json.j2 (merges into an existing
#     list rather than creating/replacing a whole object)
#   - sgc-problem-notification-payload.json.j2 (a payload fragment that
#     gets wrapped into a builtin:problem.notifications object by the
#     caller, not a complete settings document itself)
#   - the two ServiceNow AMR files (different system, provider choice
#     pending)
#   - spark-openpipeline-log-alerts-pipeline.json.j2 (orphaned -- no
#     current Ansible consumer either, see Phase 1 commit)

locals {
  dt_integrations_dir = "${path.module}/../observability/dynatrace/integrations"
  dt_mz_dir           = "${path.module}/../observability/dynatrace/management-zones/spark-observability"

  management_zone = jsondecode(templatefile("${local.dt_mz_dir}/management-zone.json", {
    DT_MANAGEMENT_ZONE    = var.dt_management_zone_name
    DT_HOST_GROUP         = var.dt_host_group
    K8S_DYNATRACE_CLUSTER = var.k8s_dynatrace_cluster
  }))

  auto_tags = jsondecode(templatefile("${local.dt_mz_dir}/auto-tags.json.j2", {
    DT_HOST_GROUP         = var.dt_host_group
    K8S_DYNATRACE_CLUSTER = var.k8s_dynatrace_cluster
    tags = [
      { key = "Project", value = "spark-observability" },
      { key = "Environment", value = var.dt_environment },
      { key = "OwnedBy", value = var.dt_owned_by },
    ]
  }))

  alerting_profile = jsondecode(templatefile("${local.dt_integrations_dir}/spark-alerting-profile.json.j2", {
    dt_sn_alerting_profile_name  = "Spark Observability - ServiceNow brooks-lab"
    dt_management_zone_object_id = dynatrace_generic_setting.management_zone.id
  }))

  cpu_metric_event = jsondecode(templatefile("${local.dt_integrations_dir}/spark-cpu-metric-event.json.j2", {
    DT_HOST_GROUP                  = var.dt_host_group
    dt_l2i_environment             = var.dt_environment
    dt_management_zone_resolved    = var.dt_management_zone_name
    dt_sn_cpu_metric_event_summary = "Spark Lab - Host CPU above 50%"
  }))

  error_log_event = jsondecode(templatefile("${local.dt_integrations_dir}/spark-error-log-event.json.j2", {
    dt_sn_spark_error_log_event_summary = "Spark Lab - ERROR and WARN log lines"
  }))

  custom_log_source = jsondecode(templatefile("${local.dt_integrations_dir}/standalone-short-log4j2-custom-source.json.j2", {
    dt_l2i_standalone_custom_source_name       = "Standalone short Log4j2 - application log files"
    dt_l2i_standalone_log_path_pattern         = "/opt/spark/logs/*.log"
    dt_l2i_standalone_log_path_pattern_rotated = "/opt/spark/logs/*.log.*"
    dt_l2i_standalone_service_instance         = "Spark-Standalone"
  }))

  standalone_openpipeline = jsondecode(templatefile("${local.dt_integrations_dir}/standalone-short-log4j2-openpipeline.json.j2", {
    dt_l2i_standalone_openpipeline_display_name = "Standalone short Log4j2 - log alerts"
    dt_l2i_standalone_openpipeline_custom_id    = "standalone-short-log4j2-log-alerts"
    dt_l2i_environment                          = var.dt_environment
  }))

  k8s_openpipeline = jsondecode(templatefile("${local.dt_integrations_dir}/k8s-short-log4j2-openpipeline.json.j2", {
    dt_l2i_k8s_openpipeline_display_name = "K8s short Log4j2 - log alerts"
    dt_l2i_k8s_openpipeline_custom_id    = "k8s-short-log4j2-log-alerts"
    dt_l2i_environment                   = var.dt_environment
  }))

  service_response_time = jsondecode(templatefile("${local.dt_integrations_dir}/spark-service-response-time-anomaly-detection.json.j2", {
    dt_spark_hostgroup_entity_id = var.dt_spark_hostgroup_entity_id
  }))
}

resource "dynatrace_generic_setting" "management_zone" {
  schema = local.management_zone.schemaId
  scope  = local.management_zone.scope
  value  = jsonencode(local.management_zone.value)
}

resource "dynatrace_generic_setting" "auto_tags" {
  for_each = { for t in local.auto_tags : t.value.name => t }

  schema = each.value.schemaId
  scope  = each.value.scope
  value  = jsonencode(each.value.value)
}

resource "dynatrace_generic_setting" "alerting_profile" {
  schema = local.alerting_profile.schemaId
  scope  = local.alerting_profile.scope
  value  = jsonencode(local.alerting_profile.value)
}

resource "dynatrace_generic_setting" "cpu_metric_event" {
  schema = local.cpu_metric_event.schemaId
  scope  = local.cpu_metric_event.scope
  value  = jsonencode(local.cpu_metric_event.value)
}

resource "dynatrace_generic_setting" "error_log_event" {
  schema = local.error_log_event.schemaId
  scope  = local.error_log_event.scope
  value  = jsonencode(local.error_log_event.value)
}

resource "dynatrace_generic_setting" "custom_log_source" {
  schema = local.custom_log_source.schemaId
  scope  = local.custom_log_source.scope
  value  = jsonencode(local.custom_log_source.value)
}

resource "dynatrace_generic_setting" "standalone_openpipeline" {
  schema = local.standalone_openpipeline.schemaId
  scope  = local.standalone_openpipeline.scope
  value  = jsonencode(local.standalone_openpipeline.value)
}

resource "dynatrace_generic_setting" "k8s_openpipeline" {
  schema = local.k8s_openpipeline.schemaId
  scope  = local.k8s_openpipeline.scope
  value  = jsonencode(local.k8s_openpipeline.value)
}

resource "dynatrace_generic_setting" "service_response_time" {
  schema = local.service_response_time.schemaId
  scope  = local.service_response_time.scope
  value  = jsonencode(local.service_response_time.value)
}
