#!/usr/bin/env python3
"""Open or close a ServiceNow change window for Chapter_*.py stress.

OOTB "CI in Change Window" marks change.cmdb_ci when the change is approved,
not on hold, in Scheduled or Implement (not New), and now is inside the
planned start/end window OR the actual work_start/work_end window. The lab
extension "Affected CIs in Change Window" applies the same gates to
task_ci.ci_item. Normal model blocks New → Implement from REST
(assignment-group approval). Standard walks New → Scheduled → Implement
(work_start set on Implement).

  create-sn-change-window.py --minutes 60 --log-dir DIR
  create-sn-change-window.py --close --log-dir DIR
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

CI_LOOKUPS = [
    ("cmdb_ci_linux_server", "lab1"),
    ("cmdb_ci_linux_server", "lab2"),
    ("cmdb_ci_linux_server", "lab3"),
    ("cmdb_ci_service_discovered", "Spark Client"),
    ("cmdb_ci_service_discovered", "Spark Master"),
    ("cmdb_ci_service_discovered", "Spark Worker"),
    ("cmdb_ci_service_discovered", "Spark History Server"),
]

# Standard change model — New → Scheduled → Implement without CAB.
STANDARD_MODEL = "e55d0bfec343101035ae3f52c1d3ae49"
CHANGE_MGMT_GROUP = "a715cd759f2002002920bde8132e7018"

STATE_SCHEDULED = "-2"
STATE_IMPLEMENT = "-1"
STATE_REVIEW = "0"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def load_sn_creds() -> tuple[str, str, str]:
    url = os.environ.get("SN_URL", "").strip()
    user = os.environ.get("SN_USER", "").strip()
    password = os.environ.get("SN_PASSWORD", "").strip()
    root = repo_root()
    if not url:
        ctx = root / "vars/contexts/servicenow_ansible_vars.yml"
        if ctx.is_file():
            m = re.search(r'^SN_URL:\s*"([^"]+)"', ctx.read_text(), re.M)
            if m:
                url = m.group(1).rstrip("/")
    secrets = root / "vars/secrets.yaml"
    if secrets.is_file():
        text = secrets.read_text()
        if not user:
            m = re.search(r'SN_USER:\s*"([^"]+)"', text)
            if m:
                user = m.group(1)
        if not password:
            m = re.search(r'SN_PASSWORD:\s*"([^"]+)"', text)
            if m:
                password = m.group(1)
    if not url:
        url = "https://optimizincdemo1.service-now.com"
    if not user or not password:
        raise SystemExit("SN_USER / SN_PASSWORD missing (env or vars/secrets.yaml)")
    return url.rstrip("/"), user, password


class SnClient:
    def __init__(self, base: str, user: str, password: str) -> None:
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.base = base
        self.headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": f"Basic {token}",
        }

    def _req(self, method: str, path: str, body: dict | None = None) -> dict:
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            self.base + path, data=data, headers=self.headers, method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            raise SystemExit(
                f"ServiceNow {method} {path} HTTP {exc.code}: {detail[:800]}"
            ) from exc

    def get(self, table: str, query: str, fields: str, limit: int = 20) -> list[dict]:
        qs = urllib.parse.urlencode(
            {
                "sysparm_query": query,
                "sysparm_fields": fields,
                "sysparm_limit": str(limit),
            }
        )
        return self._req("GET", f"/api/now/table/{table}?{qs}").get("result", [])

    def post(self, table: str, body: dict, allow_conflict: bool = False) -> dict:
        try:
            return self._req("POST", f"/api/now/table/{table}", body).get("result", {})
        except SystemExit as exc:
            if allow_conflict and "403" in str(exc):
                return {}
            raise

    def patch(self, table: str, sys_id: str, body: dict) -> dict:
        return self._req("PATCH", f"/api/now/table/{table}/{sys_id}", body).get(
            "result", {}
        )

    def chg_get(self, sys_id: str) -> dict:
        return self._req("GET", f"/api/sn_chg_rest/change/{sys_id}").get("result", {})

    def chg_patch(self, sys_id: str, body: dict) -> dict:
        return self._req("PATCH", f"/api/sn_chg_rest/change/{sys_id}", body).get(
            "result", {}
        )


def field_val(row: dict, name: str) -> str:
    v = row.get(name)
    if isinstance(v, dict):
        return str(v.get("value") or v.get("display_value") or "")
    return str(v or "")


def field_display(row: dict, name: str) -> str:
    v = row.get(name)
    if isinstance(v, dict):
        return str(v.get("display_value") or v.get("value") or "")
    return str(v or "")


def resolve_cis(sn: SnClient) -> list[dict]:
    found = []
    missing = []
    for table, name in CI_LOOKUPS:
        rows = sn.get(table, f"name={name}", "sys_id,name,sys_class_name", 5)
        if not rows:
            missing.append(f"{name} ({table})")
            continue
        found.append(rows[0])
    if missing:
        raise SystemExit(f"CMDB CIs not found: {', '.join(missing)}")
    return found


def fmt_sn(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def change_json_path(log_dir: str) -> Path:
    return Path(log_dir) / "change-window.json"


def write_payload(log_dir: str, payload: dict) -> None:
    if not log_dir:
        return
    path = change_json_path(log_dir)
    path.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {path}", file=sys.stderr)


def close_change(sn: SnClient, log_dir: str) -> int:
    path = change_json_path(log_dir) if log_dir else None
    if not path or not path.is_file():
        print("No change-window.json; nothing to close.", file=sys.stderr)
        return 0
    payload = json.loads(path.read_text())
    chg_id = payload.get("sys_id", "")
    number = payload.get("number", "")
    if not chg_id:
        print("change-window.json has no sys_id.", file=sys.stderr)
        return 0
    current = sn.chg_get(chg_id)
    state = field_val(current, "state").split(".")[0]
    if state in (STATE_REVIEW, "0", "3", "4") or field_display(current, "state").lower() in (
        "review",
        "closed",
        "canceled",
        "cancelled",
    ):
        print(
            f"Change {number} already {field_display(current, 'state')}; leave it.",
            file=sys.stderr,
        )
        payload["closed"] = True
        payload["close_state"] = field_display(current, "state")
        write_payload(log_dir, payload)
        return 0
    now = fmt_sn(datetime.now(timezone.utc))
    try:
        sn.chg_patch(chg_id, {"state": STATE_REVIEW, "work_end": now})
    except SystemExit as exc:
        print(f"WARNING: could not move {number} to Review: {exc}", file=sys.stderr)
        return 2
    after = sn.chg_get(chg_id)
    print(
        f"Change {number} → {field_display(after, 'state')} work_end={now}",
        file=sys.stderr,
    )
    payload["closed"] = True
    payload["close_state"] = field_display(after, "state")
    payload["work_end_utc"] = now
    write_payload(log_dir, payload)
    return 0


def wait_for_maint(sn: SnClient, cis: list[dict], wait_seconds: int) -> tuple[bool, list[str]]:
    needed = {c["sys_id"] for c in cis}
    deadline = time.time() + wait_seconds
    present: set[str] = set()
    while time.time() < deadline:
        try:
            rows = sn.get(
                "em_impact_maint_ci",
                "ci_idIN" + ",".join(needed),
                "ci_id,sys_id",
                50,
            )
        except SystemExit as exc:
            if "403" in str(exc) or "unauthorized" in str(exc).lower():
                print(
                    "em_impact_maint_ci is not readable; waiting "
                    f"{wait_seconds}s for Maintenance Calculator anyway.",
                    file=sys.stderr,
                )
                time.sleep(min(70, wait_seconds))
                return False, []
            raise
        present = set()
        for row in rows:
            ci = row.get("ci_id") or row.get("ci") or ""
            if isinstance(ci, dict):
                ci = ci.get("value", "")
            if ci:
                present.add(ci)
        if needed <= present:
            return True, []
        time.sleep(5)
    missing = [c["name"] for c in cis if c["sys_id"] not in present]
    return True, missing


def open_change(sn: SnClient, minutes: int, log_dir: str, wait_seconds: int) -> int:
    cis = resolve_cis(sn)
    primary = next((c for c in cis if c.get("name") == "lab1"), cis[0])
    start = datetime.now(timezone.utc)
    end = start + timedelta(minutes=minutes)
    body = {
        "short_description": f"Spark chapter stress test ({minutes} min)",
        "description": (
            "Automated Standard change window for Chapter_*.py stress. "
            "Affected CIs: " + ", ".join(c["name"] for c in cis)
        ),
        "type": "standard",
        "chg_model": STANDARD_MODEL,
        "assignment_group": CHANGE_MGMT_GROUP,
        "approval": "approved",
        "start_date": fmt_sn(start),
        "end_date": fmt_sn(end),
        "cmdb_ci": primary["sys_id"],
    }
    chg = sn.post("change_request", body)
    chg_id = chg.get("sys_id", "")
    number = chg.get("number", "")
    if not chg_id:
        raise SystemExit(f"change_request insert returned no sys_id: {chg}")

    for ci in cis:
        sn.post("task_ci", {"task": chg_id, "ci_item": ci["sys_id"]}, allow_conflict=True)

    sn.chg_patch(chg_id, {"state": STATE_SCHEDULED})
    sn.chg_patch(chg_id, {"state": STATE_IMPLEMENT})
    live = sn.chg_get(chg_id)
    state_name = field_display(live, "state")
    state_raw = field_val(live, "state").split(".")[0]
    if state_raw not in (STATE_IMPLEMENT, "-1") and state_name.lower() != "implement":
        raise SystemExit(
            f"Change {number} did not reach Implement (state={state_name}/{state_raw}). "
            "OOTB CI in Change Window will not fire."
        )
    print(
        f"Change {number} is {state_name}; "
        f"cmdb_ci={primary['name']}; work_start={field_display(live, 'work_start')}",
        file=sys.stderr,
    )

    readable, missing = wait_for_maint(sn, cis, wait_seconds)
    payload = {
        "number": number,
        "sys_id": chg_id,
        "type": "standard",
        "state": state_name,
        "start_utc": fmt_sn(start),
        "end_utc": fmt_sn(end),
        "minutes": minutes,
        "cmdb_ci": {"name": primary["name"], "sys_id": primary["sys_id"]},
        "cis": [{"name": c["name"], "sys_id": c["sys_id"]} for c in cis],
        "maint_missing": missing,
        "maint_table_readable": readable,
        "closed": False,
    }
    print(json.dumps(payload, indent=2))
    write_payload(log_dir, payload)
    if missing:
        print(
            "WARNING: CIs not yet in em_impact_maint_ci: " + ", ".join(missing),
            file=sys.stderr,
        )
        print(
            "Maintenance Calculator runs about once a minute; AMR maintenance=false "
            "will not hold until those rows appear.",
            file=sys.stderr,
        )
    elif readable:
        print(f"Change {number} is live; {len(cis)} CIs in maintenance.", file=sys.stderr)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Open or close a Spark lab change window")
    parser.add_argument("--minutes", type=int, default=0)
    parser.add_argument("--log-dir", default="")
    parser.add_argument("--wait-seconds", type=int, default=90)
    parser.add_argument(
        "--close",
        action="store_true",
        help="Move the change in --log-dir/change-window.json to Review",
    )
    args = parser.parse_args()
    url, user, password = load_sn_creds()
    sn = SnClient(url, user, password)
    if args.close:
        if not args.log_dir:
            raise SystemExit("--close requires --log-dir")
        return close_change(sn, args.log_dir)
    if args.minutes < 1:
        raise SystemExit("--minutes must be >= 1 (or pass --close)")
    return open_change(sn, args.minutes, args.log_dir, args.wait_seconds)


if __name__ == "__main__":
    sys.exit(main())
