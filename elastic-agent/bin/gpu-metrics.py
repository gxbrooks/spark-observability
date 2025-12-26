#!/usr/bin/env python3
"""
Collect AMDGPU utilization, clocks, temperature, power, and fan metrics directly
from the kernel's sysfs interfaces so Elastic Agent can ship them as custom
metrics.
"""

from __future__ import annotations

import datetime
import gzip
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

    # Utilization metrics
    gpu_busy = read_float(card_device / "gpu_busy_percent")
    mem_busy = read_float(card_device / "mem_busy_percent")

    # Temperature metrics
    temp_edge = read_float(hwmon / "temp1_input", 1000.0) if hwmon else None
    temp_junction = read_float(hwmon / "temp2_input", 1000.0) if hwmon else None
    temp_memory = read_float(hwmon / "temp3_input", 1000.0) if hwmon else None
    temp_min = read_float(hwmon / "temp1_min", 1000.0) if hwmon else None
    temp_max = read_float(hwmon / "temp1_max", 1000.0) if hwmon else None
    temp_crit = read_float(hwmon / "temp1_crit", 1000.0) if hwmon else None

    # Power metrics
    power_avg = read_float(hwmon / "power1_average", 1_000_000.0) if hwmon else None
    power_current = read_float(hwmon / "power1_input", 1_000_000.0) if hwmon else None
    power_cap = read_float(hwmon / "power1_cap", 1_000_000.0) if hwmon else None
    power_cap_max = read_float(hwmon / "power1_cap_max", 1_000_000.0) if hwmon else None
    power_cap_min = read_float(hwmon / "power1_cap_min", 1_000_000.0) if hwmon else None

    # Clock metrics
    gfx_clock = read_float(hwmon / "freq1_input", 1_000_000.0) if hwmon else None
    mem_clock = read_float(hwmon / "freq2_input", 1_000_000.0) if hwmon else None
    gfx_clock_min = read_float(hwmon / "freq1_min", 1_000_000.0) if hwmon else None
    gfx_clock_max = read_float(hwmon / "freq1_max", 1_000_000.0) if hwmon else None
    mem_clock_min = read_float(hwmon / "freq2_min", 1_000_000.0) if hwmon else None
    mem_clock_max = read_float(hwmon / "freq2_max", 1_000_000.0) if hwmon else None

    # Fan metrics
    fan_rpm = read_float(hwmon / "fan1_input") if hwmon else None
    fan_rpm_min = read_float(hwmon / "fan1_min") if hwmon else None
    fan_rpm_max = read_float(hwmon / "fan1_max") if hwmon else None

    # Voltage metrics
    voltage_core = read_float(hwmon / "in0_input", 1000.0) if hwmon else None

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

    # Utilization
    utilization = {}
    if gpu_busy is not None:
        utilization["core_percent"] = gpu_busy
    if mem_busy is not None:
        utilization["memory_percent"] = mem_busy
    if gpu_busy is not None or mem_busy is not None:
        utilization["active"] = (gpu_busy is not None and gpu_busy > 0) or (mem_busy is not None and mem_busy > 0)
    if utilization:
        metrics["gpu"]["utilization"] = utilization

    # Temperature
    temperature = {}
    if temp_edge is not None:
        temperature["edge"] = temp_edge
    if temp_junction is not None:
        temperature["junction"] = temp_junction
    if temp_memory is not None:
        temperature["memory"] = temp_memory
    if temp_min is not None:
        temperature["min"] = temp_min
    if temp_max is not None:
        temperature["max"] = temp_max
    if temp_crit is not None:
        temperature["critical"] = temp_crit
    if temperature:
        metrics["gpu"]["temperature_c"] = temperature
    # AMD-specific temperature fields
    if temp_junction is not None:
        if "amd" not in metrics:
            metrics["amd"] = {}
        if "gpu" not in metrics["amd"]:
            metrics["amd"]["gpu"] = {}
        if "temperature_c" not in metrics["amd"]["gpu"]:
            metrics["amd"]["gpu"]["temperature_c"] = {}
        metrics["amd"]["gpu"]["temperature_c"]["hotspot"] = temp_junction
    if temp_memory is not None:
        if "amd" not in metrics:
            metrics["amd"] = {}
        if "gpu" not in metrics["amd"]:
            metrics["amd"]["gpu"] = {}
        if "temperature_c" not in metrics["amd"]["gpu"]:
            metrics["amd"]["gpu"]["temperature_c"] = {}
        metrics["amd"]["gpu"]["temperature_c"]["memory_junction"] = temp_memory

    # Power
    power = {}
    if power_avg is not None:
        power["watts"] = power_avg
    if power_current is not None:
        power["watts_current"] = power_current
    if power_cap is not None:
        power["cap_watts"] = power_cap
    if power_cap_max is not None:
        power["cap_max_watts"] = power_cap_max
    if power_cap_min is not None:
        power["cap_min_watts"] = power_cap_min
    if power:
        metrics["gpu"]["power"] = power

    # Clocks
    clocks = {}
    if gfx_clock is not None:
        clocks["core_mhz"] = gfx_clock
        clocks["gfx_mhz"] = gfx_clock  # Keep for backward compatibility
    if mem_clock is not None:
        clocks["memory_mhz"] = mem_clock
    if gfx_clock_min is not None:
        clocks["core_min_mhz"] = gfx_clock_min
    if gfx_clock_max is not None:
        clocks["core_max_mhz"] = gfx_clock_max
    if mem_clock_min is not None:
        clocks["memory_min_mhz"] = mem_clock_min
    if mem_clock_max is not None:
        clocks["memory_max_mhz"] = mem_clock_max
    if clocks:
        metrics["gpu"]["clocks"] = clocks

    # Fan
    fan = {}
    if fan_rpm is not None:
        fan["rpm"] = fan_rpm
    if fan_rpm_min is not None:
        fan["rpm_min"] = fan_rpm_min
    if fan_rpm_max is not None:
        fan["rpm_max"] = fan_rpm_max
    if fan:
        metrics["gpu"]["fan"] = fan

    # Voltage
    if voltage_core is not None:
        if "voltage" not in metrics["gpu"]:
            metrics["gpu"]["voltage"] = {}
        metrics["gpu"]["voltage"]["core_v"] = voltage_core

    return metrics


def rotate_log_file(log_file: pathlib.Path, max_size_mb: int = 100, keep_days: int = 7) -> None:
    """
    Rotate log file if it exceeds size limit or if it's a new day.
    
    Best practices for system metrics:
    - Rotate daily at midnight (time-based)
    - Rotate when file exceeds size limit (size-based)
    - Keep last N days of rotated files
    - Compress files older than 1 day to save space
    
    Args:
        log_file: Path to the log file
        max_size_mb: Maximum file size in MB before rotation (default: 100MB)
        keep_days: Number of days of rotated files to keep (default: 7)
    """
    if not log_file.exists():
        return
    
    # Check if file needs rotation (size-based)
    file_size_mb = log_file.stat().st_size / (1024 * 1024)
    if file_size_mb < max_size_mb:
        # Check if we need daily rotation (time-based)
        # Only check on first write of a new day
        # Since this script runs every 10s, we check file modification time
        file_mtime = datetime.datetime.fromtimestamp(log_file.stat().st_mtime)
        now = datetime.datetime.now()
        # If file was last modified yesterday or earlier, rotate for new day
        if file_mtime.date() < now.date():
            # File hasn't been written to today - rotate for new day
            pass
        else:
            # File is current, no rotation needed
            return
    
    # Perform rotation
    log_dir = log_file.parent
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    rotated_file = log_dir / f"{log_file.name}.{timestamp}"
    
    # Move current file to rotated location
    log_file.rename(rotated_file)
    
    # Compress rotated file if it's older than 1 day (save space)
    # We compress immediately since we're rotating, but only if size > 1MB
    if rotated_file.stat().st_size > 1024 * 1024:  # > 1MB
        compressed_file = rotated_file.with_suffix(rotated_file.suffix + ".gz")
        with rotated_file.open("rb") as f_in:
            with gzip.open(compressed_file, "wb") as f_out:
                f_out.writelines(f_in)
        rotated_file.unlink()
        rotated_file = compressed_file
    
    # Clean up old rotated files (keep only last keep_days)
    cutoff_date = datetime.datetime.now() - datetime.timedelta(days=keep_days)
    pattern = f"{log_file.name}.*"
    
    for old_file in log_dir.glob(pattern):
        if old_file == log_file:
            continue
        
        # Extract timestamp from filename
        # Format: gpu.ndjson.YYYYMMDD-HHMMSS[.gz]
        try:
            # Remove base name and extension
            suffix = old_file.name.replace(log_file.name + ".", "")
            if suffix.endswith(".gz"):
                suffix = suffix[:-3]
            file_timestamp = datetime.datetime.strptime(suffix, "%Y%m%d-%H%M%S")
            
            if file_timestamp < cutoff_date:
                old_file.unlink()
        except (ValueError, AttributeError):
            # If we can't parse timestamp, skip cleanup for this file
            pass


def main() -> None:
    # If a log file path is provided as argument, append to it; otherwise print to stdout
    if len(sys.argv) > 1:
        log_file = pathlib.Path(sys.argv[1])
        
        # Rotate log file if needed (before appending)
        rotate_log_file(log_file, max_size_mb=100, keep_days=7)
        
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

