"""Build consolidated compare findings organized by discoverability taxonomy."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from servicenow.comparator.analysis.compare_analysis import (
    build_app_service_diff,
    build_host_diff,
    build_partitioning_diagnostics,
    field_value,
    flatten_dt_hosts,
    iter_dt_entities,
    normalize_host,
    sn_location,
    tag_binding_counts,
)
from servicenow.comparator.analysis.entity_links import (
    LinkContext,
    dt_entity_url,
    enrich_row,
    sn_record_url,
)

REPORT_VERSION = "1.3"

CANONICAL_TAG_KEY = "servicenow.io/application-service-identifier"


def resolution_for(issue: str, app_row: dict | None = None) -> dict:
    templates: dict[str, dict] = {
        "missing_in_cmdb": {
            "summary": "Application service is specified in CSDM but absent from CMDB.",
            "docs": ["servicenow/docs/CSDM_Specifications.md"],
        },
        "missing_tag_binding": {
            "summary": "Tag-based application service has no canonical servicenow.io tag bindings in CMDB.",
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md"],
        },
        "alternate_tag_only": {
            "summary": "Only alternate tags are bound; canonical servicenow.io key is missing.",
            "docs": ["servicenow/docs/Tag_Based_Service_Mapping.md"],
        },
    }
    base = templates.get(issue, {"summary": "Review the observation.", "docs": []})
    if app_row and app_row.get("spec_file"):
        return {**base, "spec_file": app_row["spec_file"]}
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


CATEGORY_META = {
    "A_dual_discoverable": {
        "title": "Dual-discoverable objects (ServiceNow Discovery/KVA ↔ Dynatrace Smartscape)",
        "description": (
            "Objects natively discoverable on both platforms and correlatable by hostname, "
            "cluster name map, or sys_object_source (IRE/SGC)."
        ),
    },
    "B_dynatrace_injected": {
        "title": "Dynatrace-injected CMDB objects (SGC import, not SN-native discovery)",
        "description": (
            "Smartscape entities imported into CMDB by Service Graph Connector scheduled "
            "imports — process groups, Smartscape services, Dynatrace applications."
        ),
    },
    "C_specification_alignment": {
        "title": "CSDM specification, tag bindings, and Dynatrace partitioning",
        "description": (
            "Operational alignment checks that are not dual-discoverable entity presence: "
            "CSDM intent vs CMDB, tag-based Service Mapping bindings, management zones."
        ),
    },
}

SUBCATEGORY_META = {
    "A1_in_cmdb_not_smartscape": {
        "title": "In ServiceNow CMDB but not in Dynatrace Smartscape",
    },
    "A2_in_smartscape_not_cmdb": {
        "title": "In Dynatrace Smartscape but not in ServiceNow CMDB",
    },
    "A3_ire_mapped": {
        "title": "Mapped between CMDB and Smartscape (sys_object_source / IRE)",
    },
    "B1_in_smartscape_not_cmdb": {
        "title": "In Smartscape but not imported to CMDB (SGC gap)",
    },
    "B2_in_cmdb_not_smartscape": {
        "title": "In CMDB (SGO-Dynatrace) but not in Smartscape export (stale import)",
    },
    "B3_sgc_mapped": {
        "title": "SGC-imported CMDB row mapped to Smartscape entity",
    },
}


def load_taxonomy(comparator_dir: Path) -> dict:
    path = comparator_dir / "entity_taxonomy.yaml"
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def _subclass_entry(
    *,
    subclass: str,
    cmdb_class: str,
    smartscape_entity_type: str,
    severity: str,
    items: list[dict],
    summary: str = "",
) -> dict:
    return {
        "subclass": subclass,
        "cmdb_class": cmdb_class,
        "smartscape_entity_type": smartscape_entity_type,
        "severity": severity,
        "count": len(items),
        "summary": summary,
        "items": items,
    }


def _sn_item(name: str, sys_id: str, table: str, links: LinkContext, **extra: Any) -> dict:
    row = {"name": name, "sys_id": sys_id, "table": table, **extra}
    row["servicenow_url"] = sn_record_url(links.servicenow_url, table, sys_id)
    return row


def _dt_item(display_name: str, entity_id: str, links: LinkContext, **extra: Any) -> dict:
    row = {"display_name": display_name, "entity_id": entity_id, **extra}
    row["dynatrace_url"] = dt_entity_url(links.dynatrace_tenant_url, entity_id)
    return row


def _cluster_name_map(unit: dict) -> dict[str, str]:
    """Dynatrace cluster displayName -> ServiceNow cluster name."""
    mapping: dict[str, str] = {}
    for entry in unit.get("dynatrace_correlation", {}).get("kubernetes_clusters") or []:
        dt_name = entry.get("dynatrace_name", "")
        sn_name = entry.get("servicenow_name", "")
        if dt_name and sn_name:
            mapping[dt_name] = sn_name
    for entry in unit.get("registry", {}).get("kubernetes_clusters") or []:
        dt_name = entry.get("dynatrace_name", "")
        sn_name = entry.get("servicenow_name", "")
        if dt_name and sn_name:
            mapping[dt_name] = sn_name
    return mapping


def parse_object_source_entity_id(raw) -> str:
    value = field_value(raw)
    if "|||" in value:
        return value.split("|||")[-1].strip()
    return value


def _object_source_by_entity(sources: list[dict]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for row in sources or []:
        entity_id = parse_object_source_entity_id(row.get("id"))
        if entity_id:
            out[entity_id] = row
    return out


def _cmdb_hosts_by_norm(sn: dict) -> dict[str, dict]:
    return {
        normalize_host(h.get("name", "")): h
        for h in sn.get("hosts", [])
        if field_value(h.get("name"))
    }


def _cmdb_clusters_by_name(sn: dict) -> dict[str, dict]:
    return {
        field_value(c.get("name")): c
        for c in sn.get("kubernetes_clusters", [])
        if field_value(c.get("name"))
    }


def _cmdb_nodes_by_norm(sn: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for node in sn.get("kubernetes_nodes", []):
        norm = normalize_host(node.get("name") or node.get("host_name", ""))
        if norm:
            out[norm] = node
    return out


def _dt_entities_by_type(dt_entities: dict, entity_type: str) -> dict[str, dict]:
    by_key: dict[str, dict] = {}
    for ent in iter_dt_entities(dt_entities, entity_type):
        if entity_type == "HOST" or entity_type == "KUBERNETES_NODE":
            key = normalize_host(ent.get("displayName", ""))
        elif entity_type == "KUBERNETES_CLUSTER":
            key = ent.get("displayName", "")
        else:
            key = ent.get("entityId", "")
        if key and key not in by_key:
            by_key[key] = ent
    return by_key


def _build_dual_discoverable(
    unit: dict,
    sn: dict,
    dt_entities: dict,
    links: LinkContext,
    object_sources: dict[str, dict],
) -> dict:
    cluster_map = _cluster_name_map(unit)
    sn_hosts = _cmdb_hosts_by_norm(sn)
    dt_hosts = _dt_entities_by_type(dt_entities, "HOST")
    sn_clusters = _cmdb_clusters_by_name(sn)
    dt_clusters_raw = _dt_entities_by_type(dt_entities, "KUBERNETES_CLUSTER")
    dt_clusters = {cluster_map.get(k, k): v for k, v in dt_clusters_raw.items()}
    sn_nodes = _cmdb_nodes_by_norm(sn)
    dt_nodes = _dt_entities_by_type(dt_entities, "KUBERNETES_NODE")

    a1_subclasses: list[dict] = []
    a2_subclasses: list[dict] = []
    a3_subclasses: list[dict] = []

    # --- Hosts ---
    host_a1, host_a2, host_a3 = [], [], []
    for norm, sn_row in sorted(sn_hosts.items()):
        dt_row = dt_hosts.get(norm)
        sys_id = field_value(sn_row.get("sys_id"))
        if dt_row:
            entity_id = dt_row.get("entityId", "")
            src = object_sources.get(entity_id)
            if src:
                host_a3.append(
                    {
                        "subclass": "host_ire_mapped",
                        "cmdb_class": "cmdb_ci_linux_server",
                        "smartscape_entity_type": "HOST",
                        "servicenow": _sn_item(
                            field_value(sn_row.get("name")),
                            sys_id,
                            "cmdb_ci_linux_server",
                            links,
                            location=sn_location(sn_row),
                        ),
                        "dynatrace": _dt_item(
                            dt_row.get("displayName", ""),
                            entity_id,
                            links,
                            management_zones=format_management_zones(dt_row),
                        ),
                        "object_source_sys_id": field_value(src.get("sys_id")),
                    }
                )
        else:
            host_a1.append(
                _sn_item(
                    field_value(sn_row.get("name")),
                    sys_id,
                    "cmdb_ci_linux_server",
                    links,
                    normalized_name=norm,
                    location=sn_location(sn_row),
                    observation=f"Linux server in CMDB has no matching HOST entity in Smartscape.",
                )
            )

    for norm, dt_row in sorted(dt_hosts.items()):
        if norm not in sn_hosts:
            host_a2.append(
                _dt_item(
                    dt_row.get("displayName", ""),
                    dt_row.get("entityId", ""),
                    links,
                    normalized_name=norm,
                    management_zones=format_management_zones(dt_row),
                    observation="HOST entity in Smartscape has no matching cmdb_ci_linux_server.",
                )
            )

    if host_a1:
        a1_subclasses.append(
            _subclass_entry(
                subclass="host_in_cmdb_not_smartscape",
                cmdb_class="cmdb_ci_linux_server",
                smartscape_entity_type="HOST",
                severity="action_required",
                items=host_a1,
            )
        )
    if host_a2:
        a2_subclasses.append(
            _subclass_entry(
                subclass="host_in_smartscape_not_cmdb",
                cmdb_class="cmdb_ci_linux_server",
                smartscape_entity_type="HOST",
                severity="action_required",
                items=host_a2,
            )
        )
    if host_a3:
        a3_subclasses.append(
            _subclass_entry(
                subclass="host_ire_mapped",
                cmdb_class="cmdb_ci_linux_server",
                smartscape_entity_type="HOST",
                severity="ok",
                items=host_a3,
                summary="Hosts linked via sys_object_source (SGO-Dynatrace) to Dynatrace entityId.",
            )
        )

    # --- Kubernetes clusters ---
    cluster_a1, cluster_a2, cluster_a3 = [], [], []
    for sn_name, sn_row in sorted(sn_clusters.items()):
        dt_row = dt_clusters.get(sn_name)
        sys_id = field_value(sn_row.get("sys_id"))
        if dt_row:
            entity_id = dt_row.get("entityId", "")
            src = object_sources.get(entity_id)
            if src:
                cluster_a3.append(
                    {
                        "subclass": "kubernetes_cluster_ire_mapped",
                        "cmdb_class": "cmdb_ci_kubernetes_cluster",
                        "smartscape_entity_type": "KUBERNETES_CLUSTER",
                        "servicenow": _sn_item(sn_name, sys_id, "cmdb_ci_kubernetes_cluster", links),
                        "dynatrace": _dt_item(dt_row.get("displayName", ""), entity_id, links),
                        "object_source_sys_id": field_value(src.get("sys_id")),
                    }
                )
        else:
            cluster_a1.append(
                _sn_item(
                    sn_name,
                    sys_id,
                    "cmdb_ci_kubernetes_cluster",
                    links,
                    observation="K8s cluster CI in CMDB has no matching KUBERNETES_CLUSTER in Smartscape.",
                )
            )

    for sn_name, dt_row in sorted(dt_clusters.items()):
        if sn_name not in sn_clusters:
            cluster_a2.append(
                _dt_item(
                    dt_row.get("displayName", ""),
                    dt_row.get("entityId", ""),
                    links,
                    servicenow_expected_name=sn_name,
                    observation="KUBERNETES_CLUSTER in Smartscape has no matching cmdb_ci_kubernetes_cluster.",
                )
            )

    if cluster_a1:
        a1_subclasses.append(
            _subclass_entry(
                subclass="kubernetes_cluster_in_cmdb_not_smartscape",
                cmdb_class="cmdb_ci_kubernetes_cluster",
                smartscape_entity_type="KUBERNETES_CLUSTER",
                severity="action_required",
                items=cluster_a1,
            )
        )
    if cluster_a2:
        a2_subclasses.append(
            _subclass_entry(
                subclass="kubernetes_cluster_in_smartscape_not_cmdb",
                cmdb_class="cmdb_ci_kubernetes_cluster",
                smartscape_entity_type="KUBERNETES_CLUSTER",
                severity="action_required",
                items=cluster_a2,
            )
        )
    if cluster_a3:
        a3_subclasses.append(
            _subclass_entry(
                subclass="kubernetes_cluster_ire_mapped",
                cmdb_class="cmdb_ci_kubernetes_cluster",
                smartscape_entity_type="KUBERNETES_CLUSTER",
                severity="ok",
                items=cluster_a3,
            )
        )

    # --- Kubernetes nodes ---
    node_a1, node_a2 = [], []
    for norm, sn_row in sorted(sn_nodes.items()):
        if norm not in dt_nodes:
            node_a1.append(
                _sn_item(
                    field_value(sn_row.get("name")),
                    field_value(sn_row.get("sys_id")),
                    "cmdb_ci_kubernetes_node",
                    links,
                    normalized_name=norm,
                    observation="K8s node CI in CMDB has no matching KUBERNETES_NODE in Smartscape.",
                )
            )
    for norm, dt_row in sorted(dt_nodes.items()):
        if norm not in sn_nodes:
            node_a2.append(
                _dt_item(
                    dt_row.get("displayName", ""),
                    dt_row.get("entityId", ""),
                    links,
                    normalized_name=norm,
                    observation="KUBERNETES_NODE in Smartscape has no matching cmdb_ci_kubernetes_node.",
                )
            )

    if node_a1:
        a1_subclasses.append(
            _subclass_entry(
                subclass="kubernetes_node_in_cmdb_not_smartscape",
                cmdb_class="cmdb_ci_kubernetes_node",
                smartscape_entity_type="KUBERNETES_NODE",
                severity="warning",
                items=node_a1,
            )
        )
    if node_a2:
        a2_subclasses.append(
            _subclass_entry(
                subclass="kubernetes_node_in_smartscape_not_cmdb",
                cmdb_class="cmdb_ci_kubernetes_node",
                smartscape_entity_type="KUBERNETES_NODE",
                severity="warning",
                items=node_a2,
            )
        )

    return {
        **CATEGORY_META["A_dual_discoverable"],
        "A1_in_cmdb_not_smartscape": {**SUBCATEGORY_META["A1_in_cmdb_not_smartscape"], "subclasses": a1_subclasses},
        "A2_in_smartscape_not_cmdb": {**SUBCATEGORY_META["A2_in_smartscape_not_cmdb"], "subclasses": a2_subclasses},
        "A3_ire_mapped": {**SUBCATEGORY_META["A3_ire_mapped"], "subclasses": a3_subclasses},
    }


def format_management_zones(ent: dict) -> str:
    mzs = ent.get("managementZones") or ent.get("management_zones") or []
    if not mzs:
        return ""
    if isinstance(mzs, str):
        return mzs
    if isinstance(mzs[0], dict):
        return ", ".join(m.get("name", "") for m in mzs if m.get("name"))
    return ", ".join(str(m) for m in mzs if m)


def _build_dynatrace_injected(
    dt_entities: dict,
    object_sources: dict[str, dict],
    links: LinkContext,
    taxonomy: dict,
) -> dict:
    injected_defs = taxonomy.get("dynatrace_injected") or []
    dual_tables = {d["cmdb_class"] for d in taxonomy.get("dual_discoverable") or []}

    b1_subclasses: list[dict] = []
    b2_subclasses: list[dict] = []
    b3_subclasses: list[dict] = []

    for defn in injected_defs:
        entity_type = defn["smartscape_entity_type"]
        cmdb_class = defn["cmdb_class"]
        prefix = defn["subclass_prefix"]

        dt_by_id = {
            ent.get("entityId", ""): ent
            for ent in iter_dt_entities(dt_entities, entity_type)
            if ent.get("entityId")
        }

        # B1: in Smartscape, not in CMDB via object_source
        b1_items = []
        for entity_id, ent in sorted(dt_by_id.items()):
            src = object_sources.get(entity_id)
            if not src or field_value(src.get("target_table")) in dual_tables:
                if not src:
                    b1_items.append(
                        _dt_item(
                            ent.get("displayName", ""),
                            entity_id,
                            links,
                            observation=(
                                f"{entity_type} in Smartscape has no sys_object_source row "
                                f"(expected CMDB class {cmdb_class} after SGC import)."
                            ),
                        )
                    )
        if b1_items:
            b1_subclasses.append(
                _subclass_entry(
                    subclass=f"{prefix}_in_smartscape_not_cmdb",
                    cmdb_class=cmdb_class,
                    smartscape_entity_type=entity_type,
                    severity="warning",
                    items=b1_items[:50],
                    summary=f"Showing up to 50 of {len(b1_items)} {entity_type} entities without SGC mapping.",
                )
            )

        # B2/B3: object_source rows for this cmdb_class
        b2_items = []
        b3_items = []
        for entity_id, src in sorted(object_sources.items()):
            if field_value(src.get("target_table")) != cmdb_class:
                continue
            prefixes = defn.get("object_source_id_prefixes") or [entity_type.replace("_", "-")]
            if not any(entity_id.startswith(f"{p}-") or entity_id.startswith(p) for p in prefixes):
                continue
            target_sys_id = field_value(src.get("target_sys_id"))
            dt_ent = dt_by_id.get(entity_id)
            if dt_ent:
                b3_items.append(
                    {
                        "subclass": f"{prefix}_sgc_mapped",
                        "cmdb_class": cmdb_class,
                        "smartscape_entity_type": entity_type,
                        "servicenow": {
                            "sys_id": target_sys_id,
                            "table": cmdb_class,
                            "servicenow_url": sn_record_url(links.servicenow_url, cmdb_class, target_sys_id),
                        },
                        "dynatrace": _dt_item(dt_ent.get("displayName", ""), entity_id, links),
                        "object_source_sys_id": field_value(src.get("sys_id")),
                    }
                )
            else:
                b2_items.append(
                    {
                        "cmdb_class": cmdb_class,
                        "smartscape_entity_type": entity_type,
                        "entity_id": entity_id,
                        "target_sys_id": target_sys_id,
                        "servicenow_url": sn_record_url(links.servicenow_url, cmdb_class, target_sys_id),
                        "observation": (
                            f"sys_object_source references Dynatrace entityId {entity_id} but "
                            f"{entity_type} not found in Smartscape export (stale SGC import)."
                        ),
                    }
                )

        if b2_items:
            b2_subclasses.append(
                _subclass_entry(
                    subclass=f"{prefix}_in_cmdb_not_smartscape",
                    cmdb_class=cmdb_class,
                    smartscape_entity_type=entity_type,
                    severity="informational",
                    items=b2_items[:25],
                    summary=f"Showing up to 25 of {len(b2_items)} stale SGC mappings.",
                )
            )
        if b3_items:
            b3_subclasses.append(
                _subclass_entry(
                    subclass=f"{prefix}_sgc_mapped",
                    cmdb_class=cmdb_class,
                    smartscape_entity_type=entity_type,
                    severity="ok",
                    items=b3_items[:25],
                    summary=f"Showing up to 25 of {len(b3_items)} active SGC mappings.",
                )
            )

    return {
        **CATEGORY_META["B_dynatrace_injected"],
        "B1_in_smartscape_not_cmdb": {**SUBCATEGORY_META["B1_in_smartscape_not_cmdb"], "subclasses": b1_subclasses},
        "B2_in_cmdb_not_smartscape": {**SUBCATEGORY_META["B2_in_cmdb_not_smartscape"], "subclasses": b2_subclasses},
        "B3_sgc_mapped": {**SUBCATEGORY_META["B3_sgc_mapped"], "subclasses": b3_subclasses},
    }


def _build_specification_alignment(unit: dict, sn: dict, dt_entities: dict, links: LinkContext) -> dict:
    """CSDM intent, tag bindings, partitioning — legacy checks folded into category C."""
    intent_apps = specified_apps(unit)
    canonical_counts, alternate_counts = tag_binding_counts(sn.get("tag_bindings", []))
    app_diff = build_app_service_diff(
        intent_apps,
        sn.get("application_services", []),
        canonical_counts,
        alternate_counts,
    )
    app_sys_ids = sn_app_sys_ids(sn)
    spec_names = {a.get("name") for a in intent_apps if a.get("name")}
    cmdb_apps = sn.get("application_services_cmdb", [])
    cmdb_by_name = {field_value(a.get("name")): a for a in cmdb_apps if field_value(a.get("name"))}

    subclasses: list[dict] = []

    csdm_items = []
    for row in app_diff:
        if row["status"] == "missing_in_cmdb":
            csdm_items.append(
                {
                    "subclass": "application_service_missing_in_cmdb",
                    "cmdb_class": "cmdb_ci_service_discovered",
                    "smartscape_entity_type": None,
                    "name": row["name"],
                    "identifier": row["identifier"],
                    "spec_file": row.get("spec_file", ""),
                    "observation": "CSDM-specified application service not found in CMDB.",
                    "resolution": resolution_for("missing_in_cmdb", row),
                }
            )
        elif row["status"] == "missing_tag_binding":
            csdm_items.append(
                {
                    "subclass": "application_service_missing_tag_binding",
                    "cmdb_class": "cmdb_ci_service_discovered",
                    "smartscape_entity_type": None,
                    "name": row["name"],
                    "identifier": row["identifier"],
                    "sys_id": app_sys_ids.get(row["name"], ""),
                    "servicenow_url": sn_record_url(
                        links.servicenow_url,
                        "cmdb_ci_service_discovered",
                        app_sys_ids.get(row["name"], ""),
                    ),
                    "observation": f"No cmdb_key_value rows for {CANONICAL_TAG_KEY}.",
                    "resolution": resolution_for("missing_tag_binding", row),
                }
            )
        elif row["status"] == "ok_alternate_tag_only":
            csdm_items.append(
                {
                    "subclass": "application_service_alternate_tag_only",
                    "cmdb_class": "cmdb_ci_service_discovered",
                    "smartscape_entity_type": None,
                    "name": row["name"],
                    "identifier": row["identifier"],
                    "observation": "Alternate tags present; canonical servicenow.io key missing.",
                    "resolution": resolution_for("alternate_tag_only", row),
                }
            )

    if csdm_items:
        subclasses.append(
            _subclass_entry(
                subclass="csdm_application_service",
                cmdb_class="cmdb_ci_service_discovered",
                smartscape_entity_type=None,
                severity="action_required",
                items=csdm_items,
            )
        )

    extras = [
        field_value(name)
        for name in cmdb_by_name
        if name not in spec_names
    ]
    if extras:
        sample = extras[:25]
        subclasses.append(
            _subclass_entry(
                subclass="cmdb_extra_application_service",
                cmdb_class="cmdb_ci_service_discovered",
                smartscape_entity_type=None,
                severity="informational",
                items=[
                    {
                        "name": name,
                        "sys_id": field_value(cmdb_by_name[name].get("sys_id")),
                        "servicenow_url": sn_record_url(
                            links.servicenow_url,
                            "cmdb_ci_service_discovered",
                            field_value(cmdb_by_name[name].get("sys_id")),
                        ),
                    }
                    for name in sample
                ],
                summary=f"{len(extras)} CMDB application services not in region CSDM spec (showing {len(sample)}).",
            )
        )

    partition_items = []
    for diag in build_partitioning_diagnostics(unit, sn.get("hosts", []), dt_entities):
        if diag.get("status") == "ok":
            continue
        partition_items.append(
            {
                "subclass": diag.get("issue", "partitioning_issue"),
                "cmdb_class": None,
                "smartscape_entity_type": diag.get("entity_type"),
                "entity_name": diag.get("entity_name", ""),
                "entity_id": diag.get("entity_id", ""),
                "dynatrace_url": dt_entity_url(links.dynatrace_tenant_url, diag.get("entity_id", "")),
                "observation": diag.get("detail", ""),
                "recommendation": diag.get("recommendation", ""),
            }
        )
    if partition_items:
        subclasses.append(
            _subclass_entry(
                subclass="dynatrace_partitioning",
                cmdb_class=None,
                smartscape_entity_type="HOST",
                severity="action_required",
                items=partition_items,
            )
        )

    registry = unit.get("registry") or {}
    registry_location = registry.get("cmdb_location", "")
    matched, _, _ = build_host_diff(sn.get("hosts", []), flatten_dt_hosts(dt_entities))
    location_items = []
    for row in matched:
        if row.get("servicenow_location") and registry_location:
            if row["servicenow_location"].lower() != registry_location.lower():
                location_items.append(enrich_row(row, links.servicenow_url, links.dynatrace_tenant_url))
    if location_items:
        subclasses.append(
            _subclass_entry(
                subclass="host_location_mismatch",
                cmdb_class="cmdb_ci_linux_server",
                smartscape_entity_type="HOST",
                severity="warning",
                items=location_items,
            )
        )

    return {
        **CATEGORY_META["C_specification_alignment"],
        "subclasses": subclasses,
    }


def build_consolidated_findings(unit: dict, links: LinkContext, comparator_dir: Path) -> dict:
    taxonomy = load_taxonomy(comparator_dir)
    sn = unit.get("servicenow", {})
    dt_entities = unit.get("dynatrace", {}).get("entities", {})
    object_sources = _object_source_by_entity(sn.get("object_sources", []))

    return {
        "A_dual_discoverable": _build_dual_discoverable(unit, sn, dt_entities, links, object_sources),
        "B_dynatrace_injected": _build_dynatrace_injected(dt_entities, object_sources, links, taxonomy),
        "C_specification_alignment": _build_specification_alignment(unit, sn, dt_entities, links),
    }


def count_findings(findings: dict) -> dict[str, int]:
    counts = {"action_required": 0, "warning": 0, "informational": 0, "ok": 0, "total_items": 0}

    def walk_subclasses(subclasses: list[dict]) -> None:
        for sc in subclasses or []:
            sev = sc.get("severity", "informational")
            counts[sev] = counts.get(sev, 0) + 1
            counts["total_items"] += sc.get("count", 0)

    for cat_key in ("A_dual_discoverable", "B_dynatrace_injected"):
        cat = findings.get(cat_key) or {}
        for sub_key in ("A1_in_cmdb_not_smartscape", "A2_in_smartscape_not_cmdb", "A3_ire_mapped",
                        "B1_in_smartscape_not_cmdb", "B2_in_cmdb_not_smartscape", "B3_sgc_mapped"):
            sub = cat.get(sub_key) or {}
            walk_subclasses(sub.get("subclasses", []))

    c_cat = findings.get("C_specification_alignment") or {}
    walk_subclasses(c_cat.get("subclasses", []))
    return counts
