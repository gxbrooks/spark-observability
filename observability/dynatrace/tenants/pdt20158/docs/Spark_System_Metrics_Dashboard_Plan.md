# Spark System Metrics in Dynatrace (Plan + Phase 1)

## Goal

Create a global, high-level Spark environment view in Dynatrace using the
"Dynatrace way": prefer OOB entity views and built-in dimensions first, then
add targeted custom charts only where OOB does not cover the signal.

## OOB versus custom balance

### OOB first (preferred)

- Cluster and node health from Kubernetes / Infrastructure apps.
- Host CPU, memory, disk, and network trends from built-in metrics.
- Service and trace performance from Distributed Tracing app.
- Problem cards and Davis root-cause context.

### Custom where needed

- One consolidated "Spark System Metrics" dashboard that combines global
  rollups in one place for operators.
- Computed Spark "active jobs" signal (open operations) once we confirm a
  robust source in Dynatrace traces/logs.
- GPU and GC signals if they are not present as built-in metrics in this tenant.

## Panel mapping (Grafana -> Dynatrace target)

1. Active Application Jobs -> **Custom (phase 2)** from spans/logs query
2. Spark Log Volume -> **Custom (phase 2)** from logs/traces query
3. Average System Compute Use -> **OOB metric rollup**
4. Average System Memory Pressure -> **OOB metric rollup**
5. Total Network Throughput -> **OOB metric rollup**
6. Total Disk Throughput -> **OOB metric rollup**
7. Total System Load Trend -> **OOB metric rollup**
8. Total Page Fault Rate -> **OOB metric rollup**
9. Total GC Pause Time -> **Custom plumbing required**
10. Total GC Heap Reclaimed -> **Custom plumbing required**
11. GPU Compute Envelope -> **Custom plumbing required**
12. GPU Thermals -> **Custom plumbing required**

## Implementation phases

### Phase 1 (implemented now)

- Added a Dynatrace diagnose probe task that inventories metric descriptors by
  signal class (`spark`, `cpu`, `memory`, `network`, `disk`, `load`, `page`,
  `gc`, `gpu`) to determine what can be mapped to OOB immediately.
- This probe is wired into `ansible/playbooks/observability/dynatrace/diagnose.yml`
  under tag `dashboard_signals`.

### Phase 2 (next implementation)

- Build the first Dynatrace dashboard with only high-confidence OOB panels:
  CPU, memory, network, disk, load, page faults.
- Keep each panel scoped by project partitioning dimensions (management zone /
  tags / cluster name), not raw host lists.

### Phase 3 (custom signal plumbing)

- GC metrics: add OTel/log pipeline extraction into Dynatrace metric keys.
- GPU metrics: ingest node GPU metrics into Dynatrace metrics with stable labels.
- Active jobs: derive from trace/log model and validate semantics with Spark
  batch lifecycle (open START minus END).

## How to run the new signal inventory

```bash
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/dynatrace/diagnose.yml \
  --tags dashboard_signals
```

## Guardrails

- Avoid cloning every Grafana panel as custom Dynatrace visualizations.
- Keep OOB apps as the primary troubleshooting path.
- Use custom dashboards for cross-signal operator summary only.

## New Dashboards app: DQL and `builtin:` metrics

Grail `timeseries` aggregations take a **metric key identifier**, not a string
literal. Per [DQL metric commands](https://docs.dynatrace.com/docs/platform/grail/dynatrace-query-language/commands/metric-commands),
the first argument to `max()` / `avg()` / … must be that identifier.

- **Wrong:** `max("builtin:tech.jvm.spark.apps.gauge", scalar:true)` — double
  quotes make a **string**, which produces **The parameter has to be a metric key**.

### Spark master metrics (`builtin:tech.jvm.spark.*`) and Grail

Not every Metrics Classic key exists on Grail. Dynatrace documents that
[some Classic metrics have no Grail equivalent yet](https://docs.dynatrace.com/docs/shortlink/metrics-selector-conversion#troubleshooting-converted-dql)
and that DQL should use **Grail** metric keys.

The large mapping table in [Built-in metrics on Grail](https://docs.dynatrace.com/docs/shortlink/built-in-metrics-on-grail)
lists many `builtin:tech.jvm.*` → `dt.runtime.jvm.*` / `dt.profiling.jvm.*`
pairs, but **does not list** `builtin:tech.jvm.spark.apps.gauge`,
`builtin:tech.jvm.spark.aliveWorkers.gauge`, or similar Spark master gauges.

**If you still see “The parameter has to be a metric key” after fixing quoting,**
the usual cause is that **`timeseries` has no registered Grail key for that
signal** — backticks around `builtin:…` do not help when the metric is not
stored for DQL. Confirm in a Notebook or **DQL** tile (not `fetch`):

```text
metrics | filter contains(metric.key, "spark") | dedup metric.key | sort metric.key
```

`metrics` is a **DQL starting command** (like `timeseries`), not a telemetry type.
If you run `fetch metrics`, the UI reports that there is no telemetry called
`metric`. Use `metrics` as the **first** token. This query only **lists** which
`metric.key` values exist in Grail for exploration; it does not return a
chartable time series. For values over time, use `timeseries` with a key you
already know (from this table, the metric picker, or Data Explorer conversion).

- If **none** of the rows match the Classic `metricId` you use in Data Explorer,
  you **cannot** drive that signal from a New Dashboards **DQL** tile today.
  Use a **Classic** dashboard / Data Explorer tile (metric selector), e.g. the
  DATA_EXPLORER payloads in
  `ansible/playbooks/observability/dynatrace/tasks/apply_spark_system_dashboard.yml`,
  or use **Data Explorer → Open with… → Dashboards** and only adopt the
  generated DQL when that action is offered for your metric.

- If a row **does** appear (for example a `dt.*` key), use that identifier
  **unquoted** in `timeseries`, e.g. `timeseries spark_apps=max(dt.example.key, scalar:true)`.

For metrics that exist on Grail but whose Classic name contains characters that
are not valid in a bare identifier, the Grail docs describe **backtick** metric
references for some extension-style keys; that still requires the key to be
present in Grail.

### Notebook diagnostics when `metrics | … "spark"` returns no rows

**No records** can mean (a) there is no Grail series whose `metric.key` contains
`spark`, (b) the Notebook **timeframe** is too narrow or outside the last **10
days** (Grail `metrics` limit), (c) a **segment** filters out all metric data,
or (d) the user lacks **Grail** permissions such as `storage:metrics:read`.

Run these **in order** in a Notebook DQL cell (use a **wider timeframe**, e.g.
last 24h or 7d; clear custom segments if unsure):

1. **Confirm Grail metrics work at all**

   ```text
   timeseries avg(dt.host.cpu.usage)
   ```

   If this is empty, fix timeframe, segments, or IAM before debugging Spark.

2. **See any metric keys (sanity check)**

   ```text
   metrics | dedup metric.key | limit 50
   ```

   If this is empty but step 1 worked, try `metrics | limit 50` or widen
   timeframe; if still empty, check permissions and segments.

3. **Broader JVM search** (Spark keys often include `jvm`, not the word `spark`)

   ```text
   metrics | filter contains(metric.key, "jvm") | dedup metric.key | limit 100
   ```

4. **Classic name fragments** (if present on Grail under another spelling)

   ```text
   metrics | filter contains(metric.key, "aliveWorkers") | dedup metric.key
   ```

   ```text
   metrics | filter contains(metric.key, "tech.jvm") | dedup metric.key | limit 50
   ```

5. **Scoped to one host** (replace with a real `HOST-…` from your environment)

   ```text
   metrics | filter dt.entity.host == "HOST-6DF6DE092963F2AB" | dedup metric.key | limit 100
   ```

**How to read results:** If steps 2–5 never show a key you can map to Spark
master gauges, treat those signals as **Classic-only** for New Dashboards DQL
tiles and keep using Data Explorer / Dashboards Classic for them.
