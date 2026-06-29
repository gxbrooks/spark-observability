"""Collect CSDM intent from region specification files."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def _validate_csdm_spec(spec: dict, spec_path: Path) -> None:
    basename = spec_path.name
    for item in spec.get("business_applications") or []:
        for field in ("business_owner", "it_application_owner", "operational_status", "active"):
            if field not in item or not str(item.get(field, "")).strip():
                raise ValueError(
                    f"Business application '{item.get('name', '')}' in {basename} "
                    f"must declare {field} explicitly."
                )

    for item in spec.get("business_services") or []:
        for field in ("owned_by", "business_criticality", "operational_status", "parent_business_application"):
            if field not in item or (field != "operational_status" and not str(item.get(field, "")).strip()):
                raise ValueError(
                    f"Business service '{item.get('name', '')}' in {basename} "
                    f"must declare {field} explicitly."
                )

    for item in spec.get("application_services") or []:
        if item.get("platform") == "saas":
            continue
        for field in (
            "owned_by",
            "business_criticality",
            "operational_status",
            "parent_business_service",
            "environment",
            "location",
        ):
            if field not in item or (field != "operational_status" and not str(item.get(field, "")).strip()):
                raise ValueError(
                    f"Application service '{item.get('name', '')}' in {basename} "
                    f"must declare {field} explicitly."
                )


def _expand_template(value: str, host: str) -> str:
    return value.replace("{host}", host).replace("{host_lower}", host.lower())


def _append_app_service(
    apps: list[dict],
    item: dict,
    spec_path: Path,
    *,
    expand: bool = False,
    host: str = "",
) -> None:
    name = _expand_template(item["name"], host) if expand else item["name"]
    identifier = _expand_template(item.get("identifier", ""), host) if expand else item.get("identifier", "")
    criticality_key = "busines_criticality" if "busines_criticality" in item else "business_criticality"
    entry = {
        "name": name,
        "identifier": identifier,
        "parent_business_service": item.get("parent_business_service", ""),
        "platform": item.get("platform", ""),
        "service_mapping": item.get("service_mapping", ""),
        "csdm_op": item.get("csdm_op", "insert"),
        "spec_file": spec_path.name,
        "environment": item.get("environment", ""),
        "location": item.get("location", ""),
        "owned_by": item.get("owned_by", ""),
        criticality_key: item.get(criticality_key, ""),
        "expand": expand,
    }
    if expand:
        entry["host"] = host
    apps.append(entry)


def load_csdm_intent(
    spec_paths: list[str | Path],
    inventory_groups: dict[str, list[str]],
) -> dict[str, list[dict]]:
    bas: list[dict] = []
    bss: list[dict] = []
    apps: list[dict] = []
    spec_files: list[str] = []

    for spec_path in spec_paths:
        path = Path(spec_path)
        with path.open(encoding="utf-8") as handle:
            spec = yaml.safe_load(handle) or {}
        _validate_csdm_spec(spec, path)
        spec_files.append(path.name)

        for item in spec.get("business_applications") or []:
            if item.get("csdm_op", "insert") == "delete":
                continue
            bas.append(
                {
                    "name": item["name"],
                    "identifier": item.get("identifier", ""),
                    "csdm_op": item.get("csdm_op", "insert"),
                    "spec_file": path.name,
                    "business_owner": item.get("business_owner", ""),
                    "it_application_owner": item.get("it_application_owner", ""),
                }
            )

        for item in spec.get("business_services") or []:
            if item.get("csdm_op", "insert") == "delete":
                continue
            bss.append(
                {
                    "name": item["name"],
                    "identifier": item.get("identifier", ""),
                    "parent_business_application": item.get("parent_business_application", ""),
                    "platform": "",
                    "csdm_op": item.get("csdm_op", "insert"),
                    "spec_file": path.name,
                    "owned_by": item.get("owned_by", ""),
                    "business_criticality": item.get("business_criticality", item.get("busines_criticality", "")),
                }
            )

        for item in spec.get("application_services") or []:
            if item.get("csdm_op", "insert") == "delete":
                continue
            if "expand" in item:
                expand_cfg = item["expand"] or {}
                group = expand_cfg.get("inventory_group", "")
                hosts = inventory_groups.get(group, [])
                for host in hosts:
                    _append_app_service(apps, item, path, expand=True, host=host)
            else:
                _append_app_service(apps, item, path, expand=False)

    intent = {
        "business_applications": bas,
        "business_services": bss,
        "application_services": apps,
        "spec_files": spec_files,
    }
    return {
        "specified": {**intent, "spec_paths": [str(p) for p in spec_paths]},
        "intent": intent,
    }


def load_dynatrace_correlation(
    correlation_path: Path,
    scope_unit: dict,
    dt_management_zone: str,
    dt_host_group: str,
    dt_environment: str,
    dt_owned_by: str,
) -> dict[str, Any]:
    with correlation_path.open(encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}

    partitioning = raw.get("partitioning") or {}
    mz_list = scope_unit.get("dynatrace_management_zones") or []
    expected_mz = (mz_list[0] if mz_list else "") or partitioning.get("management_zone") or dt_management_zone

    return {
        "spec_file": correlation_path.name,
        "partitioning": {
            "management_zone": expected_mz,
            "host_group": partitioning.get("host_group") or dt_host_group,
            "environment": partitioning.get("environment") or dt_environment,
            "owned_by": partitioning.get("owned_by") or dt_owned_by,
        },
        "kubernetes_clusters": scope_unit.get("kubernetes_clusters") or raw.get("kubernetes_clusters") or [],
        "auto_tags": raw.get("auto_tags") or [],
        "management_zone_expected_for": raw.get("management_zone_expected_for") or [],
        "reference_host_names": raw.get("reference_host_names") or raw.get("project_host_names") or [],
        "recommendations": raw.get("recommendations") or {},
    }
