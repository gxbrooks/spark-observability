"""Deep-link URLs for ServiceNow CMDB and Dynatrace entity records."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode


@dataclass
class LinkContext:
    servicenow_url: str = ""
    dynatrace_tenant_url: str = ""


SN_ENTITY_TABLES = {
    "cmdb_ci_linux_server": "cmdb_ci_linux_server",
    "application_service": "cmdb_ci_service_discovered",
    "cmdb_ci_service_discovered": "cmdb_ci_service_discovered",
    "cmdb_key_value": "cmdb_key_value",
    "sys_object_source": "sys_object_source",
    "host_alignment": "cmdb_ci_linux_server",
}

_DT_ENTITY_ID_RE = re.compile(
    r"^(?:HOST|PROCESS_GROUP|PROCESS_GROUP_INSTANCE|CONTAINER_GROUP_INSTANCE|"
    r"SERVICE|APPLICATION|POD|NODE|CLUSTER|KUBERNETES_CLUSTER|KUBERNETES_NODE)-[A-F0-9]+$",
    re.IGNORECASE,
)


def field_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return str(value.get("display_value") or value.get("value") or "")
    return str(value)


def parse_dynatrace_entity_id(raw: Any) -> str:
    """Extract a Smartscape entityId suitable for /ui/nav/ from SGC compound keys."""
    value = field_value(raw).strip()
    if not value:
        return ""
    if "|||" in value:
        for part in reversed(value.split("|||")):
            candidate = part.strip()
            if _DT_ENTITY_ID_RE.match(candidate):
                return candidate
        return value.split("|||")[-1].strip()
    return value


def normalize_dynatrace_ui_base(tenant_or_api_url: str) -> str:
    if not tenant_or_api_url:
        return ""
    base = tenant_or_api_url.rstrip("/")
    base = re.sub(r"/api/?$", "", base, flags=re.IGNORECASE)
    base = re.sub(r"\.apps\.dynatrace\.com$", ".live.dynatrace.com", base, flags=re.IGNORECASE)
    return base


def sn_record_url(instance_url: str, table: str, sys_id: str) -> str:
    if not instance_url or not table or not sys_id:
        return ""
    base = instance_url.rstrip("/")
    uri = f"{table}.do?sys_id={sys_id}"
    return f"{base}/nav_to.do?{urlencode({'uri': uri})}"


def sn_list_record_url(instance_url: str, table: str, sys_id: str) -> str:
    """List view filtered to one row — more reliable than form.do for cmdb_key_value."""
    if not instance_url or not table or not sys_id:
        return ""
    base = instance_url.rstrip("/")
    query = urlencode({"sysparm_query": f"sys_id={sys_id}"})
    return f"{base}/{table}_list.do?{query}"


def dt_entity_url(tenant_or_api_url: str, entity_id: str) -> str:
    parsed = parse_dynatrace_entity_id(entity_id)
    if not tenant_or_api_url or not parsed:
        return ""
    base = normalize_dynatrace_ui_base(tenant_or_api_url)
    if not base:
        return ""
    return f"{base}/ui/nav/{parsed}"


def resolve_dynatrace_link_base(instance: dict, meta: dict | None = None) -> str:
    meta = meta or {}
    inst = instance or {}
    for key in ("dynatrace_ui_url", "dynatrace_api_url", "dynatrace_tenant_url"):
        raw = str(inst.get(key) or meta.get(key) or "").strip()
        if raw:
            normalized = normalize_dynatrace_ui_base(raw)
            if normalized:
                return normalized
    return ""


def link_for_entity(entity: dict, sn_url: str, dt_url: str) -> str:
    if not entity:
        return ""
    table = entity.get("table") or SN_ENTITY_TABLES.get(entity.get("type", ""), "")
    sys_id = field_value(entity.get("sys_id") or entity.get("servicenow_sys_id"))
    if table in ("cmdb_key_value", "sys_object_source") and sys_id:
        return sn_record_url(sn_url, table, sys_id)
    entity_id = entity.get("dynatrace_entity_id") or entity.get("entity_id") or ""
    if entity_id:
        dt_link = dt_entity_url(dt_url, entity_id)
        if dt_link:
            return dt_link
    if sys_id and table:
        return sn_record_url(sn_url, table, sys_id)
    return ""


def enrich_tag_binding(row: dict, sn_url: str, dt_url: str) -> dict:
    """UI links for cmdb_key_value rows — not REST API hrefs on configuration_item."""
    out = dict(row)
    kv_sys_id = field_value(out.get("sys_id"))
    out["type"] = "cmdb_key_value"
    out["table"] = "cmdb_key_value"
    out["key_value_url"] = sn_record_url(sn_url, "cmdb_key_value", kv_sys_id)
    out["key_value_list_url"] = sn_list_record_url(sn_url, "cmdb_key_value", kv_sys_id)
    out["url"] = out["key_value_list_url"] or out["key_value_url"]

    ci_ref = out.get("configuration_item") or out.get("cmdb_ci") or {}
    ci_sys_id = field_value(ci_ref.get("value") if isinstance(ci_ref, dict) else ci_ref)
    ci_table = field_value(out.get("configuration_item_class")) or "cmdb_ci"
    if ci_sys_id:
        ci_url = sn_record_url(sn_url, ci_table, ci_sys_id)
        out["configuration_item_url"] = ci_url
        out["configuration_item"] = {
            "sys_id": ci_sys_id,
            "table": ci_table,
            "url": ci_url,
        }
    return out


def enrich_object_source(row: dict, sn_url: str, dt_url: str) -> dict:
    """UI links for sys_object_source rows and imported CMDB target CIs."""
    out = dict(row)
    raw_entity_id = field_value(out.get("id") or out.get("entity_id"))
    dt_entity_id = parse_dynatrace_entity_id(raw_entity_id)
    out["type"] = "sys_object_source"
    out["table"] = "sys_object_source"
    out["entity_id"] = raw_entity_id
    out["dynatrace_entity_id"] = dt_entity_id
    out["dynatrace_url"] = dt_entity_url(dt_url, dt_entity_id)

    os_sys_id = field_value(out.get("sys_id"))
    out["object_source_url"] = sn_record_url(sn_url, "sys_object_source", os_sys_id)

    target_table = field_value(out.get("target_table"))
    target_sys_id = field_value(out.get("target_sys_id"))
    if target_table and target_sys_id:
        out["servicenow_target_url"] = sn_record_url(sn_url, target_table, target_sys_id)
        out["url"] = out["servicenow_target_url"]
    elif out["object_source_url"]:
        out["url"] = out["object_source_url"]
    return out


def enrich_entity(entity: dict | None, sn_url: str, dt_url: str) -> dict | None:
    if not entity:
        return entity
    out = dict(entity)
    url = link_for_entity(out, sn_url, dt_url)
    if url:
        out["url"] = url

    items = out.get("items")
    if isinstance(items, list):
        out["items"] = [enrich_entity(item, sn_url, dt_url) or item for item in items]

    sample = out.get("sample")
    if isinstance(sample, list) and sample:
        if sample and isinstance(sample[0], dict):
            out["sample"] = [enrich_entity(s, sn_url, dt_url) or s for s in sample]
        elif out.get("sample_urls"):
            pass
        elif out.get("sample_entity_ids"):
            out["sample_urls"] = [dt_entity_url(dt_url, eid) for eid in out["sample_entity_ids"] if eid]
        elif out.get("sample_sys_ids"):
            table = SN_ENTITY_TABLES.get(out.get("type", ""), "cmdb_ci_linux_server")
            out["sample_urls"] = [sn_record_url(sn_url, table, sid) for sid in out["sample_sys_ids"] if sid]

    return out


def enrich_row(row: dict, sn_url: str, dt_url: str) -> dict:
    out = dict(row)
    sys_id = out.get("servicenow_sys_id") or out.get("sys_id") or ""
    if sys_id:
        table = SN_ENTITY_TABLES.get(out.get("type", ""), "cmdb_ci_linux_server")
        out["servicenow_url"] = sn_record_url(sn_url, table, sys_id)
    entity_id = out.get("dynatrace_entity_id") or out.get("entity_id") or ""
    if entity_id:
        out["dynatrace_url"] = dt_entity_url(dt_url, entity_id)
    return out
