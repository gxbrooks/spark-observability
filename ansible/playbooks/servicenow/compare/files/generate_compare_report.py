#!/usr/bin/env python3
"""Build annotated JSON compare report from raw compare_data.json exports."""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
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

REPORT_VERSION = "1.0"

CATEGORY_TITLES = {
    "servicenow_setup": "ServiceNow setup (specification not reflected in CMDB)",
    "servicenow_tags": "ServiceNow tag-based Service Mapping",
    "servicenow_placement": "ServiceNow CMDB placement",
    "servicenow_extra": "ServiceNow CMDB objects outside specification",
    "cross_platform_alignment": "Cross-platform host and service alignment",
    "dynatrace_setup": "Dynatrace partitioning and monitoring setup",
    "dynatrace_inventory": "Dynatrace tenant inventory (informational)",
}

SEVERITY_ORDER = ("action_required", "warning", "informational", "ok")


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def resolution_for(issue: str, app_row: dict | None = None) -> dict:
    """Return structured resolution guidance for a known issue code."""
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
                "Confirm the host reports to the expected tenant and host group.",
                "If the host is out of scope, adjust CMDB or discovery scope.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml -e @../vars/secrets.yaml",
            ],
            "docs": ["observability/dynatrace/README.md"],
        },
        "dynatrace_only_host": {
            "summary": "Dynatrace monitors a host that is not in the ServiceNow CMDB export.",
            "steps": [
                "If the host belongs to this management region, run horizontal discovery to create cmdb_ci_linux_server.",
                "If the host is outside project scope, no CMDB action is required; note for tenant hygiene.",
                "For SGC correlation, ensure discovered hosts receive the correct CMDB location.",
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
            "docs": ["servicenow/docs/DT_CN_Comparison_Process.md"],
        },
        "missing_management_zone": {
            "summary": "Dynatrace entity is not in the expected management zone.",
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
            "summary": "Project hosts are partitioned but process groups are not propagating the management zone.",
            "steps": [
                "Verify hostToPGPropagation on the HOST rule in management-zone.json.",
                "Confirm OneAgent assigns host group spark-observability (or configured group).",
                "Re-apply partitioning after rule changes.",
            ],
            "commands": [
                "cd ansible",
                "ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml -e @../vars/secrets.yaml --tags partitioning",
            ],
            "docs": ["observability/dynatrace/tenants/pdt20158/docs/Partitioning_and_Tagging.md"],
        },
        "location_mismatch": {
            "summary": "CMDB host location does not match the management region cmdb_location hint.",
            "steps": [
                "Update cmn_location on the Linux server CI in ServiceNow, or",
                "Adjust cmdb_location in servicenow/regions/{region}/region.yaml if the hint is wrong.",
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
    }
    base = templates.get(issue, {"summary": "Review the observation and correlation spec.", "steps": [], "docs": []})
    if app_row and app_row.get("spec_file"):
        base = dict(base)
        base["spec_file"] = app_row["spec_file"]
    return base


def make_finding(
    scope_unit_id: str,
    category: str,
    severity: str,
    issue: str,
    title: str,
    observation: str,
    entity: dict | None = None,
    recommendation: str = "",
    app_row: dict | None = None,
) -> dict:
    entity = entity or {}
    entity_name = entity.get("name") or entity.get("entity_name") or entity.get("display_name") or ""
    finding_id = f"{scope_unit_id}:{category}:{issue}:{slug(entity_name or 'summary')}"
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


def analyze_scope_unit(scope_unit_id: str, unit: dict) -> dict:
    scope = unit.get("scope_unit", {})
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

    findings: list[dict] = []
    project_hosts = {
        normalize_host(h)
        for h in unit.get("dynatrace_correlation", {}).get("project_host_names", [])
        if h
    }

    # Application services — specification vs CMDB
    spec_names = {a.get("name") for a in intent_apps if a.get("name")}
    cmdb_apps = sn.get("application_services_cmdb", [])
    cmdb_by_name = {field_value(a.get("name")): a for a in cmdb_apps if field_value(a.get("name"))}

    for row in app_diff:
        if row["status"] == "missing_in_cmdb":
            findings.append(
                make_finding(
                    scope_unit_id,
                    "servicenow_setup",
                    "action_required",
                    "missing_in_cmdb",
                    f"Application service not in CMDB: {row['name']}",
                    f"'{row['name']}' (identifier: {row['identifier']}) is in CSDM spec {row.get('spec_file', '')} but not found in cmdb_ci_service_discovered.",
                    entity={"type": "application_service", "name": row["name"], "identifier": row["identifier"], "spec_file": row.get("spec_file", "")},
                    app_row=row,
                )
            )
        elif row["status"] == "missing_tag_binding":
            findings.append(
                make_finding(
                    scope_unit_id,
                    "servicenow_tags",
                    "action_required",
                    "missing_tag_binding",
                    f"Missing canonical tag bindings: {row['name']}",
                    f"No cmdb_key_value rows for {CANONICAL_TAG_KEY} with value '{row['identifier']}'. Tag-based Service Mapping cannot correlate this service.",
                    entity={"type": "application_service", "name": row["name"], "identifier": row["identifier"]},
                    app_row=row,
                )
            )
        elif row["status"] == "ok_alternate_tag_only":
            findings.append(
                make_finding(
                    scope_unit_id,
                    "servicenow_tags",
                    "warning",
                    "alternate_tag_only",
                    f"Alternate tags only (no canonical key): {row['name']}",
                    f"Found {row['alternate_tag_count']} alternate tag binding(s) but 0 canonical {CANONICAL_TAG_KEY} bindings for identifier '{row['identifier']}'.",
                    entity={"type": "application_service", "name": row["name"], "identifier": row["identifier"]},
                    app_row=row,
                )
            )
        elif row["status"] in ("ok_canonical_tag", "present_in_cmdb") and row.get("process_status") not in ("", "1", 1):
            findings.append(
                make_finding(
                    scope_unit_id,
                    "servicenow_setup",
                    "warning",
                    "process_status_not_discovered",
                    f"Service Mapping not fully discovered: {row['name']}",
                    f"process_status={row.get('process_status', '')} (1=Discovered). service_status={row.get('service_status', '')}.",
                    entity={"type": "application_service", "name": row["name"], "identifier": row["identifier"]},
                    app_row=row,
                )
            )

    # CMDB application services not in specification (may include SGC/Dynatrace imports)
    extras_cmdb = []
    for name, cmdb_row in sorted(cmdb_by_name.items()):
        if name not in spec_names:
            extras_cmdb.append(
                {
                    "name": name,
                    "sys_id": field_value(cmdb_row.get("sys_id")),
                    "process_status": field_value(cmdb_row.get("process_status")),
                    "service_status": field_value(cmdb_row.get("service_status")),
                }
            )
    if extras_cmdb:
        sample = [e["name"] for e in extras_cmdb[:10]]
        findings.append(
            make_finding(
                scope_unit_id,
                "servicenow_extra",
                "informational",
                "cmdb_extra_application_service",
                f"{len(extras_cmdb)} CMDB application service(s) not in region specification",
                "These application services exist in cmdb_ci_service_discovered but are not declared in CSDM specs. "
                "They may be manual, legacy, or created by SGC/Dynatrace integration.",
                entity={"type": "application_service", "count": len(extras_cmdb), "sample": sample, "items": extras_cmdb},
            )
        )

    # Host alignment — project-scoped hosts get individual findings; others are batched
    sn_only_project, sn_only_other = [], []
    for row in sn_only:
        (sn_only_project if row.get("normalized_name") in project_hosts else sn_only_other).append(row)

    dt_only_project, dt_only_other = [], []
    for row in dt_only:
        (dt_only_project if row.get("normalized_name") in project_hosts else dt_only_other).append(row)

    for row in sn_only_project:
        findings.append(
            make_finding(
                scope_unit_id,
                "cross_platform_alignment",
                "action_required",
                "servicenow_only_host",
                f"Project host in ServiceNow only: {row.get('servicenow_name', row.get('normalized_name'))}",
                f"Linux server '{row.get('servicenow_name')}' (location: {row.get('servicenow_location', '')}) has no matching Dynatrace HOST.",
                entity={
                    "type": "cmdb_ci_linux_server",
                    "name": row.get("servicenow_name", ""),
                    "sys_id": row.get("servicenow_sys_id", ""),
                    "normalized_name": row.get("normalized_name", ""),
                },
            )
        )

    if sn_only_other:
        findings.append(
            make_finding(
                scope_unit_id,
                "cross_platform_alignment",
                "informational",
                "servicenow_only_host",
                f"{len(sn_only_other)} ServiceNow host(s) without Dynatrace match (outside project scope)",
                "These Linux servers are in the CMDB export but have no matching Dynatrace HOST. "
                "Expected when CMDB scope is broader than the Dynatrace project.",
                entity={
                    "type": "cmdb_ci_linux_server",
                    "count": len(sn_only_other),
                    "sample": [r.get("servicenow_name") for r in sn_only_other[:10]],
                },
            )
        )

    for row in dt_only_project:
        findings.append(
            make_finding(
                scope_unit_id,
                "cross_platform_alignment",
                "action_required",
                "dynatrace_only_host",
                f"Project host in Dynatrace only: {row.get('dynatrace_display_name', row.get('normalized_name'))}",
                f"Dynatrace HOST '{row.get('dynatrace_display_name')}' (entityId: {row.get('dynatrace_entity_id')}) "
                f"has no matching cmdb_ci_linux_server. Management zones: {row.get('dynatrace_management_zones', '') or '(none)'}.",
                entity={
                    "type": "HOST",
                    "name": row.get("dynatrace_display_name", ""),
                    "entity_id": row.get("dynatrace_entity_id", ""),
                    "normalized_name": row.get("normalized_name", ""),
                    "management_zones": row.get("dynatrace_management_zones", ""),
                },
            )
        )

    if dt_only_other:
        findings.append(
            make_finding(
                scope_unit_id,
                "dynatrace_inventory",
                "informational",
                "dynatrace_only_host",
                f"{len(dt_only_other)} Dynatrace host(s) without ServiceNow CMDB match (outside project scope)",
                "These HOST entities are in the tenant export but not in cmdb_ci_linux_server. "
                "Typical for full-tenant compare when many hosts are outside the management region.",
                entity={
                    "type": "HOST",
                    "count": len(dt_only_other),
                    "sample": [r.get("dynatrace_display_name") for r in dt_only_other[:10]],
                },
            )
        )

    for row in matched:
        if row.get("servicenow_location") and scope.get("cmdb_location"):
            if row["servicenow_location"].lower() != scope["cmdb_location"].lower():
                findings.append(
                    make_finding(
                        scope_unit_id,
                        "servicenow_placement",
                        "warning",
                        "location_mismatch",
                        f"Matched host location differs from region hint: {row.get('servicenow_name')}",
                        f"CMDB location '{row.get('servicenow_location')}' != region cmdb_location '{scope.get('cmdb_location')}'. "
                        f"Dynatrace management zones: {row.get('dynatrace_management_zones', '') or '(none)'}.",
                        entity={
                            "type": "host_alignment",
                            "servicenow_name": row.get("servicenow_name"),
                            "dynatrace_entity_id": row.get("dynatrace_entity_id"),
                        },
                        recommendation=unit.get("dynatrace_correlation", {}).get("recommendations", {}).get("sn_location_mismatch", ""),
                    )
                )

    # Dynatrace partitioning diagnostics
    for diag in build_partitioning_diagnostics(unit, sn.get("hosts", []), dt_entities):
        status = diag.get("status", "")
        if status == "ok":
            continue
        severity = "action_required" if status in ("action_required", "missing_entity") else "warning"
        issue = diag.get("issue") or "partitioning_issue"
        findings.append(
            make_finding(
                scope_unit_id,
                "dynatrace_setup",
                severity,
                issue,
                f"Dynatrace partitioning: {diag.get('entity_name', issue)}",
                diag.get("detail", ""),
                entity={
                    "type": diag.get("entity_type", ""),
                    "name": diag.get("entity_name", ""),
                    "entity_id": diag.get("entity_id", ""),
                },
                recommendation=diag.get("recommendation", ""),
            )
        )

    # Informational: DT hosts outside project management zone (summary only)
    expected_mz = unit.get("dynatrace_correlation", {}).get("partitioning", {}).get("management_zone", "")
    if expected_mz:
        hosts_outside = [
            h for h in dt_hosts if expected_mz not in (h.get("management_zones") or "") and h.get("normalized_name") not in project_hosts
        ]
        if hosts_outside:
            findings.append(
                make_finding(
                    scope_unit_id,
                    "dynatrace_inventory",
                    "informational",
                    "hosts_outside_project_mz",
                    f"{len(hosts_outside)} Dynatrace host(s) outside project management zone",
                    f"Monitored in tenant but not in '{expected_mz}' and not listed as project hosts in dynatrace-correlation.yaml.",
                    entity={"type": "HOST", "count": len(hosts_outside), "sample": [h.get("display_name") for h in hosts_outside[:10]]},
                )
            )

    findings_by_category: dict[str, list[dict]] = defaultdict(list)
    for finding in findings:
        findings_by_category[finding["category"]].append(finding)

    severity_counts = defaultdict(int)
    for finding in findings:
        severity_counts[finding["severity"]] += 1

    return {
        "scope_unit_id": scope_unit_id,
        "region_id": scope.get("region_id", ""),
        "cmdb_location": scope.get("cmdb_location", ""),
        "generated_at": unit.get("generated_at", ""),
        "summary": {
            "findings_total": len(findings),
            "findings_by_severity": dict(severity_counts),
            "hosts_matched": len(matched),
            "hosts_servicenow_only": len(sn_only),
            "hosts_dynatrace_only": len(dt_only),
            "specified_application_services": len(intent_apps),
            "cmdb_application_services": len(cmdb_apps),
            "cmdb_extra_vs_spec": len(cmdb_by_name) - len(spec_names & set(cmdb_by_name)),
            "app_missing_cmdb": sum(1 for r in app_diff if r["status"] == "missing_in_cmdb"),
            "app_missing_tags": sum(1 for r in app_diff if r["status"] == "missing_tag_binding"),
            "canonical_tag_bindings": len(sn.get("tag_bindings_canonical", [])),
            "dt_hosts": len(dt_hosts),
            "dt_process_groups": len(flatten_dt_by_type(dt_entities, "PROCESS_GROUP")),
            "dt_kubernetes_clusters": len(flatten_dt_by_type(dt_entities, "KUBERNETES_CLUSTER")),
        },
        "navigation": {
            "categories": [
                {
                    "id": cat_id,
                    "title": CATEGORY_TITLES.get(cat_id, cat_id),
                    "finding_count": len(findings_by_category.get(cat_id, [])),
                }
                for cat_id in CATEGORY_TITLES
                if findings_by_category.get(cat_id)
            ],
        },
        "findings": sorted(findings, key=lambda f: (SEVERITY_ORDER.index(f["severity"]) if f["severity"] in SEVERITY_ORDER else 99, f["category"], f["title"])),
        "findings_by_category": {k: v for k, v in sorted(findings_by_category.items())},
        "inventory": {
            "host_alignment": {
                "description": "Linux servers (ServiceNow) vs HOST entities (Dynatrace), matched by short hostname.",
                "matched": matched,
                "servicenow_only": sn_only,
                "dynatrace_only": dt_only,
            },
            "application_services": {
                "description": "CSDM-specified application services correlated with CMDB and tag bindings.",
                "diff": app_diff,
            },
            "servicenow_hosts": sn_host_rows(sn.get("hosts", [])),
            "servicenow_tag_bindings": sn.get("tag_bindings", []),
            "servicenow_application_services_cmdb": [
                {
                    "name": field_value(r.get("name")),
                    "sys_id": field_value(r.get("sys_id")),
                    "operational_status": field_value(r.get("operational_status")),
                    "process_status": field_value(r.get("process_status")),
                    "service_status": field_value(r.get("service_status")),
                    "in_specification": field_value(r.get("name")) in spec_names,
                }
                for r in cmdb_apps
            ],
            "dynatrace_entities_summary": {
                "scope_mode": dt.get("scope_mode", ""),
                "hosts": dt_hosts,
                "process_groups_count": len(flatten_dt_by_type(dt_entities, "PROCESS_GROUP")),
                "services_count": len(flatten_dt_by_type(dt_entities, "SERVICE")),
                "kubernetes_clusters": flatten_dt_by_type(dt_entities, "KUBERNETES_CLUSTER"),
                "kubernetes_nodes_count": len(flatten_dt_by_type(dt_entities, "KUBERNETES_NODE")),
            },
        },
        "raw_export_file": f"{scope_unit_id}.json",
    }


def build_report(data: dict) -> dict:
    scope_units = []
    total_findings = defaultdict(int)
    total_severity = defaultdict(int)

    for scope_unit_id, unit in sorted(data.items()):
        analyzed = analyze_scope_unit(scope_unit_id, unit)
        scope_units.append(analyzed)
        total_findings["scope_units"] += 1
        for sev, count in analyzed["summary"]["findings_by_severity"].items():
            total_severity[sev] += count
        total_findings["findings"] += analyzed["summary"]["findings_total"]

    return {
        "report_version": REPORT_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": {
            "scope_units": len(scope_units),
            "findings_total": total_findings["findings"],
            "findings_by_severity": dict(total_severity),
        },
        "navigation": {
            "description": "Scroll findings[] for a flat annotated list, or open findings_by_category within each scope unit.",
            "severity_levels": list(SEVERITY_ORDER),
            "categories": [
                {"id": cat_id, "title": title}
                for cat_id, title in CATEGORY_TITLES.items()
            ],
        },
        "scope_units": scope_units,
    }


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <compare_data.json> [compare_report.json]", file=sys.stderr)
        return 2
    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) == 3 else input_path.parent / "compare_report.json"
    data = load_data(input_path)
    report = build_report(data)
    output_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote report: {output_path}")
    for unit in report["scope_units"]:
        sev = unit["summary"]["findings_by_severity"]
        print(
            f"  {unit['scope_unit_id']}: findings={unit['summary']['findings_total']} "
            f"(action_required={sev.get('action_required', 0)} warning={sev.get('warning', 0)} "
            f"informational={sev.get('informational', 0)}) "
            f"hosts matched={unit['summary']['hosts_matched']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
