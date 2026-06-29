"""Deep-link URLs for ServiceNow CMDB and Dynatrace entity records."""

from __future__ import annotations

import re
from dataclasses import dataclass
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
    "host_alignment": "cmdb_ci_linux_server",
}


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


def dt_entity_url(tenant_or_api_url: str, entity_id: str) -> str:
    if not tenant_or_api_url or not entity_id:
        return ""
    base = normalize_dynatrace_ui_base(tenant_or_api_url)
    if not base:
        return ""
    return f"{base}/ui/nav/{entity_id}"


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
    entity_id = entity.get("entity_id") or entity.get("dynatrace_entity_id") or ""
    if entity_id:
        return dt_entity_url(dt_url, entity_id)
    sys_id = entity.get("sys_id") or entity.get("servicenow_sys_id") or ""
    if sys_id:
        table = entity.get("table") or SN_ENTITY_TABLES.get(entity.get("type", ""), "")
        if table:
            return sn_record_url(sn_url, table, sys_id)
    return ""


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
