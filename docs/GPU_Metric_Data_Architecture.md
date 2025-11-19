# GPU Metric Data Architecture

## Overview

Lab1 and Lab2 each host an AMD Radeon RX 7600M XT GPU (RDNA3, 8 GB GDDR6, 128‑bit bus, 120 W TDP).<sup>[1](https://www.techpowerup.com/gpu-specs/radeon-rx-7600m-xt.c4013)</sup> These GPUs are responsible for Spark workloads that run directly on the Ubuntu hosts, so we added a lightweight telemetry path that surfaces the three most actionable signals for capacity planning:

1. **Core utilization** (`gpu_busy_percent`)
2. **VRAM utilization** (`mem_busy_percent`)
3. **Edge temperature** + supporting data (power, clocks, fan)

The amdgpu kernel driver already exposes these metrics in `/sys/class/drm/card*/device/` and `/hwmon`.<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html#gpu-power-thermal-controls-and-monitoring)</sup> We collect them locally, forward them through Elastic Agent, and visualize them on the Spark System Metrics dashboard without introducing new daemons or high-frequency polling.

## Component Stack

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| Sensors | Linux amdgpu sysfs (`gpu_busy_percent`, `mem_busy_percent`, `temp1_input`, `power1_average`, `freq1_input`, `freq2_input`, etc.) | Driver-maintained metrics updated by the SMU firmware |
| Collection | `elastic-agent/bin/gpu-metrics.py` | Reads AMD sysfs files, normalizes units (°C, MHz, Watts, %), emits newline-delimited JSON per GPU |
| Agent Input | Filebeat `exec` input (`id: gpu-metrics`) in `elastic-agent.linux.yml.j2` | Runs the script every 10 s, decodes JSON, drops raw message, tags events as `event.kind: metric`, adds host metadata |
| Transport | Elastic Agent (systemd) → Elasticsearch output | Uses same `default` output as other metrics, so no Logstash hop |
| Storage | Data stream `metrics-gpu-default` with `gpu-metrics` ILM | Backing indices roll daily, hot/warm/cold downsampling matches `system-metrics.ilm.json` footprint |
| Discovery | Kibana data view `gpu-metrics` + saved search `gpu-metrics-default` | Ships with Init-Index step 7.8 for immediate discoverability |
| Visualization | Grafana panel “GPU Metrics (Utilization & Temperature)” on `spark-system` dashboard | Plots GPU % vs VRAM % on left axis and edge temperature on right axis with shared time range |

## Data Flow

```
RDNA3 GPU (Lab1/Lab2)
        │
        │ sysfs (gpu_busy_percent, mem_busy_percent, hwmon temp/power)
        ▼
 /opt/Elastic/Agent/extensions/gpu-metrics.py
        │  (JSON events, one per card)
        ▼
Elastic Agent exec input (gpu-metrics)
        │  decode_json_fields + add_host_metadata
        ▼
Elasticsearch data stream metrics-gpu-default
        │  (ILM: gpu-metrics)
        ├─ Kibana data view / saved search
        └─ Grafana Spark System dashboard panel
```

## Metric Mapping

| JSON Field | Units | Source | Notes |
|------------|-------|--------|-------|
| `gpu.utilization.core_percent` | % | `/sys/class/drm/cardX/device/gpu_busy_percent` | Firmware-computed workload utilization.<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html#busy-percent)</sup> |
| `gpu.utilization.memory_percent` | % | `/sys/class/drm/cardX/device/mem_busy_percent` | VRAM load level (same API family as core utilization).<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html#busy-percent)</sup> |
| `gpu.temperature_c.edge` | °C | `/hwmon/temp1_input` | Converts millidegrees to °C, monitors on-die temperature.<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html#hwmon-interfaces)</sup> |
| `gpu.power.watts` | W | `/hwmon/power1_average` | Average SoC power draw.<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html#hwmon-interfaces)</sup> |
| `gpu.clocks.gfx_mhz` / `memory_mhz` | MHz | `/hwmon/freq1_input`, `/hwmon/freq2_input` | Provides context for boost behavior vs. nominal 1280–2469 MHz clocks.<sup>[1](https://www.techpowerup.com/gpu-specs/radeon-rx-7600m-xt.c4013)</sup> |
| `gpu.fan.rpm` | RPM | `/hwmon/fan1_input` | Optional on mobile boards; omitted when sensor absent. |

## Deployment Sequence

1. **Ansible Playbook (`ansible/playbooks/elastic-agent/install.yml`):**
   - Installs Elastic Agent (Linux block)
   - Creates `/opt/Elastic/Agent/extensions`
   - Copies `gpu-metrics.py` with execute bits (owner `elastic-agent`)
   - Renders `elastic-agent.linux.yml` template with `gpu_metrics_script_path`
   - Restarts systemd service

2. **Elasticsearch Initialization (`observability/elasticsearch/bin/init-index.sh` step 7.8):**
   - PUT `/_ilm/policy/gpu-metrics`
   - PUT `/_index_template/metrics-gpu-default`
   - Creates the `metrics-gpu-default` data stream if it does not exist
   - POSTs Kibana data view + saved search

3. **Grafana Update (`spark-system.json`):**
   - Inserts new panel (id 101) at row `y=32`
   - Moves Spark logs panel to `y=40` to keep layout tidy

## Operations

- **Retention:** Matches system metrics (1 day hot rollover, 12 day delete) to keep disk usage bounded while still allowing week-scale trend analysis.
- **Overhead:** The exec input runs every 10 s, reads a handful of files, and returns immediately. No background daemon stays resident.
- **Backpressure:** If a host lacks an AMD GPU, the script emits no events; the data stream simply stays empty.
- **Extendability:** Additional sensors (fan tach, per-engine temperatures, power caps) can be exposed by adding fields to the Python script—no playbook changes required unless new dependencies are introduced.

## References

1. TechPowerUp GPU database – Radeon RX 7600M XT specifications (clocks, memory, TDP).<sup>[1](https://www.techpowerup.com/gpu-specs/radeon-rx-7600m-xt.c4013)</sup>
2. Linux kernel documentation – AMDGPU power/thermal hwmon and busy-percent sysfs APIs.<sup>[2](https://www.kernel.org/doc/html/latest/gpu/amdgpu/thermal.html)</sup>

