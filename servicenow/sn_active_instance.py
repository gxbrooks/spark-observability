"""Which ServiceNow instance is brooks-lab feeding right now?

brooks-lab feeds one ServiceNow instance at a time, and nothing records which
one. The Ansible guard (automation/ansible/playbooks/servicenow/tasks/target.yml,
reported by playbooks/servicenow/diagnose.yml) derives it from every lab
component: the Lab3 MID Server, the KVA informer and the Dynatrace problem
notifications. Python tools on the workstation cannot reach the MID or the
cluster, so they use the Dynatrace signal: the only instance whose brooks-lab
event path is on. That is the brooks-lab problem workflow's trigger
(SN_INSTANCES[].dt_problem_workflow_name) for instances with dt_event_path
"workflow", and the classic problem notification
(SN_INSTANCES[].dt_problem_notification_name) for the others. That is the
instance Spark problems, and therefore change windows and comparisons, belong to.

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
    """No (or more than one) brooks-lab event path is on."""


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
    token = str(_unwrap(dt_vars.get("DT_AUTOMATION_TOKEN")) or "")
    if not api or not token:
        raise NoActiveInstance("DT_API_URL / DT_AUTOMATION_TOKEN missing from vars/contexts/dynatrace_ansible_vars.yml")
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
    active_workflows: set[str] = set()
    if any(inst.get("dt_event_path") == "workflow" for inst in regs):
        tenant = str(_unwrap(dt_vars.get("DT_TENANT_URL")) or "").rstrip("/")
        platform_token = str(_unwrap(dt_vars.get("DT_AUTOMATION_PLATFORM_TOKEN")) or "")
        if not tenant or not platform_token:
            raise NoActiveInstance(
                "DT_TENANT_URL / DT_AUTOMATION_PLATFORM_TOKEN missing from "
                "vars/contexts/dynatrace_ansible_vars.yml (needed for workflow instances)"
            )
        wreq = urllib.request.Request(
            f"{tenant}/platform/automation/v1/workflows?limit=500",
            headers={"Authorization": f"Bearer {platform_token}", "Accept": "application/json"},
        )
        with urllib.request.urlopen(wreq, timeout=timeout) as resp:
            workflows = json.load(resp).get("results") or []
        active_workflows = {
            w.get("title")
            for w in workflows
            if ((w.get("trigger") or {}).get("eventTrigger") or {}).get("isActive")
        }

    def is_on(inst: dict) -> bool:
        if inst.get("dt_event_path") == "workflow":
            return inst.get("dt_problem_workflow_name") in active_workflows
        return inst.get("dt_problem_notification_name") in enabled_names

    active = [inst for inst in regs if is_on(inst)]
    if len(active) == 1:
        return active[0]
    which = ", ".join(i["id"] for i in active) or "none"
    raise NoActiveInstance(
        f"brooks-lab Dynatrace event paths on for: {which}. Exactly one instance must be "
        "active; run automation/ansible playbooks/servicenow/diagnose.yml for the full check, "
        "or set SN_TARGET=<id>."
    )
