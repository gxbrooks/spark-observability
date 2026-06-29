# DT_SN_Model_Comparison_Report — structural outline

Generated from `DT_SN_Model_Comparison_Report.json`. Numeric inventory values are array lengths from that run.

```json
{
  "report_version": "1.2",
  "generated_at": "2026-06-27T21:58:21Z",
  "scope_applied": {
    "dynatrace": {
      "management_zones": [],
      "mode": "all"
    },
    "servicenow": {
      "location": "",
      "mode": "all"
    }
  },
  "csdm_intent_sources": {
    "count": 1,
    "item": {
      "registry": "scope_unit_id, region_id, …",
      "intent": "BA, BS, application_services"
    }
  },
  "instance": {
    "servicenow_url": "…",
    "dynatrace_ui_url": "…"
  },
  "summary": {
    "findings_total": 35,
    "findings_by_severity": {
      "warning": 1,
      "informational": 2,
      "action_required": 32
    },
    "hosts_matched": 4,
    "hosts_servicenow_only": 28,
    "hosts_dynatrace_only": 2,
    "specified_application_services": 18,
    "cmdb_application_services": 2000,
    "canonical_tag_bindings": 36,
    "dt_hosts": 6,
    "dt_process_groups": 178
  },
  "navigation": {
    "severity_levels": "action_required, warning, informational, ok",
    "categories_count": 7
  },
  "findings": {
    "count": 35,
    "item_keys": "id, severity, category, issue, title, entity, observation, recommendation, resolution",
    "entity_keys": "type, name, url, sys_id, entity_id",
    "resolution_keys": "summary, steps, commands, docs"
  },
  "findings_by_category": {
    "cross_platform_alignment": 30,
    "dynatrace_inventory": 1,
    "dynatrace_setup": 2,
    "servicenow_extra": 1,
    "servicenow_setup": 1
  },
  "inventory": {
    "host_alignment": {
      "matched": 4,
      "servicenow_only": 28,
      "dynatrace_only": 2
    },
    "application_services_diff": 18,
    "servicenow_hosts": 32,
    "servicenow_tag_bindings": 295,
    "servicenow_application_services_cmdb": 2000,
    "dynatrace_entities_summary": {
      "scope_mode": "full_tenant",
      "hosts": 6,
      "process_groups_count": 178,
      "kubernetes_clusters": 1
    }
  }
}
```
