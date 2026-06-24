#!/usr/bin/env python3
"""Build multi-sheet Excel workbook comparing ServiceNow and Dynatrace model exports."""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def normalize_host(name: str) -> str:
    if not name:
        return ""
    base = name.split(".")[0]
    return base.lower()


def load_data(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def flatten_dt_hosts(entities: dict) -> list[dict]:
    rows: list[dict] = []
    for key, items in (entities or {}).items():
        if not key.endswith("::HOST"):
            continue
        mz = key.split("::")[0]
        for ent in items or []:
            rows.append(
                {
                    "management_zone": mz,
                    "display_name": ent.get("displayName", ""),
                    "entity_id": ent.get("entityId", ""),
                    "discovered_name": ent.get("discoveredName", ""),
                    "normalized_name": normalize_host(ent.get("displayName", "")),
                }
            )
    return rows


def flatten_dt_by_type(entities: dict, suffix: str) -> list[dict]:
    rows: list[dict] = []
    for key, items in (entities or {}).items():
        if not key.endswith(f"::{suffix}"):
            continue
        mz = key.split("::")[0]
        for ent in items or []:
            rows.append(
                {
                    "management_zone": mz,
                    "display_name": ent.get("displayName", ""),
                    "entity_id": ent.get("entityId", ""),
                }
            )
    return rows


CANONICAL_TAG_KEY = "servicenow.io/application-service-identifier"
ALTERNATE_TAG_KEYS = frozenset({"app.kubernetes.io/name", "app"})


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
    sn_by_norm = {normalize_host(h.get("name", "")): h for h in sn_hosts or [] if h.get("name")}
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
                    "servicenow_name": sn.get("name", ""),
                    "servicenow_sys_id": sn.get("sys_id", ""),
                    "dynatrace_display_name": dt.get("display_name", ""),
                    "dynatrace_entity_id": dt.get("entity_id", ""),
                    "status": "matched",
                }
            )
        else:
            sn_only.append(
                {
                    "normalized_name": norm,
                    "servicenow_name": sn.get("name", ""),
                    "servicenow_sys_id": sn.get("sys_id", ""),
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


def cell_value(value) -> str | int | float | bool:
    if value is None:
        return ""
    if isinstance(value, (list, dict, tuple)):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, bool):
        return value
    return value


def sheet_from_rows(ws, headers: list[str], rows: list[dict]) -> None:
    ws.append(headers)
    for row in rows:
        ws.append([cell_value(row.get(h, "")) for h in headers])


def write_workbook(data: dict, output: Path) -> None:
    try:
        from openpyxl import Workbook
    except ImportError as exc:
        raise SystemExit("openpyxl is required: pip install openpyxl") from exc

    wb = Workbook()
    # Remove default sheet after we add content
    summary_ws = wb.active
    summary_ws.title = "Summary"

    all_scope_rows = []
    for scope_id, unit in sorted(data.items()):
        scope = unit.get("scope_unit", {})
        intent = unit.get("intent", {})
        sn = unit.get("servicenow", {})
        dt = unit.get("dynatrace", {})
        dt_hosts = flatten_dt_hosts(dt.get("entities", {}))
        matched, sn_only, dt_only = build_host_diff(sn.get("hosts", []), dt_hosts)
        canonical_counts, alternate_counts = tag_binding_counts(sn.get("tag_bindings", []))
        app_diff = build_app_service_diff(
            intent.get("application_services", []),
            sn.get("application_services", []),
            canonical_counts,
            alternate_counts,
        )

        all_scope_rows.append(
            {
                "scope_unit_id": scope_id,
                "cmdb_location": scope.get("cmdb_location", ""),
                "cmdb_environment": scope.get("cmdb_environment", ""),
                "dynatrace_management_zones": ", ".join(scope.get("dynatrace_management_zones", [])),
                "intent_app_services": len(intent.get("application_services", [])),
                "sn_hosts": len(sn.get("hosts", [])),
                "dt_hosts": len(dt_hosts),
                "hosts_matched": len(matched),
                "hosts_sn_only": len(sn_only),
                "hosts_dt_only": len(dt_only),
                "app_missing_cmdb": sum(1 for r in app_diff if r["status"] == "missing_in_cmdb"),
                "app_missing_tags": sum(1 for r in app_diff if r["status"] == "missing_tag_binding"),
                "app_alternate_tags_only": sum(1 for r in app_diff if r["status"] == "ok_alternate_tag_only"),
                "canonical_tag_bindings": len(sn.get("tag_bindings_canonical", [])),
                "generated_at": unit.get("generated_at", ""),
            }
        )

        safe = re.sub(r"[^\w\-]", "_", scope_id)[:28]

        ws_scope = wb.create_sheet(f"Scope_{safe}"[:31])
        scope_rows = []
        for key, val in sorted(scope.items()):
            scope_rows.append({"field": key, "value": val})
        sheet_from_rows(ws_scope, ["field", "value"], scope_rows)

        ws_intent = wb.create_sheet(f"Intent_{safe}"[:31])
        sheet_from_rows(
            ws_intent,
            ["name", "identifier", "platform", "service_mapping", "parent_business_service", "spec_file", "expand", "host"],
            intent.get("application_services", []),
        )

        ws_sn_hosts = wb.create_sheet(f"SN_Hosts_{safe}"[:31])
        sheet_from_rows(ws_sn_hosts, ["name", "host_name", "sys_id", "discovery_source", "operational_status"], sn.get("hosts", []))

        ws_dt_hosts = wb.create_sheet(f"DT_Hosts_{safe}"[:31])
        sheet_from_rows(ws_dt_hosts, ["management_zone", "display_name", "entity_id", "normalized_name"], dt_hosts)

        ws_host_diff = wb.create_sheet(f"HostDiff_{safe}"[:31])
        sheet_from_rows(
            ws_host_diff,
            ["status", "normalized_name", "servicenow_name", "servicenow_sys_id", "dynatrace_display_name", "dynatrace_entity_id"],
            matched + sn_only + dt_only,
        )

        ws_app = wb.create_sheet(f"AppDiff_{safe}"[:31])
        sheet_from_rows(
            ws_app,
            ["status", "name", "identifier", "platform", "service_mapping", "present_in_cmdb", "canonical_tag_count", "alternate_tag_count", "process_status", "service_status", "spec_file"],
            app_diff,
        )

        ws_tags = wb.create_sheet(f"SN_Tags_{safe}"[:31])
        sheet_from_rows(ws_tags, ["key", "value", "sys_id"], sn.get("tag_bindings", []))

        ws_pg = wb.create_sheet(f"DT_PG_{safe}"[:31])
        sheet_from_rows(
            ws_pg,
            ["management_zone", "display_name", "entity_id"],
            flatten_dt_by_type(dt.get("entities", {}), "PROCESS_GROUP"),
        )

        ws_k8s = wb.create_sheet(f"DT_K8s_{safe}"[:31])
        sheet_from_rows(
            ws_k8s,
            ["management_zone", "display_name", "entity_id"],
            flatten_dt_by_type(dt.get("entities", {}), "KUBERNETES_CLUSTER"),
        )

    sheet_from_rows(
        summary_ws,
        list(all_scope_rows[0].keys()) if all_scope_rows else ["scope_unit_id"],
        all_scope_rows,
    )
    summary_ws.insert_rows(1)
    summary_ws["A1"] = "Generated"
    summary_ws["B1"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    wb.save(output)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <compare_data.json> <output.xlsx>", file=sys.stderr)
        return 2
    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    data = load_data(input_path)
    write_workbook(data, output_path)
    print(f"Wrote workbook: {output_path}")
    for scope_id, unit in data.items():
        sn = unit.get("servicenow", {})
        dt = unit.get("dynatrace", {})
        dt_hosts = flatten_dt_hosts(dt.get("entities", {}))
        matched, sn_only, dt_only = build_host_diff(sn.get("hosts", []), dt_hosts)
        print(
            f"  {scope_id}: hosts matched={len(matched)} sn_only={len(sn_only)} dt_only={len(dt_only)} "
            f"intent_apps={len(unit.get('intent', {}).get('application_services', []))}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
