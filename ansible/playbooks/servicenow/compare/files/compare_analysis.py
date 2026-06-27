"""Shared analysis helpers for ServiceNow ↔ Dynatrace compare exports."""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

CANONICAL_TAG_KEY = "servicenow.io/application-service-identifier"
ALTERNATE_TAG_KEYS = frozenset({"app.kubernetes.io/name", "app"})


def field_value(value) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return str(value.get("display_value") or value.get("value") or "")
    return str(value)


def normalize_host(name) -> str:
    name = field_value(name)
    if not name:
        return ""
    return name.split(".")[0].lower()


def load_data(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def iter_dt_entities(entities: dict, entity_type: str) -> list[dict]:
    rows: list[dict] = []
    for key, items in (entities or {}).items():
        if key != entity_type and not key.endswith(f"::{entity_type}"):
            continue
        for ent in items or []:
            rows.append(ent)
    return rows


def format_management_zones(ent: dict) -> str:
    mzs = ent.get("managementZones") or ent.get("management_zones") or []
    if not mzs:
        return ""
    if isinstance(mzs, str):
        return mzs
    if isinstance(mzs[0], dict):
        return ", ".join(m.get("name", "") for m in mzs if m.get("name"))
    return ", ".join(str(m) for m in mzs if m)


def mz_list(ent: dict) -> list[str]:
    raw = format_management_zones(ent)
    return [part.strip() for part in raw.split(",") if part.strip()]


def flatten_dt_hosts(entities: dict) -> list[dict]:
    rows: list[dict] = []
    for ent in iter_dt_entities(entities, "HOST"):
        rows.append(
            {
                "management_zones": format_management_zones(ent),
                "display_name": ent.get("displayName", ""),
                "entity_id": ent.get("entityId", ""),
                "discovered_name": ent.get("discoveredName", ""),
                "normalized_name": normalize_host(ent.get("displayName", "")),
            }
        )
    return rows


def flatten_dt_by_type(entities: dict, suffix: str) -> list[dict]:
    rows: list[dict] = []
    for ent in iter_dt_entities(entities, suffix):
        rows.append(
            {
                "management_zones": format_management_zones(ent),
                "display_name": ent.get("displayName", ""),
                "entity_id": ent.get("entityId", ""),
            }
        )
    return rows


def sn_location(host: dict) -> str:
    loc = host.get("location") or {}
    if isinstance(loc, dict):
        return str(loc.get("display_value") or loc.get("value") or "")
    return str(loc) if loc else ""


def sn_host_rows(hosts: list[dict]) -> list[dict]:
    rows = []
    for host in hosts or []:
        rows.append(
            {
                "name": field_value(host.get("name")),
                "host_name": field_value(host.get("host_name")),
                "location": sn_location(host),
                "sys_id": field_value(host.get("sys_id")),
                "discovery_source": field_value(host.get("discovery_source")),
                "operational_status": field_value(host.get("operational_status")),
            }
        )
    return rows


def tag_binding_counts(tag_bindings: list[dict]) -> tuple[dict[str, int], dict[str, int]]:
    canonical: dict[str, int] = defaultdict(int)
    alternate: dict[str, int] = defaultdict(int)
    for row in tag_bindings or []:
        value = row.get("value") or row.get("val") or ""
        key = row.get("key") or ""
        if not value:
            continue
        if key == CANONICAL_TAG_KEY:
            canonical[str(value)] += 1
        elif key in ALTERNATE_TAG_KEYS:
            alternate[str(value)] += 1
    return dict(canonical), dict(alternate)


def build_host_diff(sn_hosts: list[dict], dt_hosts: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    sn_by_norm = {normalize_host(h.get("name", "")): h for h in sn_hosts or [] if field_value(h.get("name"))}
    dt_by_norm: dict[str, dict] = {}
    for row in dt_hosts:
        norm = row.get("normalized_name") or normalize_host(row.get("display_name", ""))
        if norm and norm not in dt_by_norm:
            dt_by_norm[norm] = row

    matched, sn_only, dt_only = [], [], []
    for norm, sn in sorted(sn_by_norm.items()):
        dt = dt_by_norm.get(norm)
        if dt:
            matched.append(
                {
                    "normalized_name": norm,
                    "servicenow_name": field_value(sn.get("name", "")),
                    "servicenow_sys_id": field_value(sn.get("sys_id")),
                    "servicenow_location": sn_location(sn),
                    "dynatrace_display_name": dt.get("display_name", ""),
                    "dynatrace_entity_id": dt.get("entity_id", ""),
                    "dynatrace_management_zones": dt.get("management_zones", ""),
                    "status": "matched",
                }
            )
        else:
            sn_only.append(
                {
                    "normalized_name": norm,
                    "servicenow_name": field_value(sn.get("name", "")),
                    "servicenow_sys_id": field_value(sn.get("sys_id")),
                    "servicenow_location": sn_location(sn),
                    "status": "servicenow_only",
                }
            )

    for norm, dt in sorted(dt_by_norm.items()):
        if norm not in sn_by_norm:
            dt_only.append(
                {
                    "normalized_name": norm,
                    "dynatrace_display_name": dt.get("display_name", ""),
                    "dynatrace_entity_id": dt.get("entity_id", ""),
                    "dynatrace_management_zones": dt.get("management_zones", ""),
                    "status": "dynatrace_only",
                }
            )

    return matched, sn_only, dt_only


def build_app_service_diff(
    intent_apps: list[dict],
    sn_apps: list[dict],
    canonical_counts: dict[str, int],
    alternate_counts: dict[str, int],
) -> list[dict]:
    sn_by_name = {a.get("intent_name"): a for a in sn_apps or []}
    rows = []
    for intent in intent_apps or []:
        name = intent.get("name", "")
        identifier = intent.get("identifier", "")
        sn = sn_by_name.get(name, {})
        canonical_count = canonical_counts.get(identifier, 0)
        alternate_count = alternate_counts.get(identifier, 0)
        if not sn.get("present_in_cmdb"):
            status = "missing_in_cmdb"
        elif intent.get("service_mapping") == "tags" and canonical_count > 0:
            status = "ok_canonical_tag"
        elif intent.get("service_mapping") == "tags" and alternate_count > 0:
            status = "ok_alternate_tag_only"
        elif intent.get("service_mapping") == "tags":
            status = "missing_tag_binding"
        elif sn.get("present_in_cmdb"):
            status = "present_in_cmdb"
        else:
            status = "unknown"
        rows.append(
            {
                "name": name,
                "identifier": identifier,
                "platform": intent.get("platform", ""),
                "service_mapping": intent.get("service_mapping", ""),
                "spec_file": intent.get("spec_file", ""),
                "present_in_cmdb": sn.get("present_in_cmdb", False),
                "process_status": sn.get("process_status", ""),
                "service_status": sn.get("service_status", ""),
                "canonical_tag_count": canonical_count,
                "alternate_tag_count": alternate_count,
                "status": status,
            }
        )
    return rows


def build_partitioning_diagnostics(
    unit: dict,
    sn_hosts: list[dict],
    dt_entities: dict,
) -> list[dict]:
    correlation = unit.get("dynatrace_correlation", {})
    partitioning = correlation.get("partitioning", {})
    expected_mz = partitioning.get("management_zone", "")
    reference_hosts = {
        normalize_host(h)
        for h in correlation.get("reference_host_names", correlation.get("project_host_names", []))
        if h
    }
    expected_clusters = {
        c.get("dynatrace_name", ""): c for c in correlation.get("kubernetes_clusters", []) if c.get("dynatrace_name")
    }
    recs = correlation.get("recommendations", {})
    rows: list[dict] = []

    def add_row(**kwargs) -> None:
        rows.append(kwargs)

    for cluster_name, cluster_meta in sorted(expected_clusters.items()):
        match = next(
            (ent for ent in iter_dt_entities(dt_entities, "KUBERNETES_CLUSTER") if ent.get("displayName") == cluster_name),
            None,
        )
        if not match:
            add_row(
                category="dynatrace_partitioning",
                status="missing_entity",
                entity_type="KUBERNETES_CLUSTER",
                entity_name=cluster_name,
                entity_id="",
                issue="cluster_not_in_tenant",
                detail=f"Expected cluster '{cluster_name}' (ServiceNow: {cluster_meta.get('servicenow_name', '')}) not found in Dynatrace export",
                recommendation=recs.get("missing_cluster_management_zone", ""),
            )
            continue
        mzs = mz_list(match)
        if expected_mz and expected_mz not in mzs:
            add_row(
                category="dynatrace_partitioning",
                status="action_required",
                entity_type="KUBERNETES_CLUSTER",
                entity_name=cluster_name,
                entity_id=match.get("entityId", ""),
                issue="missing_management_zone",
                detail=f"Cluster has management zones [{', '.join(mzs) or '(none)'}]; correlation spec expects '{expected_mz}'",
                recommendation=recs.get("missing_cluster_management_zone", recs.get("missing_management_zone", "")),
            )

    dt_hosts_by_norm = {normalize_host(ent.get("displayName", "")): ent for ent in iter_dt_entities(dt_entities, "HOST")}
    for norm in sorted(reference_hosts):
        ent = dt_hosts_by_norm.get(norm)
        if not ent:
            add_row(
                category="dynatrace_partitioning",
                status="missing_entity",
                entity_type="HOST",
                entity_name=norm,
                entity_id="",
                issue="reference_host_not_in_dynatrace",
                detail=f"Reference host '{norm}' from correlation spec not found in Dynatrace HOST export",
                recommendation="Verify OneAgent deployment and host group assignment",
            )
            continue
        mzs = mz_list(ent)
        if expected_mz and expected_mz not in mzs:
            add_row(
                category="dynatrace_partitioning",
                status="action_required",
                entity_type="HOST",
                entity_name=ent.get("displayName", norm),
                entity_id=ent.get("entityId", ""),
                issue="missing_management_zone",
                detail=f"Host has management zones [{', '.join(mzs) or '(none)'}]; correlation spec expects '{expected_mz}'",
                recommendation=recs.get("missing_management_zone", ""),
            )

    if expected_mz:
        hosts_in_mz = sum(1 for ent in iter_dt_entities(dt_entities, "HOST") if expected_mz in mz_list(ent))
        pg_in_mz = sum(1 for ent in iter_dt_entities(dt_entities, "PROCESS_GROUP") if expected_mz in mz_list(ent))
        pg_total = len(iter_dt_entities(dt_entities, "PROCESS_GROUP"))
        if hosts_in_mz > 0 and pg_in_mz == 0:
            add_row(
                category="dynatrace_partitioning",
                status="action_required",
                entity_type="PROCESS_GROUP",
                entity_name="(tenant summary)",
                entity_id="",
                issue="missing_process_group_management_zone",
                detail=f"0/{pg_total} process groups assigned to management zone '{expected_mz}' while {hosts_in_mz} HOST entities are in that zone",
                recommendation=recs.get("missing_process_group_management_zone", ""),
            )

    return rows
