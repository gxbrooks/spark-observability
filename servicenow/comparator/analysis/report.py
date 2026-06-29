#!/usr/bin/env python3
"""Build annotated JSON compare report from raw compare exports."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from servicenow.comparator.analysis.compare_analysis import (
    build_app_service_diff,
    build_host_diff,
    field_value,
    flatten_dt_by_type,
    flatten_dt_hosts,
    load_data,
    sn_host_rows,
    tag_binding_counts,
)
from servicenow.comparator.analysis.entity_links import enrich_entity, enrich_row, LinkContext, resolve_dynatrace_link_base
from servicenow.comparator.analysis.findings import (
    REPORT_VERSION,
    build_consolidated_findings,
    count_findings,
)

SEVERITY_ORDER = ("action_required", "warning", "informational", "ok")


def resolution_for(issue: str, app_row: dict | None = None) -> dict:
    common_csdm = {
        "commands": [
            "cd spark-observability",
            "PYTHONPATH=. python -m servicenow.comparator -e @vars/secrets.yaml",
        ],
        "docs": ["servicenow/docs/CSDM_Specifications.md"],
    }
    templates: dict[str, dict] = {
        "missing_in_cmdb": {
            "summary": "Application service is specified in CSDM but absent from CMDB.",
            "steps": [
                "Confirm the service entry in servicenow/regions/{region}/*.csdm.yaml.",
                "Run csdm/deploy.yml to create cmdb_ci_service_discovered and relationships.",
                "Re-run compare to verify present_in_cmdb.",
            ],
            **common_csdm,
        },
        "missing_tag_binding": {
            "summary": "Tag-based application service has no canonical servicenow.io tag bindings in CMDB.",
            "steps": [
                "Ensure Docker/Kubernetes runtime labels match the CSDM specification.",
                "Run discovery playbooks so cmdb_key_value rows are created.",
            ],
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md", "servicenow/docs/install.md"],
        },
        "alternate_tag_only": {
            "summary": "Only alternate tags are bound; canonical servicenow.io key is missing.",
            "steps": [
                "Add servicenow.io/application-service-identifier to workload labels.",
                "Re-run discovery to refresh cmdb_key_value.",
            ],
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md"],
        },
    }
    base = templates.get(issue, {"summary": "Review the observation.", "steps": [], "docs": []})
    if app_row and app_row.get("spec_file"):
        base = dict(base)
        base["spec_file"] = app_row["spec_file"]
    return base


def specified_apps(unit: dict) -> list[dict]:
    specified = unit.get("specified", {})
    if specified.get("application_services"):
        return specified["application_services"]
    return unit.get("intent", {}).get("application_services", [])


def sn_app_sys_ids(sn: dict) -> dict[str, str]:
    return {
        row.get("intent_name", ""): field_value(row.get("sys_id"))
        for row in sn.get("application_services", [])
        if row.get("intent_name") and field_value(row.get("sys_id"))
    }


def merge_intent_sources(sources: list[dict]) -> dict:
    merged = {
        "business_applications": [],
        "business_services": [],
        "application_services": [],
        "spec_files": [],
    }
    for source in sources or []:
        intent = source.get("intent") or source.get("specified") or {}
        for key in ("business_applications", "business_services", "application_services", "spec_files"):
            merged[key].extend(intent.get(key) or [])
    return merged


def normalize_export(data: dict) -> tuple[dict, dict]:
    if data.get("export_version"):
        intents = data.get("csdm_intent_sources") or []
        registry = (intents[0].get("registry") or {}) if intents else {}
        unit = {
            "scope_applied": data.get("scope_applied") or {},
            "generated_at": data.get("generated_at") or "",
            "instance": data.get("instance") or {},
            "servicenow": data.get("servicenow") or {},
            "dynatrace": data.get("dynatrace") or {},
            "dynatrace_correlation": data.get("dynatrace_correlation") or {},
            "intent": merge_intent_sources(intents),
            "csdm_intent_sources": intents,
            "registry": registry,
        }
        return unit, {}
    meta = data.get("_meta", {}) if isinstance(data.get("_meta"), dict) else {}
    units = {k: v for k, v in data.items() if not k.startswith("_")}
    if not units:
        return {}, meta
    if len(units) == 1:
        unit = next(iter(units.values()))
        registry = unit.get("scope_unit") or {}
        return {
            **unit,
            "registry": registry,
            "csdm_intent_sources": [{"registry": registry, "intent": unit.get("intent") or unit.get("specified") or {}}],
        }, meta
    merged_intents = []
    last = {}
    for scope_unit_id, unit in units.items():
        registry = unit.get("scope_unit") or {"scope_unit_id": scope_unit_id}
        merged_intents.append({"registry": registry, "intent": unit.get("intent") or unit.get("specified") or {}})
        last = unit
    return {
        "scope_applied": last.get("scope_applied") or {},
        "generated_at": last.get("generated_at") or "",
        "instance": last.get("instance") or meta.get("instance") or {},
        "servicenow": last.get("servicenow") or {},
        "dynatrace": last.get("dynatrace") or {},
        "intent": merge_intent_sources(merged_intents),
        "csdm_intent_sources": merged_intents,
    }, meta


def links_for_unit(unit: dict, meta: dict) -> LinkContext:
    inst = unit.get("instance", {}) or meta.get("instance", {}) or {}
    return LinkContext(
        servicenow_url=str(inst.get("servicenow_url") or meta.get("servicenow_url") or "").strip(),
        dynatrace_tenant_url=resolve_dynatrace_link_base(inst, meta),
    )


def analyze_comparison(unit: dict, links: LinkContext, comparator_dir: Path) -> dict:
    scope_applied = unit.get("scope_applied", {})
    intent_apps = specified_apps(unit)
    sn = unit.get("servicenow", {})
    dt = unit.get("dynatrace", {})
    dt_entities = dt.get("entities", {})
    dt_hosts = flatten_dt_hosts(dt_entities)
    matched, sn_only, dt_only = build_host_diff(sn.get("hosts", []), dt_hosts)
    canonical_counts, alternate_counts = tag_binding_counts(sn.get("tag_bindings", []))
    app_diff = build_app_service_diff(
        intent_apps,
        sn.get("application_services", []),
        canonical_counts,
        alternate_counts,
    )
    spec_names = {a.get("name") for a in intent_apps if a.get("name")}
    cmdb_apps = sn.get("application_services_cmdb", [])

    consolidated = build_consolidated_findings(unit, links, comparator_dir)
    finding_counts = count_findings(consolidated)

    enriched_matched = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in matched]
    enriched_sn_only = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in sn_only]
    enriched_dt_only = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in dt_only]
    enriched_hosts = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in sn_host_rows(sn.get("hosts", []))]
    enriched_dt_hosts = [
        enrich_row({"dynatrace_entity_id": h.get("entity_id"), "display_name": h.get("display_name")}, links.servicenow_url, links.dynatrace_tenant_url)
        for h in dt_hosts
    ]

    return {
        "scope_applied": scope_applied,
        "generated_at": unit.get("generated_at", ""),
        "csdm_intent_sources": unit.get("csdm_intent_sources", []),
        "instance": {
            "servicenow_url": links.servicenow_url,
            "dynatrace_ui_url": links.dynatrace_tenant_url,
        },
        "summary": {
            "findings_subclass_groups": finding_counts.get("action_required", 0)
            + finding_counts.get("warning", 0)
            + finding_counts.get("informational", 0),
            "findings_by_severity": {
                k: finding_counts.get(k, 0)
                for k in ("action_required", "warning", "informational", "ok")
            },
            "finding_items_total": finding_counts.get("total_items", 0),
            "hosts_matched": len(matched),
            "hosts_servicenow_only": len(sn_only),
            "hosts_dynatrace_only": len(dt_only),
            "specified_application_services": len(intent_apps),
            "cmdb_application_services": len(cmdb_apps),
            "app_missing_cmdb": sum(1 for r in app_diff if r["status"] == "missing_in_cmdb"),
            "app_missing_tags": sum(1 for r in app_diff if r["status"] == "missing_tag_binding"),
            "canonical_tag_bindings": len(sn.get("tag_bindings_canonical", [])),
            "object_sources_sgo_dynatrace": len(sn.get("object_sources", [])),
            "dt_hosts": len(dt_hosts),
            "dt_process_groups": len(flatten_dt_by_type(dt_entities, "PROCESS_GROUP")),
            "dt_kubernetes_clusters": len(flatten_dt_by_type(dt_entities, "KUBERNETES_CLUSTER")),
        },
        "findings": consolidated,
        "inventory": {
            "host_alignment": {
                "description": "Linux servers (ServiceNow) vs HOST entities (Dynatrace), matched by short hostname.",
                "matched": enriched_matched,
                "servicenow_only": enriched_sn_only,
                "dynatrace_only": enriched_dt_only,
            },
            "application_services": {
                "description": "CSDM-specified application services correlated with CMDB and tag bindings.",
                "diff": app_diff,
            },
            "servicenow_hosts": enriched_hosts,
            "servicenow_object_sources": [
                enrich_entity(
                    {
                        "type": "sys_object_source",
                        "table": "sys_object_source",
                        "entity_id": field_value(r.get("id")),
                        "target_sys_id": field_value(r.get("target_sys_id")),
                        "target_table": field_value(r.get("target_table")),
                    },
                    links.servicenow_url,
                    links.dynatrace_tenant_url,
                )
                for r in sn.get("object_sources", [])
            ],
            "servicenow_tag_bindings": [
                enrich_entity(
                    {**row, "type": "cmdb_key_value", "table": "cmdb_key_value"},
                    links.servicenow_url,
                    links.dynatrace_tenant_url,
                )
                for row in sn.get("tag_bindings", [])
            ],
            "servicenow_application_services_cmdb": [
                enrich_entity(
                    {
                        "type": "application_service",
                        "table": "cmdb_ci_service_discovered",
                        "name": field_value(r.get("name")),
                        "sys_id": field_value(r.get("sys_id")),
                        "operational_status": field_value(r.get("operational_status")),
                        "process_status": field_value(r.get("process_status")),
                        "service_status": field_value(r.get("service_status")),
                        "in_specification": field_value(r.get("name")) in spec_names,
                    },
                    links.servicenow_url,
                    links.dynatrace_tenant_url,
                )
                for r in cmdb_apps
            ],
            "dynatrace_entities_summary": {
                "scope_mode": dt.get("scope_mode", "all"),
                "hosts": enriched_dt_hosts,
                "process_groups_count": len(flatten_dt_by_type(dt_entities, "PROCESS_GROUP")),
                "services_count": len(flatten_dt_by_type(dt_entities, "SERVICE")),
                "kubernetes_clusters": [
                    enrich_row({"dynatrace_entity_id": c.get("entity_id"), "display_name": c.get("display_name")}, links.servicenow_url, links.dynatrace_tenant_url)
                    for c in flatten_dt_by_type(dt_entities, "KUBERNETES_CLUSTER")
                ],
                "kubernetes_nodes_count": len(flatten_dt_by_type(dt_entities, "KUBERNETES_NODE")),
            },
        },
    }


def build_report(data: dict, comparator_dir: Path | None = None) -> dict:
    unit, meta = normalize_export(data)
    links = links_for_unit(unit, meta)
    comp_dir = comparator_dir or Path(__file__).resolve().parents[1]
    analyzed = analyze_comparison(unit, links, comp_dir)
    summary = analyzed.pop("summary")
    return {
        "report_version": REPORT_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scope_applied": analyzed.get("scope_applied", {}),
        "csdm_intent_sources": analyzed.get("csdm_intent_sources", []),
        "instance": analyzed.get("instance", {}),
        "summary": summary,
        "navigation": {
            "description": (
                "findings is a consolidated tree: A_dual_discoverable, B_dynatrace_injected, "
                "C_specification_alignment. Each subcategory contains subclasses with cmdb_class "
                "and smartscape_entity_type."
            ),
            "severity_levels": list(SEVERITY_ORDER),
        },
        "findings": analyzed.get("findings", {}),
        "inventory": analyzed.get("inventory", {}),
    }


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <DT_SN_Model_Comparison.json> [DT_SN_Model_Comparison_Report.json]", file=sys.stderr)
        return 2
    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) == 3 else input_path.parent / "DT_SN_Model_Comparison_Report.json"
    data = load_data(input_path)
    report = build_report(data)
    output_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote report: {output_path}")
    summary = report["summary"]
    sev = summary.get("findings_by_severity", {})
    print(
        f"  subclass_groups={summary.get('findings_subclass_groups', 0)} "
        f"items={summary.get('finding_items_total', 0)} "
        f"(action_required={sev.get('action_required', 0)} warning={sev.get('warning', 0)} "
        f"informational={sev.get('informational', 0)}) "
        f"hosts matched={summary.get('hosts_matched', 0)} "
        f"app_missing_tags={summary.get('app_missing_tags', 0)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
