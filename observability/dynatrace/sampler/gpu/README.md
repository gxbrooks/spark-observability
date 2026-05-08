# Dynatrace AMD GPU sampler

Reads AMD RDNA3 GPU metrics from the Linux kernel sysfs/hwmon interfaces and
POSTs them to the Dynatrace Metrics Ingest REST API
(`https://<tenant>.live.dynatrace.com/api/v2/metrics/ingest`).

## Why REST ingest, not port 14499

| Endpoint | Destination | DQL `timeseries` | Notes |
|---|---|---|---|
| `localhost:14499` (OneAgent local) | Classic Metrics store only | **No** | No auth, no Grail |
| `/api/v2/metrics/ingest` (REST) | Grail **and** Classic | **Yes** | Requires `metrics.ingest` token |

New Dashboards use DQL against Grail. The sampler therefore posts to the
REST endpoint using the `DT_INGEST_TOKEN` stored in `/etc/dynatrace/gpu-sampler.env`.

## Metric namespace: `system.gpu.*`

GPU metrics are **host-level hardware sensors**, not Spark-specific telemetry.
Following OTel semantic conventions (analogous to `system.cpu.*`, `system.memory.*`),
the namespace is `system.gpu.*`.

`dt.*` and `builtin:*` are Dynatrace-reserved prefixes and cannot be used for
custom metric keys.

### Metric keys and dimensions

All lines carry dimensions: `gpu.card`, `gpu.bus_address`, `host.name`.

| Metric key | Sysfs source | Unit |
|---|---|---|
| `system.gpu.utilization.core_percent` | `gpu_busy_percent` | % |
| `system.gpu.utilization.memory_percent` | `mem_busy_percent` | % |
| `system.gpu.temperature_c.edge` | `hwmon/temp1_input ÷ 1000` | °C |
| `system.gpu.temperature_c.junction` | `hwmon/temp2_input ÷ 1000` | °C |
| `system.gpu.power.watts` | `hwmon/power1_average ÷ 1e6` | W |
| `system.gpu.clocks.core_mhz` | `hwmon/freq1_input ÷ 1e6` | MHz |
| `system.gpu.clocks.memory_mhz` | `hwmon/freq2_input ÷ 1e6` | MHz |
| `system.gpu.fan.rpm` | `hwmon/fan1_input` | RPM |
| `system.gpu.voltage.core_v` | `hwmon/in0_input ÷ 1000` | V |

## Files

| File | Description |
|---|---|
| `gpu-metrics-dt.py` | Sampler script (stdlib only; no pip deps) |
| `gpu-metrics-dt.service` | systemd oneshot service unit (loads `/etc/dynatrace/gpu-sampler.env`) |
| `gpu-metrics-dt.timer` | systemd timer (fires every 10 s) |

## Deployment

Deployed to `kubernetes_workers` (Lab1, Lab2) by:

```bash
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/dynatrace/install.yml \
  --tags gpu_sampler
```

The Ansible task also deploys `/etc/dynatrace/gpu-sampler.env` with:

```
DT_API_URL=https://pdt20158.live.dynatrace.com/api
DT_INGEST_TOKEN=<DT_INGEST_TOKEN from secrets.yaml>
```

The script installs at:
`/opt/dynatrace/oneagent/agent/tools/extensions/gpu-metrics-dt.py`

## Validation

```bash
# Journal check on a worker node
journalctl -u gpu-metrics-dt.service --since '5 min ago'

# Grail metrics catalog
curl "https://pdt20158.live.dynatrace.com/api/v2/metrics?metricSelector=system.gpu.*" \
  -H "Authorization: Api-Token $DT_API_TOKEN"

# Live data (last 30 min, 5-min resolution)
curl "https://pdt20158.live.dynatrace.com/api/v2/metrics/query?metricSelector=system.gpu.utilization.core_percent:splitBy(gpu.card,host.name):avg&resolution=5m&from=now-30m" \
  -H "Authorization: Api-Token $DT_API_TOKEN"
```

## DQL queries (New Dashboard)

```dql
// GPU core utilization by host and card
timeseries core=avg(system.gpu.utilization.core_percent), by:{host.name, gpu.card}
```
