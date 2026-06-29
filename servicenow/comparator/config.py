"""Load compare configuration from Ansible context vars and secrets."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


def _unwrap(value: Any) -> Any:
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def _load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Expected mapping in {path}")
    return data


@dataclass
class CompareConfig:
    repo_root: Path
    sn_url: str
    sn_user: str
    sn_password: str
    dt_api_url: str
    dt_api_token: str
    dt_tenant_url: str
    dt_management_zone: str
    dt_host_group: str
    dt_environment: str
    dt_owned_by: str
    regions_dir: Path
    compare_dir: Path
    inventory_path: Path
    filter_by_cmdb_location: bool = False
    filter_by_dynatrace_mz: bool = False
    dt_page_size: int = 500
    dt_max_pages: int = 20
    dt_entity_types: list[str] = field(
        default_factory=lambda: [
            "HOST",
            "PROCESS_GROUP",
            "SERVICE",
            "KUBERNETES_CLUSTER",
            "KUBERNETES_NODE",
        ]
    )
    identifier_tag_key: str = "servicenow.io/application-service-identifier"
    export_filename: str = "DT_SN_Model_Comparison.json"
    report_filename: str = "DT_SN_Model_Comparison_Report.json"

    @property
    def dt_ui_url(self) -> str:
        api = self.dt_api_url.rstrip("/")
        if api.lower().endswith("/api"):
            return api[:-4]
        return api.replace(".apps.dynatrace.com", ".live.dynatrace.com")

    @property
    def sn_api_headers(self) -> dict[str, str]:
        return {"Accept": "application/json", "Content-Type": "application/json"}


def load_config(
    repo_root: Path | None = None,
    *,
    servicenow_vars_path: Path | None = None,
    dynatrace_vars_path: Path | None = None,
    secrets_path: Path | None = None,
    regions_dir: Path | None = None,
    compare_dir: Path | None = None,
    inventory_path: Path | None = None,
    filter_by_cmdb_location: bool = False,
    filter_by_dynatrace_mz: bool = False,
) -> CompareConfig:
    root = (repo_root or Path(__file__).resolve().parents[2]).resolve()
    sn_vars = _load_yaml(servicenow_vars_path or root / "vars/contexts/servicenow_ansible_vars.yml")
    dt_vars = _load_yaml(dynatrace_vars_path or root / "vars/contexts/dynatrace_ansible_vars.yml")
    secrets = _load_yaml(secrets_path or root / "vars/secrets.yaml")
    sn_secrets = secrets.get("servicenow") or {}

    sn_user = _unwrap(sn_secrets.get("SN_USER") or secrets.get("SN_USER") or "")
    sn_password = _unwrap(sn_secrets.get("SN_PASSWORD") or secrets.get("SN_PASSWORD") or "")
    if not sn_user or not sn_password:
        raise ValueError("SN_USER and SN_PASSWORD must be set in vars/secrets.yaml (servicenow section)")

    dt_api_url = str(_unwrap(dt_vars.get("DT_API_URL") or "")).strip()
    dt_api_token = str(_unwrap(dt_vars.get("DT_API_TOKEN") or "")).strip()
    if not dt_api_url or not dt_api_token:
        raise ValueError("DT_API_URL and DT_API_TOKEN must be set in dynatrace_ansible_vars.yml")

    return CompareConfig(
        repo_root=root,
        sn_url=str(_unwrap(sn_vars.get("SN_URL") or secrets.get("SN_URL") or "")).strip(),
        sn_user=str(sn_user).strip(),
        sn_password=str(sn_password).strip(),
        dt_api_url=dt_api_url,
        dt_api_token=dt_api_token,
        dt_tenant_url=str(_unwrap(dt_vars.get("DT_TENANT_URL") or sn_vars.get("DT_TENANT_URL") or "")).strip(),
        dt_management_zone=str(_unwrap(dt_vars.get("DT_MANAGEMENT_ZONE") or "")).strip(),
        dt_host_group=str(_unwrap(dt_vars.get("DT_HOST_GROUP") or "")).strip(),
        dt_environment=str(_unwrap(dt_vars.get("DT_ENVIRONMENT") or "")).strip(),
        dt_owned_by=str(_unwrap(dt_vars.get("DT_OWNED_BY") or "")).strip(),
        regions_dir=(regions_dir or root / "servicenow/regions").resolve(),
        compare_dir=(compare_dir or root / "servicenow/comparator").resolve(),
        inventory_path=(inventory_path or root / "ansible/inventory.yml").resolve(),
        filter_by_cmdb_location=filter_by_cmdb_location,
        filter_by_dynatrace_mz=filter_by_dynatrace_mz,
    )
