"""Which ServiceNow instance is brooks-lab feeding right now?

brooks-lab feeds one ServiceNow instance at a time, and nothing records which
one. The Ansible guard (automation/ansible/playbooks/servicenow/tasks/target.yml,
reported by playbooks/servicenow/diagnose.yml) derives it from every lab
component: the Lab3 MID Server, the KVA informer and the Dynatrace problem
notifications. Python tools on the workstation cannot reach the MID or the
cluster, so they use the Dynatrace signal: the instance whose brooks-lab
problem notification (SN_INSTANCES[].dt_problem_notification_name) is the only
one enabled. That is the instance Spark problems, and therefore change windows
and comparisons, belong to.

Override with the environment variable SN_TARGET=<id>.

Stdlib + PyYAML only (both tools already depend on it).
"""

from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path
from typing import Any

import yaml


class NoActiveInstance(RuntimeError):
    """No (or more than one) brooks-lab notification is enabled."""


def _unwrap(value: Any) -> Any:
    # vars/contexts files may hold {value: ...} wrappers.
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def _load(path: Path) -> dict:
    if not path.is_file():
        return {}
    return yaml.safe_load(path.read_text()) or {}


def instances(root: Path) -> list[dict]:
    sn_vars = _load(root / "vars/contexts/servicenow_ansible_vars.yml")
    return list(_unwrap(sn_vars.get("SN_INSTANCES")) or [])


def active_instance(root: Path, timeout: float = 30.0) -> dict:
    """Return the active SN_INSTANCES entry (id, url, secrets_suffix, ...)."""
    regs = instances(root)
    if not regs:
        raise NoActiveInstance("SN_INSTANCES missing from vars/contexts/servicenow_ansible_vars.yml")
    forced = os.environ.get("SN_TARGET", "").strip()
    if forced:
        for inst in regs:
            if inst.get("id") == forced:
                return inst
        raise NoActiveInstance(f"SN_TARGET={forced} is not in SN_INSTANCES")

    dt_vars = _load(root / "vars/contexts/dynatrace_ansible_vars.yml")
    api = str(_unwrap(dt_vars.get("DT_API_URL")) or "").rstrip("/")
    token = str(_unwrap(dt_vars.get("DT_API_TOKEN")) or "")
    if not api or not token:
        raise NoActiveInstance("DT_API_URL / DT_API_TOKEN missing from vars/contexts/dynatrace_ansible_vars.yml")
    req = urllib.request.Request(
        f"{api}/v2/settings/objects?schemaIds=builtin:problem.notifications&fields=value&pageSize=100",
        headers={"Authorization": f"Api-Token {token}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        items = json.load(resp).get("items") or []
    enabled_names = {
        (it.get("value") or {}).get("displayName")
        for it in items
        if (it.get("value") or {}).get("enabled")
    }
    active = [inst for inst in regs if inst.get("dt_problem_notification_name") in enabled_names]
    if len(active) == 1:
        return active[0]
    which = ", ".join(i["id"] for i in active) or "none"
    raise NoActiveInstance(
        f"brooks-lab Dynatrace notifications enabled for: {which}. Exactly one instance must be "
        "active; run automation/ansible playbooks/servicenow/diagnose.yml for the full check, "
        "or set SN_TARGET=<id>."
    )
