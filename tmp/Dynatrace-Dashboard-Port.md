# Dynatrace Dashboard Port — Status and Architecture

**Last updated:** 2026-05-08  
**Tenant:** `pdt20158` (`https://pdt20158.apps.dynatrace.com`)  
**Pause point:** New Dashboard ("Spark System Metrics") is live with 12 DQL tiles rendering without errors. JVM GC tiles are present in the dashboard but depend on Grail metric availability (see §4).

---

## 1. Scope: What we are porting

The source is the Grafana **"Spark System Metrics Aggregated"** dashboard (`spark-system-metrics-aggregated.json`), which provides a global operator view of the Spark environment:

| # | Grafana Panel | Type |
|---|---|---|
| 1 | Active Application Jobs | timeseries |
| 2 | Spark Log Volume | timeseries |
| 3 | Average System Compute Use | timeseries |
| 4 | Average System Memory Pressure | timeseries |
| 5 | Total Network Throughput | timeseries |
| 6 | Total Disk Throughput | timeseries |
| 7 | Total System Load Trend | timeseries |
| 8 | Total Page Fault Rate | timeseries |
| 9 | Total GC Pause Time | timeseries |
| 10 | Total GC Heap Reclaimed | timeseries |
| 11 | GPU Compute Envelope | timeseries |
| 12 | GPU Thermals | timeseries |

A secondary source is the **"Spark Cluster Metrics"** dashboard (`spark-system.json`), which adds per-host detail including loopback throughput, memory fault rate, and GPU card activity.

---

## 2. Dashboard port status

### 2.1 New Dashboard (DQL — primary): `d879f582-1e11-486d-8f08-56d13a706eed`

Deployed by `deploy.yml --tags new_dashboard`. All tiles render without errors as of v10 (version 22).

| Grafana source panel | Dynatrace DQL tile | Metric key | Status |
|---|---|---|---|
| GPU Compute Envelope | GPU Core Utilization (%) | `system.gpu.utilization.core_percent` | ✅ Live — custom ingest |
| GPU Thermals | GPU Edge Temperature (°C) | `system.gpu.temperature_c.edge` | ✅ Live — custom ingest |
| Average System Compute Use | Average CPU Usage (%) | `dt.host.cpu.usage` | ✅ OOB Grail |
| Average System Memory Pressure | Average Memory Usage (%) | `dt.host.memory.usage` | ✅ OOB Grail |
| Total Network Throughput | Network Throughput (B/s) — rx + tx | `dt.host.net.nic.bytes_rx/tx` | ✅ OOB Grail |
| Total Disk Throughput | Disk Throughput (B/s) — read + write | `dt.host.disk.bytes_read/written` | ✅ OOB Grail |
| Total System Load Trend | System Load Average (1 min) | `dt.host.cpu.load` | ✅ OOB Grail |
| *(Grafana: disk capacity)* | Disk Used (%) | `dt.host.disk.used.percent` | ✅ OOB Grail — added |
| Total GC Pause Time | GC Pause Time (ms) | `dt.runtime.jvm.gc.total_collection_time` | ⚠️ See §4 |
| Total GC Heap Reclaimed | GC Suspension Time (ms) | `dt.runtime.jvm.gc.suspension_time` | ⚠️ See §4 |
| *(JVM heap)* | JVM Heap Used (B) | `dt.runtime.jvm.memory_pool.used` | ⚠️ See §4 |
| *(GC frequency)* | GC Activation Count | `dt.runtime.jvm.gc.total_activation_count` | ⚠️ See §4 |

**Not yet ported to New Dashboard:**

| Grafana panel | Reason | Path forward |
|---|---|---|
| Active Application Jobs | `builtin:tech.jvm.spark.apps.gauge` is Classic-only; no Grail key exists | Phase 3: derive from traces/logs, or sampler |
| Spark Log Volume | Requires DQL `fetch logs` tile, not a `timeseries` tile | Phase 2: add a log-count DQL tile |
| Total Page Fault Rate | No confirmed Grail key mapping | Investigate `dt.host.mem.pagefaults` or similar |

### 2.2 Classic Dashboard (DATA_EXPLORER): `df044b4c-c7fb-472d-a6a0-fed81dccf2fc`

Deployed by `deploy.yml --tags dashboards`. Uses Classic metric selector syntax for signals not yet in Grail.

| Tile | Metric selector | Notes |
|---|---|---|
| Active Spark Applications | `builtin:tech.jvm.spark.apps.gauge` | Spark master only |
| Alive Spark Workers | `builtin:tech.jvm.spark.aliveWorkers.gauge` | Spark master only |
| Average Host CPU | `builtin:host.cpu.usage` | Classic |
| Average Host Memory | `builtin:host.mem.usage` | Classic |
| GPU Core Utilization | `system.gpu.utilization.core_percent` | Custom ingest |
| GPU Memory Utilization | `system.gpu.utilization.memory_percent` | Custom ingest |
| GPU Temperature (Edge) | `system.gpu.temperature_c.edge` | Custom ingest |
| GPU Power Draw | `system.gpu.power.watts` | Custom ingest |
| GPU Core Clock | `system.gpu.clocks.core_mhz` | Custom ingest |
| JVM GC Collection Time | `builtin:tech.jvm.memory.gc.collectionTime` | OOB Classic |
| JVM GC Suspension Time | `builtin:tech.jvm.memory.gc.suspensionTime` | OOB Classic |
| JVM Heap Used | `builtin:tech.jvm.memory.pool.used` | OOB Classic |
| JVM GC Activation Count | `builtin:tech.jvm.memory.gc.activationCount` | OOB Classic |
| JVM Memory Allocation Rate | `builtin:tech.jvm.memory.memAllocationBytes` | OOB Classic |

---

## 3. Architecture

### 3.1 Host topology

```
┌──────────────────────────────────────────────────────────────────────┐
│  Lab network (.lan)                                                  │
│                                                                      │
│  ┌────────────────┐   ┌────────────────┐   ┌───────────────────┐   │
│  │     Lab1       │   │     Lab2       │   │      Lab3         │   │
│  │ K8s worker     │   │ K8s master     │   │ Observability     │   │
│  │ AMD RDNA3 GPU  │   │ AMD RDNA3 GPU  │   │ No discrete GPU   │   │
│  │ DynaKube pod   │   │ DynaKube pod   │   │ DynaKube pod      │   │
│  │ gpu-metrics-dt │   │ gpu-metrics-dt │   │                   │   │
│  └────────────────┘   └────────────────┘   └───────────────────┘   │
│           │                   │                       │              │
│           └───────────────────┴───────────────────────┘              │
│                               │                                      │
│                       Dynatrace Operator                             │
│                    (cloudNativeFullStack)                            │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                │ HTTPS
                                ▼
                    ┌─────────────────────┐
                    │  Dynatrace SaaS     │
                    │  pdt20158           │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │    Grail      │  │
                    │  │ (metric store)│  │
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │Classic Metrics│  │
                    │  └───────────────┘  │
                    └─────────────────────┘
```

### 3.2 Data flow: full picture

```
╔══════════════════════════════════════════════════════════════════╗
║  METRIC SOURCES                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  1. AMD GPU hardware (Lab1, Lab2)                                ║
║     /sys/class/drm/card*/device/** (sysfs + hwmon)              ║
║     │                                                            ║
║     │  systemd timer: gpu-metrics-dt.timer (every 10 s)         ║
║     │  Unit: gpu-metrics-dt.service                             ║
║     │  EnvironmentFile: /etc/dynatrace/gpu-sampler.env          ║
║     ▼                                                            ║
║     gpu-metrics-dt.py  (Python 3, stdlib only)                  ║
║     │  Reads sysfs, formats Dynatrace line protocol              ║
║     │  Dimensions: gpu.card, gpu.bus_address, host.name          ║
║     │  Namespace:  system.gpu.*                                  ║
║     │                                                            ║
║     ├─► PRIMARY: POST /api/v2/metrics/ingest  (DT_INGEST_TOKEN) ║
║     │      → Dynatrace Grail  ◄── DQL timeseries reads here     ║
║     │      → Classic Metrics  ◄── DATA_EXPLORER reads here      ║
║     │                                                            ║
║     └─► FALLBACK: POST http://127.0.0.1:14499/metrics/ingest    ║
║              → Classic Metrics only (no Grail)                  ║
║                                                                  ║
║  2. Kubernetes nodes (Lab1, Lab2, Lab3)                          ║
║     DynaKube OneAgent DaemonSet (cloudNativeFullStack)           ║
║     │  Auto-collects host CPU, memory, disk, network, load       ║
║     │  Auto-instruments Spark JVM processes (GC, heap)           ║
║     │                                                            ║
║     ├─► Grail:          dt.host.*  (host infrastructure)         ║
║     │                   dt.runtime.jvm.*  (JVM GC — Grail-native)║
║     └─► Classic Metrics: builtin:host.*  (host)                  ║
║                          builtin:tech.jvm.*  (JVM — Classic-only)║
║                          builtin:tech.jvm.spark.*  (Spark master) ║
╚══════════════════════════════════════════════════════════════════╝
                           │
                           ▼
╔══════════════════════════════════════════════════════════════════╗
║  DYNATRACE GRAIL (queryable via DQL timeseries)                  ║
║                                                                  ║
║  system.gpu.*              — custom ingest (Lab1, Lab2)          ║
║  dt.host.cpu.usage         — OOB, all Lab hosts                  ║
║  dt.host.memory.usage      — OOB, all Lab hosts                  ║
║  dt.host.net.nic.bytes_*   — OOB, all Lab hosts                  ║
║  dt.host.disk.*            — OOB, all Lab hosts                  ║
║  dt.host.cpu.load          — OOB, all Lab hosts                  ║
║  dt.runtime.jvm.gc.*       — OOB, Spark JVM processes            ║
║  dt.runtime.jvm.memory_*   — OOB, Spark JVM processes            ║
╚══════════════════════════════════════════════════════════════════╝
                           │
                           ▼
╔══════════════════════════════════════════════════════════════════╗
║  DASHBOARDS                                                      ║
║                                                                  ║
║  New Dashboard (DQL tiles)          d879f582-1e11-486d-8f08-... ║
║    timeseries + entityName() + filter + fieldsRemove             ║
║    Managed by: apply_spark_system_dashboard_new.yml              ║
║    Tag: new_dashboard                                            ║
║                                                                  ║
║  Classic Dashboard (DATA_EXPLORER)  df044b4c-c7fb-472d-a6a0-... ║
║    metricSelector against Classic Metrics                        ║
║    Managed by: apply_spark_system_dashboard.yml                  ║
║    Tag: dashboards                                               ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 4. JVM GC metrics in Grail — known uncertainty

The New Dashboard includes four JVM GC tiles targeting `dt.runtime.jvm.*` keys. These keys appear in the Dynatrace "Built-in metrics on Grail" mapping table as the Grail-native equivalents of `builtin:tech.jvm.memory.gc.*`. However, whether they contain live data for this tenant depends on the Dynatrace version and feature activation.

**To verify at the tenant:**

```dql
-- In a Notebook DQL cell:
metrics | filter startsWith(metric.key, "dt.runtime.jvm") | dedup metric.key | sort metric.key
```

- If rows are returned → Grail GC data is available; the New Dashboard tiles will show data.
- If empty → GC data is Classic-only for this tenant. Use the Classic Dashboard for GC panels.

**If Grail GC data is needed and currently absent:** The fallback is a `jstat`/GC-log sampler that POSTs `process.runtime.jvm.gc.*` lines to `/api/v2/metrics/ingest` — same pattern as `gpu-metrics-dt.py`. This is deferred to Phase 3.

---

## 5. Partition and access control model

All resources in the Dynatrace tenant are scoped to the project using three in-tenant partitioning constructs applied in `deploy.yml --tags partitioning`:

```
┌─────────────────────────────────────────────────────────────┐
│  Dynatrace tenant: pdt20158                                 │
│                                                             │
│  Host group:        spark-observability                     │
│  Management zone:   Spark Observability                     │
│    ├── Rule: HOST_GROUP_NAME == spark-observability         │
│    └── Rule: KUBERNETES_CLUSTER_NAME == spark-obs-k8s       │
│         (propagates to process group instances)             │
│                                                             │
│  Auto-tags (Settings 2.0, applied to all entities):        │
│    Project:spark-observability                              │
│    Environment:lab                                          │
│    OwnedBy:gbrooks                                         │
└─────────────────────────────────────────────────────────────┘
```

The management zone scopes DQL entity filters for the dashboard. Because `tags` and `managementZones` are not available inside DQL `lookup [...]` subqueries, entity filtering in the New Dashboard uses:
- `entityName(dt.entity.host)` to resolve entity IDs to display names
- `filter in(host, "Lab1", "Lab2", "Lab3")` in the outer pipeline

---

## 6. Solution elements and relationships

```
ansible/playbooks/observability/dynatrace/
│
├── install.yml              ← oneagent host install + GPU sampler deploy
│   └── tasks/install_gpu_sampler.yml
│       ├── Deploys gpu-metrics-dt.py, .service, .timer
│       └── Deploys /etc/dynatrace/gpu-sampler.env (DT_INGEST_TOKEN)
│
├── deploy.yml               ← API-driven config: tags, MZ, dashboards
│   ├── tasks/tenant_check.yml           ← Validates tenant reachability
│   ├── tasks/ensure_api_token_scopes.yml ← Checks required token scopes
│   ├── tasks/apply_management_zone.yml   ← Settings 2.0 MZ upsert
│   ├── tasks/apply_auto_tags.yml         ← Settings 2.0 tag upsert
│   ├── tasks/deploy_operator.yml         ← Dynatrace Operator Helm
│   ├── tasks/apply_dynakube.yml          ← DynaKube CR (cloudNativeFullStack)
│   ├── tasks/probe_dql_dashboard_queries.yml  ← DQL query validator (§7)
│   ├── tasks/apply_spark_system_dashboard.yml      ← Classic dashboard
│   └── tasks/apply_spark_system_dashboard_new.yml  ← New Dashboard (DQL)
│
└── diagnose.yml             ← Non-destructive health checks
    └── tasks/probe_spark_system_dashboard_signals.yml  ← metric inventory

observability/dynatrace/
├── README.md                ← Module overview, token model, ingest path
├── docs/
│   └── Spark_System_Metrics_Dashboard_Plan.md  ← Phase plan, DQL notes
├── dynakube/dynakube.yaml.j2  ← DynaKube CR (cloudNativeFullStack)
├── management-zone/spark-observability-zone.json  ← MZ definition
├── automatic-tags/spark-observability-tags.json.j2 ← Auto-tag definitions
└── sampler/gpu/
    ├── gpu-metrics-dt.py    ← AMD GPU sysfs reader + REST ingest
    ├── gpu-metrics-dt.service ← systemd service unit
    ├── gpu-metrics-dt.timer   ← systemd timer (10 s interval)
    └── README.md
```

### Token model

| Token variable | Type | Auth scheme | Endpoints | Scopes |
|---|---|---|---|---|
| `DT_INGEST_TOKEN` | API token | `Api-Token` | `/api/v2/metrics/ingest` | `metrics.ingest` |
| `DT_API_TOKEN` | API token | `Api-Token` | `/api/config/v1/*`, `/api/v2/*` | `ReadConfig`, `WriteConfig`, `entities.read`, `settings.read`, `settings.write`, `metrics.read` |
| `DT_PLATFORM_TOKEN` | Platform token | `Bearer` | `/platform/document/v1/*` | `document:read`, `document:write`, `document:delete` |
| `DT_PLATFORM_TOKEN_GRAIL` | Platform token | `Bearer` | `/platform/storage/query/v1/*` | `storage:metrics:read`, `storage:entities:read` *(not yet created — needed for live DQL probe)* |

---

## 7. DQL probe — validation before dashboard deploy

`tasks/probe_dql_dashboard_queries.yml` (tag: `probe_dql`) runs two stages:

**Stage 1 — Static (runs now, no special token needed):**  
Reads `/tmp/spark_system_dashboard_content.json` and checks all 12 DQL tile query strings against six anti-pattern rules:

| Rule | What it catches |
|---|---|
| Backtick in DQL query | `` ` `` is not a valid DQL identifier-escape character |
| `\| fields timeframe` after timeseries | Destroys timeseries array format; chart cannot render as line |
| `prefix:"..."` in lookup | Custom prefix syntax; use default `lookup.` prefix |
| SQL-style `field in (list)` | DQL uses function form: `in(field, val1, val2, ...)` |
| `timestamp` field name | `timeseries` outputs `timeframe`, not `timestamp` |
| `managementZones` / `.tags` in lookup | Not accessible inside `[...]` subquery context |

**Stage 2 — Live DQL execute (optional):**  
Requires `DT_PLATFORM_TOKEN_GRAIL` in `vars/secrets.yaml` with `storage:metrics:read` and `storage:entities:read` scopes. Create at Settings → Access Tokens → Generate new token.

```bash
# Run the probe independently before deploying:
ansible-playbook ansible/playbooks/observability/dynatrace/deploy.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags probe_dql

# Deploy the New Dashboard:
ansible-playbook ansible/playbooks/observability/dynatrace/deploy.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags new_dashboard
```

---

## 8. DQL lessons learned

The following DQL pitfalls were discovered iteratively during dashboard development. The static probe now catches all of them before deployment.

| Iteration | Error seen in UI | Root cause | Fix |
|---|---|---|---|
| v4 | `tags isn't allowed here` | `tags` field used inside `lookup [...]` subquery | Not available in subquery context; filter in outer pipeline |
| v5 | `managementZones isn't allowed here` | Same — `managementZones` also blocked in subquery | Same fix |
| v6 | `timestamp doesn't exist` | `timeseries` output column is named `timeframe`, not `timestamp` | Use `timeframe` |
| v7 | `` ` isn't allowed here`` | Backtick quoting (`` `field`=alias ``) is not valid DQL syntax | Use plain alias: `alias=field` |
| v7 | `tags isn't allowed here` | `"Project:spark-observability" in tags` — `tags` blocked in lookup subquery | Moved filter to outer pipeline |
| v8 | `` ` isn't allowed here`` | Backticks also in markdown tile content strings; renderer scans all tile content | Removed all backticks from entire dashboard JSON |
| v9 | `` ` isn't allowed here`` | `field in (list)` — SQL syntax not valid in DQL | Use `in(field, val1, val2, ...)` function form |
| v9 | `lookup.entity.name` undefined | Custom `prefix:"h_"` creates `h_entity.name` but syntax uncertain | Use default `lookup.` prefix (no `prefix:` argument) |
| v10 | Data not suitable for Line | `\| fields timeframe, cpu, host=...` after `timeseries` converts arrays to scalars, destroying chart format | Use `fieldsAdd` + `fieldsRemove` which preserve timeseries structure; replace lookup with `entityName()` built-in |

---

## 9. Phase roadmap

### Phase 1 — Complete ✅

- GPU metrics custom ingest: `system.gpu.*` via REST API to Grail
- New Dashboard with 12 DQL tiles (GPU + host + JVM GC)
- Classic Dashboard with 15 DATA_EXPLORER tiles (full signal coverage)
- DynaKube cloudNativeFullStack: K8s monitoring + JVM auto-instrumentation
- Management zone and auto-tags for project partitioning
- Ansible automation: install, deploy, diagnose playbooks
- DQL static validation probe

### Phase 2 — Next

- **Spark Log Volume tile:** Add a `fetch logs | filter ...` DQL tile to the New Dashboard, counting Spark log events by severity over time.
- **Page Fault tile:** Identify the Grail metric key for page faults (candidate: `dt.host.mem.pagefaults`); add to New Dashboard.
- **Verify JVM GC in Grail:** Run `metrics | filter startsWith(metric.key, "dt.runtime.jvm")` in a Notebook. If present, the existing New Dashboard GC tiles will populate automatically. If absent, the Classic Dashboard tiles remain the authoritative GC source.
- **Enable live DQL probe:** Create `DT_PLATFORM_TOKEN_GRAIL` with `storage:metrics:read` + `storage:entities:read` scopes; add to `vars/secrets.yaml`.

### Phase 3 — Future

- **Active Application Jobs:** Derive from Dynatrace distributed traces (open Spark job spans) or a `jmx`/REST sampler against the Spark master UI.
- **JVM GC Grail ingest (if OOB absent):** `jstat`-based sampler posting `process.runtime.jvm.gc.*` to `/api/v2/metrics/ingest`, same pattern as `gpu-metrics-dt.py`.
- **EF2 packaging:** Wrap `gpu-metrics-dt.py` as an Extension Framework 2.0 Python extension for Dynatrace-native lifecycle management.
- **Spark Log Details and GC Analysis:** Port Grafana `spark-log-details.json` and `spark-gc-analysis.json` dashboards.

---

## 10. Quick reference

### Deploy commands

```bash
# Full Dynatrace deploy (MZ, tags, operator, dashboards):
ansible-playbook ansible/playbooks/observability/dynatrace/deploy.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml

# New Dashboard only:
ansible-playbook ansible/playbooks/observability/dynatrace/deploy.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags new_dashboard

# GPU sampler deploy/update:
ansible-playbook ansible/playbooks/observability/dynatrace/install.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags gpu_sampler

# Validate DQL tile queries (static):
ansible-playbook ansible/playbooks/observability/dynatrace/deploy.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags probe_dql

# Diagnose metric availability:
ansible-playbook ansible/playbooks/observability/dynatrace/diagnose.yml \
  -i ansible/inventory.yml -e @vars/secrets.yaml --tags dashboard_signals
```

### Useful DQL in Notebooks

```dql
-- List all custom GPU metric keys
metrics | filter startsWith(metric.key, "system.gpu") | dedup metric.key

-- Verify Grail JVM GC keys exist
metrics | filter startsWith(metric.key, "dt.runtime.jvm") | dedup metric.key | sort metric.key

-- Verify Spark master keys (expected: empty in Grail)
metrics | filter contains(metric.key, "spark") | dedup metric.key

-- Quick GPU chart
timeseries core=avg(system.gpu.utilization.core_percent), by:{host.name, gpu.card}

-- Host CPU scoped to Lab hosts
timeseries cpu=avg(dt.host.cpu.usage), by:{dt.entity.host}
| fieldsAdd host=entityName(dt.entity.host)
| filter in(host, "Lab1", "Lab2", "Lab3")
| fieldsRemove dt.entity.host
```

### Dashboard URLs

| Dashboard | URL |
|---|---|
| New Dashboard (DQL) | `https://pdt20158.apps.dynatrace.com/#dashboard;id=d879f582-1e11-486d-8f08-56d13a706eed` |
| Classic Dashboard | `https://pdt20158.live.dynatrace.com/#dashboard;id=df044b4c-c7fb-472d-a6a0-fed81dccf2fc` |
