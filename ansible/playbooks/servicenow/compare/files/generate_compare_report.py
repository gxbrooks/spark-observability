#!/usr/bin/env python3
"""Build annotated JSON compare report from raw compare_data.json exports."""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from compare_analysis import (
    CANONICAL_TAG_KEY,
    build_app_service_diff,
    build_host_diff,
    build_partitioning_diagnostics,
    field_value,
    flatten_dt_by_type,
    flatten_dt_hosts,
    load_data,
    normalize_host,
    sn_host_rows,
    tag_binding_counts,
)
from entity_links import enrich_entity, enrich_row, resolve_dynatrace_link_base, sn_record_url

REPORT_VERSION = "1.2"

CATEGORY_TITLES = {
    "servicenow_setup": "ServiceNow setup (specification not reflected in CMDB)",
    "servicenow_tags": "ServiceNow tag-based Service Mapping",
    "servicenow_placement": "ServiceNow CMDB placement",
    "servicenow_extra": "ServiceNow CMDB objects outside specification",
    "cross_platform_alignment": "Cross-platform host and service alignment",
    "dynatrace_setup": "Dynatrace partitioning and monitoring setup",
    "dynatrace_inventory": "Dynatrace model attributes (informational)",
}

SEVERITY_ORDER = ("action_required", "warning", "informational", "ok")


@dataclass
class LinkContext:
    servicenow_url: str = ""
    dynatrace_tenant_url: str = ""


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def resolution_for(issue: str, app_row: dict | None = None) -> dict:
    common_csdm = {
        "commands": [
            "cd ansible",
            "ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml -e @../vars/secrets.yaml",
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
                "Ensure Docker/Kubernetes runtime labels match the CSDM tags block.",
                "Run discovery/docker/discover.yml so cmdb_key_value rows are created.",
                "If cmdb_key_value writes fail, fix ACLs on the ServiceNow instance (servicenow/docs/install.md).",
                "Re-run compare after discovery completes.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml -e @../vars/secrets.yaml",
            ],
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md", "servicenow/docs/install.md"],
        },
        "alternate_tag_only": {
            "summary": "Only alternate tags (app.kubernetes.io/name or app) are bound; canonical servicenow.io key is missing.",
            "steps": [
                "Add servicenow.io/application-service-identifier to workload labels per CSDM spec.",
                "Re-run Docker or K8s discovery to refresh cmdb_key_value.",
                "Prefer canonical tag for stable Service Mapping correlation.",
            ],
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md"],
        },
        "servicenow_only_host": {
            "summary": "Linux server exists in ServiceNow CMDB but has no matching Dynatrace HOST entity.",
            "steps": [
                "Verify Dynatrace OneAgent is installed on the host.",
                "Confirm the host reports to the expected tenant.",
                "Run horizontal discovery if the host should exist in CMDB but is missing from the export scope.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml -e @../vars/secrets.yaml",
            ],
            "docs": ["servicenow/docs/install.md", "observability/dynatrace/README.md"],
        },
        "dynatrace_only_host": {
            "summary": "Dynatrace monitors a host that is not in the ServiceNow CMDB export.",
            "steps": [
                "Run horizontal discovery to create cmdb_ci_linux_server when the host should be in ServiceNow.",
                "For SGC correlation, ensure discovered hosts receive the correct CMDB location.",
                "Retire OneAgent on hosts that should not be monitored if the Dynatrace record is stale.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml -e @../vars/secrets.yaml",
            ],
            "docs": ["servicenow/docs/install.md"],
        },
        "cmdb_extra_application_service": {
            "summary": "Application service exists in CMDB but is not declared in the region CSDM specification.",
            "steps": [
                "Determine whether the service is intentional (manual, legacy, or imported by SGC/Dynatrace).",
                "If it should be managed by this repo, add it to servicenow/regions/{region}/*.csdm.yaml.",
                "If it is stale or test data, retire or delete the CMDB CI.",
                "SGC-imported services may carry Dynatrace-derived attributes — review before deleting.",
            ],
            "docs": ["servicenow/docs/DT_SN_Comparison_Process.md"],
        },
        "missing_management_zone": {
            "summary": "Dynatrace entity is not assigned to the management zone declared in the correlation spec.",
            "steps": [
                "Re-apply management zone rules from observability/dynatrace/tenants/{tenant}/management-zones/.",
                "Verify host group and K8s cluster name match dynatrace-correlation.yaml.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml -e @../vars/secrets.yaml --tags partitioning",
            ],
            "docs": ["observability/dynatrace/README.md", "ansible/playbooks/servicenow/compare/dynatrace-correlation.yaml"],
        },
        "missing_process_group_management_zone": {
            "summary": "Hosts are assigned to a management zone but process groups are not propagating that zone.",
            "steps": [
                "Verify hostToPGPropagation on the HOST rule in management-zone.json.",
                "Confirm OneAgent assigns the expected host group.",
                "Re-apply partitioning after rule changes.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml -e @../vars/secrets.yaml --tags partitioning",
            ],
            "docs": ["observability/dynatrace/tenants/pdt20158/docs/Partitioning_and_Tagging.md"],
        },
        "location_mismatch": {
            "summary": "CMDB host location does not match the scope correlation registry location.",
            "steps": [
                "Update cmn_location on the Linux server CI in ServiceNow, or",
                "Adjust cmdb_location in servicenow/regions/{region}/region.yaml if the registry value is wrong.",
            ],
            "docs": ["servicenow/README.md"],
        },
        "process_status_not_discovered": {
            "summary": "Application service exists but Service Mapping process_status is not Discovered.",
            "steps": [
                "For tag-based services: verify tag bindings and Service Mapping rules.",
                "For vertical discovery: trigger discovery and wait for completion; re-run csdm/diagnose.yml.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml",
            ],
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md"],
        },
        "hosts_without_management_zone": {
            "summary": "Dynatrace HOST entities in the export have no management zone assignment.",
            "steps": [
                "Review management zone rules and host group assignment.",
                "Re-apply partitioning when rules should assign a zone to these hosts.",
            ],
            "docs": ["observability/dynatrace/README.md"],
        },
    }
    base = templates.get(issue, {"summary": "Review the observation and correlation spec.", "steps": [], "docs": []})
    if app_row and app_row.get("spec_file"):
        base = dict(base)
        base["spec_file"] = app_row["spec_file"]
    return base


def make_finding(
    category: str,
    severity: str,
    issue: str,
    title: str,
    observation: str,
    links: LinkContext,
    entity: dict | None = None,
    recommendation: str = "",
    app_row: dict | None = None,
) -> dict:
    entity = enrich_entity(entity or {}, links.servicenow_url, links.dynatrace_tenant_url) or {}
    entity_name = entity.get("name") or entity.get("entity_name") or entity.get("display_name") or ""
    finding_id = f"{category}:{issue}:{slug(entity_name or 'summary')}"
    resolution = resolution_for(issue, app_row)
    if recommendation:
        resolution = dict(resolution)
        resolution["correlation_recommendation"] = recommendation
    return {
        "id": finding_id,
        "severity": severity,
        "category": category,
        "category_title": CATEGORY_TITLES.get(category, category),
        "issue": issue,
        "title": title,
        "entity": entity,
        "observation": observation,
        "recommendation": recommendation or resolution.get("summary", ""),
        "resolution": resolution,
    }


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
    """Return a single comparison unit and optional legacy meta."""
    if data.get("export_version"):
        intents = data.get("csdm_intent_sources") or []
        unit = {
            "scope_applied": data.get("scope_applied") or {},
            "generated_at": data.get("generated_at") or "",
            "instance": data.get("instance") or {},
            "servicenow": data.get("servicenow") or {},
            "dynatrace": data.get("dynatrace") or {},
            "dynatrace_correlation": data.get("dynatrace_correlation") or {},
            "intent": merge_intent_sources(intents),
            "csdm_intent_sources": intents,
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


def analyze_comparison(unit: dict, links: LinkContext) -> dict:
    registry = unit.get("registry") or unit.get("scope_unit") or {}
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
    app_sys_ids = sn_app_sys_ids(sn)

    findings: list[dict] = []
    spec_names = {a.get("name") for a in intent_apps if a.get("name")}
    cmdb_apps = sn.get("application_services_cmdb", [])
    cmdb_by_name = {field_value(a.get("name")): a for a in cmdb_apps if field_value(a.get("name"))}

    for row in app_diff:
        sys_id = app_sys_ids.get(row["name"], "")
        app_entity = {
            "type": "application_service",
            "table": "cmdb_ci_service_discovered",
            "name": row["name"],
            "identifier": row["identifier"],
            "spec_file": row.get("spec_file", ""),
            "sys_id": sys_id,
        }
        if row["status"] == "missing_in_cmdb":
            findings.append(
                make_finding(
                    "servicenow_setup", "action_required", "missing_in_cmdb",
                    f"Application service not in CMDB: {row['name']}",
                    f"'{row['name']}' (identifier: {row['identifier']}) is in CSDM spec {row.get('spec_file', '')} but not found in cmdb_ci_service_discovered.",
                    links, entity=app_entity, app_row=row,
                )
            )
        elif row["status"] == "missing_tag_binding":
            findings.append(
                make_finding(
                    "servicenow_tags", "action_required", "missing_tag_binding",
                    f"Missing canonical tag bindings: {row['name']}",
                    f"No cmdb_key_value rows for {CANONICAL_TAG_KEY} with value '{row['identifier']}'. Tag-based Service Mapping cannot correlate this service.",
                    links, entity=app_entity, app_row=row,
                )
            )
        elif row["status"] == "ok_alternate_tag_only":
            findings.append(
                make_finding(
                    "servicenow_tags", "warning", "alternate_tag_only",
                    f"Alternate tags only (no canonical key): {row['name']}",
                    f"Found {row['alternate_tag_count']} alternate tag binding(s) but 0 canonical {CANONICAL_TAG_KEY} bindings for identifier '{row['identifier']}'.",
                    links, entity=app_entity, app_row=row,
                )
            )
        elif row["status"] in ("ok_canonical_tag", "present_in_cmdb") and row.get("process_status") not in ("", "1", 1):
            findings.append(
                make_finding(
                    "servicenow_setup", "warning", "process_status_not_discovered",
                    f"Service Mapping not fully discovered: {row['name']}",
                    f"process_status={row.get('process_status', '')} (1=Discovered). service_status={row.get('service_status', '')}.",
                    links, entity=app_entity, app_row=row,
                )
            )

    extras_cmdb = []
    for name, cmdb_row in sorted(cmdb_by_name.items()):
        if name not in spec_names:
            sys_id = field_value(cmdb_row.get("sys_id"))
            extras_cmdb.append(
                {
                    "type": "application_service",
                    "table": "cmdb_ci_service_discovered",
                    "name": name,
                    "sys_id": sys_id,
                    "url": sn_record_url(links.servicenow_url, "cmdb_ci_service_discovered", sys_id),
                    "process_status": field_value(cmdb_row.get("process_status")),
                    "service_status": field_value(cmdb_row.get("service_status")),
                }
            )
    if extras_cmdb:
        sample_limit = 25
        sample_items = extras_cmdb[:sample_limit]
        findings.append(
            make_finding(
                "servicenow_extra", "informational", "cmdb_extra_application_service",
                f"{len(extras_cmdb)} CMDB application service(s) not in region specification",
                "These application services exist in cmdb_ci_service_discovered but are not declared in CSDM specs. "
                "They may be manual, legacy, or imported by SGC/Dynatrace integration. "
                f"See inventory.servicenow_application_services_cmdb where in_specification=false for the full list ({len(extras_cmdb)} rows).",
                links,
                entity={
                    "type": "application_service",
                    "count": len(extras_cmdb),
                    "sample_count": len(sample_items),
                    "items": sample_items,
                },
            )
        )

    for row in sn_only:
        findings.append(
            make_finding(
                "cross_platform_alignment", "action_required", "servicenow_only_host",
                f"Host in ServiceNow only: {row.get('servicenow_name', row.get('normalized_name'))}",
                f"Linux server '{row.get('servicenow_name')}' (location: {row.get('servicenow_location', '') or '(none)'}) has no matching Dynatrace HOST in the export.",
                links,
                entity={
                    "type": "cmdb_ci_linux_server",
                    "table": "cmdb_ci_linux_server",
                    "name": row.get("servicenow_name", ""),
                    "sys_id": row.get("servicenow_sys_id", ""),
                    "normalized_name": row.get("normalized_name", ""),
                    "location": row.get("servicenow_location", ""),
                },
            )
        )

    for row in dt_only:
        findings.append(
            make_finding(
                "cross_platform_alignment", "action_required", "dynatrace_only_host",
                f"Host in Dynatrace only: {row.get('dynatrace_display_name', row.get('normalized_name'))}",
                f"Dynatrace HOST '{row.get('dynatrace_display_name')}' (entityId: {row.get('dynatrace_entity_id')}) "
                f"has no matching cmdb_ci_linux_server. Management zones: {row.get('dynatrace_management_zones', '') or '(none)'}.",
                links,
                entity={
                    "type": "HOST",
                    "name": row.get("dynatrace_display_name", ""),
                    "entity_id": row.get("dynatrace_entity_id", ""),
                    "normalized_name": row.get("normalized_name", ""),
                    "management_zones": row.get("dynatrace_management_zones", ""),
                },
            )
        )

    registry_location = registry.get("cmdb_location", "")
    for row in matched:
        if row.get("servicenow_location") and registry_location:
            if row["servicenow_location"].lower() != registry_location.lower():
                findings.append(
                    make_finding(
                        "servicenow_placement", "warning", "location_mismatch",
                        f"Matched host location differs from scope registry: {row.get('servicenow_name')}",
                        f"CMDB location '{row.get('servicenow_location')}' != scope registry cmdb_location '{registry_location}'. "
                        f"Dynatrace management zones: {row.get('dynatrace_management_zones', '') or '(none)'}.",
                        links,
                        entity={
                            "type": "host_alignment",
                            "servicenow_name": row.get("servicenow_name"),
                            "servicenow_sys_id": row.get("servicenow_sys_id"),
                            "dynatrace_entity_id": row.get("dynatrace_entity_id"),
                        },
                        recommendation=unit.get("dynatrace_correlation", {}).get("recommendations", {}).get("sn_location_mismatch", ""),
                    )
                )

    for diag in build_partitioning_diagnostics(unit, sn.get("hosts", []), dt_entities):
        if diag.get("status") == "ok":
            continue
        severity = "action_required" if diag.get("status") in ("action_required", "missing_entity") else "warning"
        issue = diag.get("issue") or "partitioning_issue"
        findings.append(
            make_finding(
                "dynatrace_setup", severity, issue,
                f"Dynatrace partitioning: {diag.get('entity_name', issue)}",
                diag.get("detail", ""),
                links,
                entity={
                    "type": diag.get("entity_type", ""),
                    "name": diag.get("entity_name", ""),
                    "entity_id": diag.get("entity_id", ""),
                },
                recommendation=diag.get("recommendation", ""),
            )
        )

    hosts_no_mz = [h for h in dt_hosts if not (h.get("management_zones") or "").strip()]
    if hosts_no_mz:
        sample_limit = 25
        sample_hosts = hosts_no_mz[:sample_limit]
        items = [
            {
                "type": "HOST",
                "name": h.get("display_name", ""),
                "entity_id": h.get("entity_id", ""),
                "url": enrich_row({"dynatrace_entity_id": h.get("entity_id")}, links.servicenow_url, links.dynatrace_tenant_url).get("dynatrace_url", ""),
            }
            for h in sample_hosts
        ]
        findings.append(
            make_finding(
                "dynatrace_inventory", "informational", "hosts_without_management_zone",
                f"{len(hosts_no_mz)} Dynatrace HOST entities have no management zone assignment",
                "Management zone membership is empty on these HOST records in the Dynatrace export. "
                f"See inventory.dynatrace_entities_summary.hosts for all HOST rows ({len(hosts_no_mz)} without a zone).",
                links,
                entity={"type": "HOST", "count": len(hosts_no_mz), "sample_count": len(items), "items": items},
            )
        )

    findings_by_category: dict[str, list[dict]] = defaultdict(list)
    for finding in findings:
        findings_by_category[finding["category"]].append(finding)

    severity_counts = defaultdict(int)
    for finding in findings:
        severity_counts[finding["severity"]] += 1

    enriched_matched = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in matched]
    enriched_sn_only = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in sn_only]
    enriched_dt_only = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in dt_only]
    enriched_hosts = [enrich_row(r, links.servicenow_url, links.dynatrace_tenant_url) for r in sn_host_rows(sn.get("hosts", []))]
    enriched_dt_hosts = [enrich_row({"dynatrace_entity_id": h.get("entity_id"), "display_name": h.get("display_name")}, links.servicenow_url, links.dynatrace_tenant_url) for h in dt_hosts]

    return {
        "scope_applied": scope_applied,
        "generated_at": unit.get("generated_at", ""),
        "csdm_intent_sources": unit.get("csdm_intent_sources", []),
        "instance": {
            "servicenow_url": links.servicenow_url,
            "dynatrace_ui_url": links.dynatrace_tenant_url,
        },
        "summary": {
            "findings_total": len(findings),
            "findings_by_severity": dict(severity_counts),
            "hosts_matched": len(matched),
            "hosts_servicenow_only": len(sn_only),
            "hosts_dynatrace_only": len(dt_only),
            "specified_application_services": len(intent_apps),
            "cmdb_application_services": len(cmdb_apps),
            "cmdb_extra_vs_spec": max(0, len(cmdb_by_name) - len(spec_names & set(cmdb_by_name))),
            "app_missing_cmdb": sum(1 for r in app_diff if r["status"] == "missing_in_cmdb"),
            "app_missing_tags": sum(1 for r in app_diff if r["status"] == "missing_tag_binding"),
            "canonical_tag_bindings": len(sn.get("tag_bindings_canonical", [])),
            "dt_hosts": len(dt_hosts),
            "dt_process_groups": len(flatten_dt_by_type(dt_entities, "PROCESS_GROUP")),
            "dt_kubernetes_clusters": len(flatten_dt_by_type(dt_entities, "KUBERNETES_CLUSTER")),
        },
        "navigation": {
            "categories": [
                {"id": cat_id, "title": CATEGORY_TITLES.get(cat_id, cat_id), "finding_count": len(findings_by_category.get(cat_id, []))}
                for cat_id in CATEGORY_TITLES
                if findings_by_category.get(cat_id)
            ],
        },
        "findings": sorted(
            findings,
            key=lambda f: (SEVERITY_ORDER.index(f["severity"]) if f["severity"] in SEVERITY_ORDER else 99, f["category"], f["title"]),
        ),
        "findings_by_category": {k: v for k, v in sorted(findings_by_category.items())},
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


def links_for_unit(unit: dict, meta: dict) -> LinkContext:
    inst = unit.get("instance", {}) or meta.get("instance", {}) or {}
    return LinkContext(
        servicenow_url=str(inst.get("servicenow_url") or meta.get("servicenow_url") or "").strip(),
        dynatrace_tenant_url=resolve_dynatrace_link_base(inst, meta),
    )


def build_report(data: dict) -> dict:
    unit, meta = normalize_export(data)
    links = links_for_unit(unit, meta)
    analyzed = analyze_comparison(unit, links)
    summary = analyzed.pop("summary")
    return {
        "report_version": REPORT_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scope_applied": analyzed.get("scope_applied", {}),
        "csdm_intent_sources": analyzed.get("csdm_intent_sources", []),
        "instance": analyzed.get("instance", {}),
        "summary": summary,
        "navigation": {
            "description": "Open findings[] for a flat list, or findings_by_category. Entity url fields are clickable in JSON-aware editors.",
            "severity_levels": list(SEVERITY_ORDER),
            "categories": [{"id": cat_id, "title": title} for cat_id, title in CATEGORY_TITLES.items()],
        },
        "findings": analyzed.get("findings", []),
        "findings_by_category": analyzed.get("findings_by_category", {}),
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
        f"  findings={summary.get('findings_total', 0)} "
        f"(action_required={sev.get('action_required', 0)} warning={sev.get('warning', 0)} "
        f"informational={sev.get('informational', 0)}) "
        f"hosts matched={summary.get('hosts_matched', 0)} "
        f"app_missing_tags={summary.get('app_missing_tags', 0)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
