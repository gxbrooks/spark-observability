#!/usr/bin/env python3
"""
AMD GPU sysfs sampler for Dynatrace Grail.

Reads RDNA3 (amdgpu) metrics from the kernel sysfs/hwmon interfaces and
POSTs them to the Dynatrace Metrics Ingest REST API
(https://<tenant>.live.dynatrace.com/api/v2/metrics/ingest).

This endpoint writes directly to Grail, making metrics available in DQL
`timeseries` queries and New Dashboards. Token scope required: metrics.ingest.

Credentials are read from /etc/dynatrace/gpu-sampler.env (EnvironmentFile):
    DT_API_URL=https://pdt20158.live.dynatrace.com/api
    DT_INGEST_TOKEN=dt0c01...

Metric namespace: system.gpu.*
  Follows OTel semantic conventions for hardware host metrics
  (analogous to system.cpu.*, system.memory.*). GPU metrics are host-level
  hardware sensors, not application or Spark-specific telemetry.

Dimensions on every line:
    gpu.card       - card0, card1, … (kernel DRM device)
    gpu.bus_address - PCI slot (e.g. 0000:03:00.0)
    host.name      - hostname (added automatically for entity correlation)

No third-party dependencies; stdlib only.
"""

from __future__ import annotations

import http.client
import os
import pathlib
import re
import socket
import sys
import urllib.error
import urllib.request
from typing import Optional

SYSFS_ROOT = pathlib.Path("/sys/class/drm")
AMD_VENDOR_ID = "0x1002"
CONNECT_TIMEOUT_S = 10

# Credentials loaded from EnvironmentFile
_DT_API_URL = os.environ.get("DT_API_URL", "").rstrip("/")
_DT_INGEST_TOKEN = os.environ.get("DT_INGEST_TOKEN", "")

# Fallback: local OneAgent ingest API (Classic Metrics only, no token needed)
_LOCAL_INGEST_URL = "http://127.0.0.1:14499/metrics/ingest"


def _read_text(path: pathlib.Path) -> Optional[str]:
    try:
        return path.read_text().strip()
    except (FileNotFoundError, PermissionError, OSError):
        return None


def _read_float(path: pathlib.Path, scale: float = 1.0) -> Optional[float]:
    raw = _read_text(path)
    if raw is None:
        return None
    try:
        return float(raw) / scale
    except ValueError:
        return None


def _hwmon(device: pathlib.Path) -> Optional[pathlib.Path]:
    d = device / "hwmon"
    if not d.exists():
        return None
    candidates = sorted(d.glob("hwmon*"))
    return candidates[0] if candidates else None


def _pci_slot(device: pathlib.Path) -> Optional[str]:
    raw = _read_text(device / "uevent")
    if not raw:
        return None
    m = re.search(r"PCI_SLOT_NAME=(?P<slot>[\w:.]+)", raw)
    return m.group("slot") if m else None


def _dim(key: str, value: str) -> str:
    return f'{key}="{value.replace(chr(34), chr(92) + chr(34))}"'


def collect(card_device: pathlib.Path) -> list[str]:
    """Return Dynatrace line-protocol strings for one GPU card."""
    vendor = _read_text(card_device / "vendor")
    if not vendor or vendor.lower() != AMD_VENDOR_ID:
        return []

    card_name = card_device.parent.name  # e.g. card1
    bus_address = _pci_slot(card_device) or "unknown"
    hostname = socket.gethostname()

    dims = ",".join([
        _dim("gpu.card", card_name),
        _dim("gpu.bus_address", bus_address),
        _dim("host.name", hostname),
    ])

    def line(key: str, value: float) -> str:
        return f"system.gpu.{key},{dims} {value:.6g}"

    lines: list[str] = []

    gpu_busy = _read_float(card_device / "gpu_busy_percent")
    if gpu_busy is not None:
        lines.append(line("utilization.core_percent", max(0.0, min(100.0, gpu_busy))))

    mem_busy = _read_float(card_device / "mem_busy_percent")
    if mem_busy is not None:
        lines.append(line("utilization.memory_percent", max(0.0, min(100.0, mem_busy))))

    hw = _hwmon(card_device)
    if hw:
        temp_edge = _read_float(hw / "temp1_input", 1000.0)
        if temp_edge is not None:
            lines.append(line("temperature_c.edge", temp_edge))

        temp_junction = _read_float(hw / "temp2_input", 1000.0)
        if temp_junction is not None:
            lines.append(line("temperature_c.junction", temp_junction))

        power_avg = _read_float(hw / "power1_average", 1_000_000.0)
        if power_avg is not None:
            lines.append(line("power.watts", power_avg))

        gfx_clock = _read_float(hw / "freq1_input", 1_000_000.0)
        if gfx_clock is not None:
            lines.append(line("clocks.core_mhz", gfx_clock))

        mem_clock = _read_float(hw / "freq2_input", 1_000_000.0)
        if mem_clock is not None:
            lines.append(line("clocks.memory_mhz", mem_clock))

        fan_rpm = _read_float(hw / "fan1_input")
        if fan_rpm is not None:
            lines.append(line("fan.rpm", fan_rpm))

        voltage = _read_float(hw / "in0_input", 1000.0)
        if voltage is not None:
            lines.append(line("voltage.core_v", voltage))

    return lines


def _post(url: str, payload: str, headers: dict) -> bool:
    """POST payload. Returns True on 200/202."""
    data = payload.encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=CONNECT_TIMEOUT_S) as resp:
            return resp.getcode() in (200, 202)
    except (urllib.error.URLError, http.client.RemoteDisconnected, OSError) as exc:
        print(f"gpu-metrics-dt: POST {url} failed: {exc}", file=sys.stderr)
        return False


def ingest(payload: str) -> None:
    """Send payload, preferring the REST Grail endpoint, falling back to port 14499."""
    if _DT_API_URL and _DT_INGEST_TOKEN:
        url = f"{_DT_API_URL}/v2/metrics/ingest"
        headers = {
            "Authorization": f"Api-Token {_DT_INGEST_TOKEN}",
            "Content-Type": "text/plain; charset=utf-8",
        }
        if _post(url, payload, headers):
            return
        print("gpu-metrics-dt: REST ingest failed, falling back to port 14499", file=sys.stderr)

    # Fallback: local OneAgent port (Classic Metrics only)
    headers_local = {"Content-Type": "text/plain; charset=utf-8"}
    if not _post(_LOCAL_INGEST_URL, payload, headers_local):
        print("gpu-metrics-dt: both ingest endpoints failed; printing to stdout", file=sys.stderr)
        print(payload)


def main() -> None:
    lines: list[str] = []
    for card_device in sorted(SYSFS_ROOT.glob("card*/device")):
        lines.extend(collect(card_device))

    if not lines:
        sys.exit(0)

    ingest("\n".join(lines))


if __name__ == "__main__":
    main()
