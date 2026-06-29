"""Collect Dynatrace entities via Environment API v2."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

import requests

from servicenow.comparator.config import CompareConfig


class DynatraceClient:
    def __init__(self, config: CompareConfig) -> None:
        self.config = config
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Api-Token {config.dt_api_token}"})
        self._mz_name_to_id: dict[str, str] | None = None

    @property
    def api_base(self) -> str:
        return self.config.dt_api_url.rstrip("/")

    def management_zone_ids(self) -> dict[str, str]:
        if self._mz_name_to_id is None:
            url = f"{self.api_base}/config/v1/managementZones"
            response = self.session.get(url, timeout=60)
            response.raise_for_status()
            values = response.json().get("values") or []
            self._mz_name_to_id = {item["name"]: item["id"] for item in values if item.get("name")}
        return self._mz_name_to_id

    def _normalize_entity(self, ent: dict, entity_type: str) -> dict:
        mzs = ent.get("managementZones") or []
        if mzs and isinstance(mzs[0], dict):
            mz_names = [m.get("name", "") for m in mzs if m.get("name")]
        else:
            mz_names = list(mzs)
        return {
            "displayName": ent.get("displayName", ""),
            "entityId": ent.get("entityId", ""),
            "type": entity_type,
            "managementZones": mz_names,
        }

    def _fetch_pages(self, entity_selector: str, entity_type: str) -> list[dict]:
        rows: list[dict] = []
        next_page_key = ""
        for _ in range(self.config.dt_max_pages):
            params = f"entitySelector={quote(entity_selector, safe='')}&pageSize={self.config.dt_page_size}&fields=+managementZones"
            if next_page_key:
                params += f"&nextPageKey={quote(next_page_key, safe='')}"
            url = f"{self.api_base}/v2/entities?{params}"
            response = self.session.get(url, timeout=120)
            response.raise_for_status()
            payload = response.json()
            for ent in payload.get("entities") or []:
                rows.append(self._normalize_entity(ent, entity_type))
            next_page_key = payload.get("nextPageKey") or ""
            if not next_page_key:
                break
        return rows

    def collect_entities(self, management_zones: list[str] | None = None) -> dict[str, list[dict]]:
        entities: dict[str, list[dict]] = {}
        if self.config.filter_by_dynatrace_mz:
            mz_map = self.management_zone_ids()
            for mz_name in management_zones or []:
                mz_id = mz_map.get(mz_name, "")
                if not mz_id:
                    continue
                for entity_type in self.config.dt_entity_types:
                    selector = f"type({entity_type}),mzId({mz_id})"
                    key = f"{mz_name}::{entity_type}"
                    entities[key] = self._fetch_pages(selector, entity_type)
        else:
            for entity_type in self.config.dt_entity_types:
                selector = f"type({entity_type})"
                entities[entity_type] = self._fetch_pages(selector, entity_type)
        return entities

    def collect_block(self, management_zones: list[str] | None = None) -> dict[str, Any]:
        return {
            "scope_mode": "management_zone_filtered" if self.config.filter_by_dynatrace_mz else "full_tenant",
            "management_zones": management_zones or [],
            "entities": self.collect_entities(management_zones),
        }
