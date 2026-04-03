# batch-metrics — DEPRECATED

> **Status:** Deprecated as of 2026-04-03.
> Superseded by `application-events-metrics` (the "Active Application Jobs" panel).

## What it did

The `batch-metrics-ds` pipeline counted **active Spark jobs** by:

1. An Elasticsearch **watcher** (`batch-metrics.watcher.json`) ran every 5 seconds.
2. The watcher queried `batch-events-*` for `Start` events with `matched: false`,
   aggregated counts by `realm` and `class`, and indexed the result into the
   `batch-metrics-ds` data stream.
3. A Grafana panel ("Active Spark Jobs" in `spark-system.json`) graphed the
   time-series from that data stream.

## Why it was deprecated

The pipeline was **non-functional prior to deprecation**:

- **Watcher never fired.** Its condition (`ctx.payload.hits.total > 0`) was
  always false because all historical `Start` events had already been marked
  `matched: true`, and no new `batch-events` were being ingested.
- **Disk flood-stage watermark** on the Elasticsearch node had additionally
  blocked new writes into the data stream.
- The replacement pipeline, `application-events-metrics-ds`, provides
  equivalent and more reliable active-job tracking using the
  `application-events-metrics.watcher.json` against the `app-events-*`
  indices.

## What changed

| Action | Detail |
|--------|--------|
| Grafana panel removed | "Active Spark Jobs" (`id: 1`) removed from `spark-system.json` (v9). |
| `init-index.sh` | Step 11 now prints a skip message; batch-metrics resources are no longer created automatically. |
| Standalone script | `init-index-batch-metrics.sh` (this directory) can recreate the resources manually for testing or migration. |

## Files in this directory

| File | Purpose |
|------|---------|
| `batch-metrics.template.json` | Index template for the `batch-metrics-ds` data stream. |
| `batch-metrics.watcher.json` | Elasticsearch watcher that aggregated open batch counts. |
| `batch-metrics.dataview.json` | Kibana data view for `batch-metrics-ds`. |
| `batch-counts.search.json` | Kibana saved search (Batch Counts). |
| `batch-counts.dashboard.json` | Kibana saved dashboard (Batch Counts by Class). |
| `batch-metrics-completed-jobs.search.json` | Kibana saved search (Completed Batch Jobs). |
| `test-dashboard.json` | Test/scratch dashboard definition. |
| `init-index-batch-metrics.sh` | Standalone init script (not called by `init-index.sh`). |

All JSON config files in this directory are **deprecated** and are retained
only for reference and manual re-initialization.
