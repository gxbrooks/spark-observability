"""Collect ServiceNow CMDB data via Table API."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

import requests

from servicenow.comparator.config import CompareConfig


class ServiceNowClient:
    def __init__(self, config: CompareConfig) -> None:
        self.config = config
        self.session = requests.Session()
        self.session.auth = (config.sn_user, config.sn_password)
        self.session.headers.update(config.sn_api_headers)

    def _get(self, table: str, query: str) -> tuple[int, list[dict]]:
        url = f"{self.config.sn_url.rstrip('/')}/api/now/table/{table}?{query}"
        response = self.session.get(url, timeout=120)
        if response.status_code == 200:
            payload = response.json()
            return response.status_code, payload.get("result") or []
        return response.status_code, []

    def collect_hosts(self, cmdb_location: str = "") -> tuple[list[dict], str]:
        if self.config.filter_by_cmdb_location and cmdb_location:
            query = (
                f"sysparm_query=location.name={quote(cmdb_location, safe='')}"
                "&sysparm_fields=name,host_name,discovery_source,sys_id,operational_status,location"
                "&sysparm_display_value=all&sysparm_limit=500"
            )
            status, rows = self._get("cmdb_ci_linux_server", query)
            return rows, "location_filtered" if status == 200 else "location_filtered"

        query = (
            "sysparm_fields=name,host_name,discovery_source,sys_id,operational_status,location"
            "&sysparm_display_value=all&sysparm_limit=2000"
        )
        status, rows = self._get("cmdb_ci_linux_server", query)
        return rows, "full_cmdb" if status == 200 else "full_cmdb"

    def collect_application_services_cmdb(self) -> list[dict]:
        query = (
            "sysparm_fields=name,sys_id,operational_status,process_status,service_status"
            "&sysparm_limit=2000"
        )
        _, rows = self._get("cmdb_ci_service_discovered", query)
        return rows

    def lookup_intent_application_service(self, intent_app: dict) -> dict:
        name = intent_app.get("name", "")
        query = (
            f"sysparm_query=name={quote(name, safe='')}"
            "&sysparm_fields=sys_id,name,operational_status,process_status,service_status"
            "&sysparm_limit=1"
        )
        _, rows = self._get("cmdb_ci_service_discovered", query)
        present = len(rows) > 0
        row = rows[0] if present else {}
        return {
            "intent_name": name,
            "intent_identifier": intent_app.get("identifier", ""),
            "intent_platform": intent_app.get("platform", ""),
            "intent_service_mapping": intent_app.get("service_mapping", ""),
            "spec_file": intent_app.get("spec_file", ""),
            "present_in_cmdb": present,
            "sys_id": row.get("sys_id", "") if present else "",
            "process_status": row.get("process_status", "") if present else "",
            "service_status": row.get("service_status", "") if present else "",
        }

    def collect_tag_bindings(self) -> dict[str, Any]:
        canonical_key = self.config.identifier_tag_key
        canonical_query = (
            f"sysparm_query=key={quote(canonical_key, safe='')}"
            "&sysparm_fields=sys_id,key,value,cmdb_ci,configuration_item&sysparm_limit=500"
        )
        canonical_status, canonical = self._get("cmdb_key_value", canonical_query)

        alternate_query = (
            "sysparm_query=key=app.kubernetes.io/name^ORkey=app"
            "&sysparm_fields=sys_id,key,value,cmdb_ci,configuration_item&sysparm_limit=500"
        )
        alternate_status, alternate = self._get("cmdb_key_value", alternate_query)

        return {
            "tag_bindings": canonical + alternate,
            "tag_bindings_canonical": canonical,
            "tag_bindings_alternate": alternate,
            "tag_binding_query": {
                "canonical_key": canonical_key,
                "canonical_status": canonical_status,
                "alternate_status": alternate_status,
            },
        }

    def collect_object_sources(self, source_name: str = "SGO-Dynatrace") -> list[dict]:
        query = (
            f"sysparm_query=name={quote(source_name, safe='')}"
            "&sysparm_fields=sys_id,name,id,target_sys_id,target_table,source_table"
            "&sysparm_limit=5000"
        )
        _, rows = self._get("sys_object_source", query)
        return rows

    def collect_cmdb_by_class(self, table: str, discovery_source: str = "") -> list[dict]:
        fields = "sys_id,name,host_name,discovery_source,sys_class_name,operational_status,location"
        if discovery_source:
            query = (
                f"sysparm_query=discovery_sourceLIKE{quote(discovery_source, safe='')}"
                f"&sysparm_fields={fields}&sysparm_display_value=all&sysparm_limit=2000"
            )
        else:
            query = f"sysparm_fields={fields}&sysparm_display_value=all&sysparm_limit=2000"
        _, rows = self._get(table, query)
        return rows

    def collect_kubernetes_clusters(self) -> list[dict]:
        query = (
            "sysparm_fields=sys_id,name,discovery_source,location"
            "&sysparm_display_value=all&sysparm_limit=500"
        )
        _, rows = self._get("cmdb_ci_kubernetes_cluster", query)
        return rows

    def collect_kubernetes_nodes(self) -> list[dict]:
        query = (
            "sysparm_fields=sys_id,name,host_name,discovery_source,cluster"
            "&sysparm_display_value=all&sysparm_limit=2000"
        )
        _, rows = self._get("cmdb_ci_kubernetes_node", query)
        return rows
