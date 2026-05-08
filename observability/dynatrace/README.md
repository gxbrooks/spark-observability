# Dynatrace observability module

This directory contains Dynatrace-specific assets for the platform split where
`elastic` and `dynatrace` are co-equal observability backends selected by the
`OBSERVABILITY_PLATFORM` / `observability_platform` flag in Ansible playbooks.

## Contents

- `docs/` architecture and operational guidance for Dynatrace.
- `dynakube/dynakube.yaml.j2` Dynatrace Operator CR (`cloudNativeFullStack`).
- `management-zone/` Settings 2.0 payload for partitioning.
- `automatic-tags/` Settings 2.0 payloads for partitioning tags (`spark-observability-tags.json.j2` renders three `builtin:tags.auto-tagging` objects).
- `otel-exporter/` snippet used for OTel dual-feed into Dynatrace.
- `sampler/gpu/` AMD GPU sysfs sampler — reads GPU metrics and POSTs to the Dynatrace REST ingest API (Grail).

## Partitioning model

The tenant is shared, so partitioning is done in-tenant:

- Host group: `spark-observability`
- Kubernetes cluster: `spark-observability-k8s`
- Management zone: `Spark Observability`
- Auto tags: `Project:spark-observability`, `Environment:lab`,
  `OwnedBy:gbrooks`

## Lifecycle

Playbooks live in `ansible/playbooks/observability/dynatrace/` and follow:
`install`, `deploy`, `start`, `stop`, `diagnose`, `test`, `uninstall`.

## Prerequisites (IAM and tokens)

Use three IAM/token objects for this module:

1. **Service user** for Dynatrace Platform APIs (Dashboards/Notebooks document API)
2. **Platform token** for the service user (Bearer auth, `/platform/*`)
3. **Environment API token** (`DT_API_TOKEN`, Api-Token auth, `/api/*` and `/v2/*`)

### Service user

- Name: `Spark Observability`
- Description: `Spark Observability dashboard/document automation`
- Recommended assignment:
  - Start with `Admin user` during bootstrap/validation.
  - After validation, reduce to least-privilege document permissions.

### Platform token (`DT_PLATFORM_TOKEN`)

- Purpose: new Dashboards app automation via Document API.
- Auth scheme: `Authorization: Bearer <token>`.
- API host: `https://<tenant>.apps.dynatrace.com/platform/...`
- Required permissions in token/IAM mapping:
  - Documents read
  - Documents write
  - Documents delete (recommended for idempotent lifecycle operations)

### Environment API token (`DT_API_TOKEN`)

- Purpose: Settings 2.0, entity/metric reads, and classic config APIs.
- Auth scheme: `Authorization: Api-Token <token>`.
- API hosts: `https://<tenant>.live.dynatrace.com/api/...` and `/v2/...`.
- Required scopes used by this module:
  - `entities.read`
  - `settings.read`
  - `settings.write`
  - `metrics.read`
  - `ReadConfig`
  - `WriteConfig`

### Secret locations

Store both tokens in `vars/secrets.yaml` under `dynatrace:`:

- `DT_PLATFORM_TOKEN`
- `DT_API_TOKEN`

## GPU metrics ingest (Step A — implemented)

AMD GPU sysfs metrics (Radeon RX 7600 on Lab1 and Lab2) are ingested into
Dynatrace **Grail** (and Classic Metrics) via the Dynatrace REST Metrics Ingest
API, using `DT_INGEST_TOKEN` (`metrics.ingest` scope). This makes the metrics
queryable via DQL `timeseries` in New Dashboards and Notebooks.

**Ingest path:**

```
amdgpu sysfs  (/sys/class/drm/card1/device/**)
  → sampler/gpu/gpu-metrics-dt.py  (systemd timer, 10 s)
  → POST https://<tenant>.live.dynatrace.com/api/v2/metrics/ingest  (DT_INGEST_TOKEN)
  → Dynatrace Grail + Classic Metrics
  → "Spark System Metrics" New Dashboard (DQL tiles) + Classic Dashboard (DATA_EXPLORER)
```

**Metric namespace: `system.gpu.*`**  
GPU metrics are host-level hardware sensors, not Spark-specific. Following OTel
semantic conventions (`system.cpu.*`, `system.memory.*`), the namespace is
`system.gpu.*`. The `dt.*` and `builtin:*` prefixes are Dynatrace-reserved and
cannot be used for custom metric keys.

Deployed by: `ansible/playbooks/observability/dynatrace/install.yml` (tag `gpu_sampler`)

**Credentials:** `DT_INGEST_TOKEN` (from `secrets.yaml`) is deployed to
`/etc/dynatrace/gpu-sampler.env` on each Kubernetes worker as an `EnvironmentFile`
for the `gpu-metrics-dt.service` unit.

## JVM GC metrics (OOB — no plumbing required)

OneAgent `cloudNativeFullStack` mode auto-instruments Spark JVM processes
(workers, master, history server, pyspark daemons). JVM GC metrics are already
available as Classic Metrics under `builtin:tech.jvm.memory.gc.*` and
`builtin:tech.jvm.memory.pool.*`. The "Spark System Metrics" dashboard includes
DATA_EXPLORER tiles for GC collection time, suspension time, heap usage, and
GC activation count. Filtering to Spark processes only can be done interactively
in the Data Explorer by filtering on `dt.entity.process_group_instance` name.

## Dashboard migration guidance

`docs/Spark_System_Metrics_Dashboard_Plan.md` defines the phased migration of
the Grafana "Spark System Metrics" dashboard to Dynatrace, including an OOB vs
custom split and telemetry plumbing requirements for GPU/GC/computed metrics.

Two dashboards are maintained:

**New Dashboard (DQL — primary):** `d879f582-1e11-486d-8f08-56d13a706eed`  
Managed by `tasks/apply_spark_system_dashboard_new.yml`, deployed by `deploy.yml`
(tag `new_dashboard`). Tiles use DQL `timeseries` against Grail:
- AMD GPU: core utilization, memory utilization, edge/junction temp, power, core/memory
  clocks, fan, voltage (`system.gpu.*`)
- Host: CPU usage, memory usage, network throughput (`dt.host.*`)

**Classic Dashboard (DATA_EXPLORER — GC and Spark master):** `df044b4c-c7fb-472d-a6a0-fed81dccf2fc`  
Managed by `tasks/apply_spark_system_dashboard.yml`. Uses Classic metric selector
syntax for `builtin:tech.jvm.spark.*` and `builtin:tech.jvm.memory.gc.*` keys
that are Classic-only and not available in Grail. Tiles cover:
- Active Spark applications / alive workers (`builtin:tech.jvm.spark.*`)
- Average host CPU / memory (`builtin:host.*`)
- AMD GPU utilization, temperature, power, clocks, fan (`system.gpu.*`)
- JVM GC collection time, suspension time, heap used, GC count, allocation rate

**Classic vs DQL:** `builtin:tech.jvm.*` keys are Classic-only (not in Grail).
To discover what metric keys are available in Grail, run:
`metrics | filter contains(metric.key, "spark") | dedup metric.key` in a Notebook.

## Git as source of truth (idempotent Settings)

Management zones and automatic tags are defined under `management-zone/` and
`automatic-tags/` in this repo. `deploy.yml` (tag `partitioning`) **lists**
existing `builtin:management-zones` / `builtin:tags.auto-tagging` objects,
then **creates** (POST) or **updates** (PUT by `objectId`) so re-runs do not
duplicate settings. Changes belong in Git first, then apply via Ansible.

`DT_API_TOKEN` needs **settings.read** and **settings.write**.

## DynaKube / Kubernetes monitoring

`dynakube/dynakube.yaml.j2` sets Operator feature annotations for **automatic
Kubernetes API monitoring** and the **cluster display name** (must match
`DT_K8S_CLUSTER_NAME`). Without these, the UI can show **Monitoring not
available** for the cluster even when nodes report to Dynatrace.
