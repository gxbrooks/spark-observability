#!/usr/bin/env python3
"""
Collect AMDGPU utilization, clocks, temperature, power, and fan metrics directly
from the kernel's sysfs interfaces so Elastic Agent can ship them as custom
metrics.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Dict, Optional

SYSFS_ROOT = pathlib.Path("/sys/class/drm")
AMD_VENDOR_ID = "0x1002"


def read_text(path: pathlib.Path) -> Optional[str]:
    try:
        return path.read_text().strip()
    except FileNotFoundError:
        return None


def read_float(path: pathlib.Path, scale: float = 1.0) -> Optional[float]:
    raw = read_text(path)
    if raw is None:
        return None
    try:
        value = float(raw)
    except ValueError:
        return None
    return value / scale


def read_int(path: pathlib.Path, base: int = 10) -> Optional[int]:
    raw = read_text(path)
    if raw is None:
        return None
    try:
        return int(raw, base)
    except ValueError:
        return None


def read_hwmon_path(device: pathlib.Path) -> Optional[pathlib.Path]:
    hwmon_dir = device / "hwmon"
    if not hwmon_dir.exists():
        return None
    candidates = sorted(hwmon_dir.glob("hwmon*"))
    return candidates[0] if candidates else None


def parse_pci_slot(device: pathlib.Path) -> Optional[str]:
    uevent = read_text(device / "uevent")
    if not uevent:
        return None
    match = re.search(r"PCI_SLOT_NAME=(?P<slot>[\\w:.]+)", uevent)
    return match.group("slot") if match else None


def collect_card_metrics(card_device: pathlib.Path) -> Optional[Dict]:
    vendor = read_text(card_device / "vendor")
    if vendor is None or vendor.lower() != AMD_VENDOR_ID:
        return None

    card_name = card_device.parent.name  # e.g. card0
    device_id = read_text(card_device / "device")
    subsystem_device = read_text(card_device / "subsystem_device")
    subsystem_vendor = read_text(card_device / "subsystem_vendor")
    bus_address = parse_pci_slot(card_device)

    hwmon = read_hwmon_path(card_device)

    gpu_busy = read_float(card_device / "gpu_busy_percent")
    mem_busy = read_float(card_device / "mem_busy_percent")

    temp_edge = read_float(hwmon / "temp1_input", 1000.0) if hwmon else None
    power_watts = read_float(hwmon / "power1_average", 1_000_000.0) if hwmon else None
    fan_rpm = read_float(hwmon / "fan1_input") if hwmon else None

    gfx_clock = read_float(hwmon / "freq1_input", 1_000_000.0) if hwmon else None
    mem_clock = read_float(hwmon / "freq2_input", 1_000_000.0) if hwmon else None

    metrics: Dict[str, object] = {
        "event": {
            "kind": "metric",
            "category": ["hardware"],
            "type": "info",
        },
        "gpu": {
            "card": card_name,
            "vendor": {"id": vendor},
            "device": {
                "id": device_id,
                "subsystem_id": subsystem_device,
                "subsystem_vendor": subsystem_vendor,
            },
            "bus": {"address": bus_address},
        },
    }

    utilization = {}
    if gpu_busy is not None:
        utilization["core_percent"] = gpu_busy
    if mem_busy is not None:
        utilization["memory_percent"] = mem_busy
    if utilization:
        metrics["gpu"]["utilization"] = utilization

    clocks = {}
    if gfx_clock is not None:
        clocks["gfx_mhz"] = gfx_clock
    if mem_clock is not None:
        clocks["memory_mhz"] = mem_clock
    if clocks:
        metrics["gpu"]["clocks"] = clocks

    if temp_edge is not None:
        metrics["gpu"]["temperature_c"] = {"edge": temp_edge}

    if power_watts is not None:
        metrics["gpu"]["power"] = {"watts": power_watts}

    if fan_rpm is not None:
        metrics["gpu"]["fan"] = {"rpm": fan_rpm}

    return metrics


def main() -> None:
    # If a log file path is provided as argument, append to it; otherwise print to stdout
    if len(sys.argv) > 1:
        log_file = pathlib.Path(sys.argv[1])
        with log_file.open("a") as f:
            for card_device in sorted(SYSFS_ROOT.glob("card*/device")):
                metrics = collect_card_metrics(card_device)
                if metrics:
                    f.write(json.dumps(metrics, separators=(",", ":")) + "\n")
    else:
        # Default behavior: print to stdout (for testing)
        for card_device in sorted(SYSFS_ROOT.glob("card*/device")):
            metrics = collect_card_metrics(card_device)
            if metrics:
                print(json.dumps(metrics, separators=(",", ":")))


if __name__ == "__main__":
    main()

