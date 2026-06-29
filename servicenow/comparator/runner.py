"""Orchestrate compare collection, export, and report generation."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from servicenow.comparator.analysis.report import build_report
from servicenow.comparator.collectors.csdm import load_csdm_intent, load_dynatrace_correlation
from servicenow.comparator.collectors.dynatrace import DynatraceClient
from servicenow.comparator.collectors.servicenow import ServiceNowClient
from servicenow.comparator.config import CompareConfig, load_config
from servicenow.comparator.scope import discover_scope_units, load_inventory_groups, resolve_correlation_path

EXPORT_VERSION = "1.2"


def _scope_applied(config: CompareConfig, scope_unit: dict) -> dict:
    return {
        "servicenow": {
            "mode": "location_filtered" if config.filter_by_cmdb_location else "all",
            "location": scope_unit.get("cmdb_location", "") if config.filter_by_cmdb_location else "",
        },
        "dynatrace": {
            "mode": "management_zone_filtered" if config.filter_by_dynatrace_mz else "all",
            "management_zones": scope_unit.get("dynatrace_management_zones", [])
            if config.filter_by_dynatrace_mz
            else [],
        },
    }


def _instance_block(config: CompareConfig) -> dict:
    return {
        "servicenow_url": config.sn_url,
        "dynatrace_tenant_url": config.dt_tenant_url,
        "dynatrace_ui_url": config.dt_ui_url,
    }


def compare_scope_unit(
    config: CompareConfig,
    scope_unit: dict,
    inventory_groups: dict[str, list[str]],
) -> dict[str, Any]:
    generated_at = datetime.now().astimezone().isoformat(timespec="seconds")
    csdm = load_csdm_intent(scope_unit.get("csdm_spec_paths") or [], inventory_groups)
    correlation_path = resolve_correlation_path(config.compare_dir, scope_unit)
    dynatrace_correlation = load_dynatrace_correlation(
        correlation_path,
        scope_unit,
        config.dt_management_zone,
        config.dt_host_group,
        config.dt_environment,
        config.dt_owned_by,
    )

    sn_client = ServiceNowClient(config)
    hosts, hosts_scope_mode = sn_client.collect_hosts(scope_unit.get("cmdb_location", ""))
    intent_apps = csdm["intent"].get("application_services") or []
    app_services = [sn_client.lookup_intent_application_service(app) for app in intent_apps]
    cmdb_apps = sn_client.collect_application_services_cmdb()
    tag_data = sn_client.collect_tag_bindings()
    object_sources = sn_client.collect_object_sources("SGO-Dynatrace")
    k8s_clusters = sn_client.collect_kubernetes_clusters()
    k8s_nodes = sn_client.collect_kubernetes_nodes()

    dt_client = DynatraceClient(config)
    dynatrace = dt_client.collect_block(scope_unit.get("dynatrace_management_zones"))

    registry = {
        "scope_unit_id": scope_unit.get("scope_unit_id", ""),
        "region_id": scope_unit.get("region_id", ""),
        "cmdb_location": scope_unit.get("cmdb_location", ""),
        "cmdb_environment": scope_unit.get("cmdb_environment", ""),
        "csdm_spec_files": scope_unit.get("csdm_spec_files") or [],
    }

    return {
        "registry": registry,
        "generated_at": generated_at,
        "scope_applied": _scope_applied(config, scope_unit),
        "instance": _instance_block(config),
        **csdm,
        "dynatrace_correlation": dynatrace_correlation,
        "servicenow": {
            "hosts": hosts,
            "hosts_scope_mode": hosts_scope_mode,
            "application_services": app_services,
            "application_services_cmdb": cmdb_apps,
            "kubernetes_clusters": k8s_clusters,
            "kubernetes_nodes": k8s_nodes,
            "object_sources": object_sources,
            **tag_data,
        },
        "dynatrace": dynatrace,
        "diff": {"computed_by": "servicenow.comparator.analysis.report"},
    }


def build_export(comparisons: list[dict]) -> dict:
    if not comparisons:
        raise ValueError("No scope units were compared")
    last = comparisons[-1]
    intent_sources = [{"registry": unit["registry"], "intent": unit["intent"]} for unit in comparisons]
    return {
        "export_version": EXPORT_VERSION,
        "generated_at": last["generated_at"],
        "scope_applied": last["scope_applied"],
        "instance": last["instance"],
        "csdm_intent_sources": intent_sources,
        "servicenow": last["servicenow"],
        "dynatrace": last["dynatrace"],
        "dynatrace_correlation": last.get("dynatrace_correlation") or {},
    }


def run_compare(
    output_dir: Path | None = None,
    *,
    scope_unit_id: str | None = None,
    repo_root: Path | None = None,
    filter_by_cmdb_location: bool = False,
    filter_by_dynatrace_mz: bool = False,
) -> dict[str, Any]:
    config = load_config(
        repo_root,
        filter_by_cmdb_location=filter_by_cmdb_location,
        filter_by_dynatrace_mz=filter_by_dynatrace_mz,
    )
    inventory_groups = load_inventory_groups(config.inventory_path)
    scope_units = discover_scope_units(
        config.regions_dir,
        config.dt_management_zone,
        scope_unit_id=scope_unit_id,
    )
    if not scope_units:
        raise ValueError("No compare scope units discovered (check regions and scope_unit_id filter)")

    comparisons = [compare_scope_unit(config, unit, inventory_groups) for unit in scope_units]
    export = build_export(comparisons)
    report = build_report(export, config.compare_dir)

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = (output_dir or config.repo_root / "tmp/compare" / run_id).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    export_path = out_dir / config.export_filename
    report_path = out_dir / config.report_filename
    export_path.write_text(json.dumps(export, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return {
        "output_dir": out_dir,
        "export_path": export_path,
        "report_path": report_path,
        "export": export,
        "report": report,
        "scope_units": [u.get("scope_unit_id") for u in scope_units],
    }
