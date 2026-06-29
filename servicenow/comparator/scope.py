"""Discover compare scope units and parse Ansible inventory for CSDM expansion."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def _collect_group_hosts(data: dict) -> tuple[dict[str, set[str]], dict[str, dict]]:
    """Parse inventory YAML into direct hosts per group and raw group nodes."""
    direct: dict[str, set[str]] = {}
    nodes: dict[str, dict] = {}

    def register_group(name: str, node: dict) -> None:
        nodes[name] = node
        direct.setdefault(name, set())
        for host_name in (node.get("hosts") or {}):
            direct[name].add(str(host_name))

    def walk(parent: dict) -> None:
        for child_name, child_node in (parent.get("children") or {}).items():
            if not isinstance(child_node, dict):
                continue
            register_group(child_name, child_node)
            walk(child_node)

    all_node = data.get("all") or data
    if isinstance(all_node, dict):
        register_group("all", all_node)
        walk(all_node)
    return direct, nodes


def _resolve_group_hosts(
    group_name: str,
    direct: dict[str, list[str]],
    nodes: dict[str, dict],
) -> list[str]:
    """All hosts in a group including nested child groups, preserving inventory order."""
    if group_name not in nodes:
        return []
    seen: set[str] = set()
    ordered: list[str] = []
    for host in direct.get(group_name, []):
        if host not in seen:
            seen.add(host)
            ordered.append(host)
    for child_name in (nodes[group_name].get("children") or {}):
        for host in _resolve_group_hosts(child_name, direct, nodes):
            if host not in seen:
                seen.add(host)
                ordered.append(host)
    return ordered


def load_inventory_groups(inventory_path: Path) -> dict[str, list[str]]:
    """Return Ansible group name -> host names (short names, inventory order)."""
    with inventory_path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    direct_sets, nodes = _collect_group_hosts(data)
    direct: dict[str, list[str]] = {name: [] for name in nodes}
    # Restore YAML host definition order for direct group members.
    def walk(parent: dict) -> None:
        for child_name, child_node in (parent.get("children") or {}).items():
            if not isinstance(child_node, dict):
                continue
            direct[child_name] = list((child_node.get("hosts") or {}).keys())
            walk(child_node)

    all_node = data.get("all") or data
    if isinstance(all_node, dict):
        direct["all"] = list((all_node.get("hosts") or {}).keys())
        walk(all_node)
    return {name: _resolve_group_hosts(name, direct, nodes) for name in nodes}


def discover_scope_units(
    regions_dir: Path,
    dt_management_zone_default: str = "",
    scope_unit_id: str | None = None,
) -> list[dict[str, Any]]:
    units: list[dict[str, Any]] = []
    for region_file in sorted(regions_dir.glob("*/region.yaml")):
        with region_file.open(encoding="utf-8") as handle:
            region = yaml.safe_load(handle) or {}
        if not isinstance(region, dict):
            continue

        unit = {
            "scope_unit_id": region.get("scope_unit_id", ""),
            "region_id": region.get("region_id", region_file.parent.name),
            "cmdb_location": region.get("cmdb_location", ""),
            "cmdb_environment": region.get("cmdb_environment", ""),
            "dynatrace_management_zones": [
                (region.get("dynatrace") or {}).get("management_zone_name")
                or dt_management_zone_default
            ],
            "dynatrace": region.get("dynatrace") or {},
            "kubernetes_clusters": region.get("kubernetes_clusters") or [],
            "csdm_spec_files": region.get("csdm_specs") or [],
            "csdm_spec_paths": [
                str(region_file.parent / spec) for spec in (region.get("csdm_specs") or [])
            ],
            "dynatrace_correlation_file": (region.get("compare") or {}).get(
                "dynatrace_correlation_file", "dynatrace-correlation.yaml"
            ),
        }
        units.append(unit)

    if scope_unit_id:
        units = [u for u in units if u.get("scope_unit_id") == scope_unit_id]
    return units


def resolve_correlation_path(compare_dir: Path, scope_unit: dict) -> Path:
    rel = scope_unit.get("dynatrace_correlation_file") or "dynatrace-correlation.yaml"
    path = Path(rel)
    if path.is_absolute():
        return path
    return compare_dir / rel
