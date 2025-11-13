# Quick Start: Downsampling Implementation

## 🚀 Quick Deployment (3 minutes)

### Option A: Fresh Installation (Recommended)

If you're setting up from scratch, the ILM policies are automatically created:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh
```

This creates all downsampling ILM policies automatically in STEP 10.

Then attach policies to data streams:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./attach-policies-to-datastreams.sh
```

### Option B: Existing Installation

If Elasticsearch is already running and configured:

### Step 1: Apply ILM Policies
```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./apply-ilm-policies.sh
```

### Step 2: Attach Policies to Data Streams

Use the automated script:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./attach-policies-to-datastreams.sh
```

Or manually using esapi:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin

# System metrics
./esapi PUT 'metrics-system.cpu-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.memory-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.network-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.diskio-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
./esapi PUT 'metrics-system.load-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'

# Docker metrics
./esapi PUT 'metrics-docker.cpu-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'
./esapi PUT 'metrics-docker.memory-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'
./esapi PUT 'metrics-docker.network-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'

# Spark GC
./esapi PUT 'logs-spark_gc-default/_settings' -d '{"index.lifecycle.name":"spark-gc-downsampled"}'

# Spark log metrics
./esapi PUT 'metrics-spark-logs-default/_settings' -d '{"index.lifecycle.name":"spark-logs-metrics-downsampled"}'
```

### Step 3: Restart Grafana
```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability
docker-compose restart grafana
```

### Step 4: Access New Dashboard
Open browser: `http://GaryPC.local:3000/d/spark-system-metrics-aggregated`

### Step 5: Validate
```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./validate-downsampling.sh
```

## 📊 What You Get

### New Dashboard: "Spark System Metrics"
- **URL**: `/d/spark-system-metrics-aggregated`
- **UID**: `spark-system-metrics-aggregated`
- **Features**:
  - Aggregated metrics across all cluster nodes
  - Granularity dropdown (30s, 5m, 15m, 60m)
  - 10 panels showing system, GC, and log metrics
  - Automatic refresh every 30 seconds

### Retention Strategy
| Tier | Age | Granularity | Action |
|------|-----|-------------|--------|
| Hot | 0-2 days | 30 seconds | Keep original |
| Warm | 2-4 days | 5 minutes | Downsample |
| Cold | 4-8 days | 15 minutes | Downsample |
| Frozen | 8-12 days | 60 minutes | Downsample |
| Delete | >12 days | - | Remove |

### Storage Savings
- **Expected reduction**: ~95% with full retention
- **Keep**: 12 days of historical data
- **Original storage**: ~360 GB for 12 days (example)
- **With downsampling**: ~18 GB for 12 days

## 🔍 Verification

### Check ILM Status
```bash
curl -u elastic:myElastic2025 --cacert /etc/ssl/certs/elastic/ca.crt \
  https://GaryPC.local:9200/_ilm/status
```

Expected: `{"operation_mode":"RUNNING"}`

### Check Policy Applied
```bash
curl -u elastic:myElastic2025 --cacert /etc/ssl/certs/elastic/ca.crt \
  https://GaryPC.local:9200/metrics-system.cpu-default/_ilm/explain?pretty
```

Should show: `"policy": "system-metrics-downsampled"`

### Monitor Downsampling (after 2+ days)
```bash
curl -u elastic:myElastic2025 --cacert /etc/ssl/certs/elastic/ca.crt \
  https://GaryPC.local:9200/_cat/indices/.ds-*downsample*?v
```

## 📝 Important Notes

1. **Initial Data**: Dashboard won't show much data immediately. Wait 1-2 hours for metrics to accumulate.

2. **First Downsample**: First downsampling occurs after 2 days. Check back then to verify.

3. **Non-Destructive**: Original data is preserved for 2 days before first downsample.

4. **Automatic**: Once configured, everything is automatic. No manual intervention needed.

5. **Testing Values**: The 12-day total retention is intentionally short for testing. Adjust in `variables.yaml` for production:
   ```yaml
   ES_RETENTION_BASE: 7d      # Instead of 2d
   ES_RETENTION_5MIN: 30d     # Instead of 4d
   ES_RETENTION_15MIN: 90d    # Instead of 8d
   ES_RETENTION_60MIN: 365d   # Instead of 12d
   ```

## 🆘 Troubleshooting

### Dashboard shows "No data"
- Verify Elastic Agent is running on all nodes
- Check data streams exist: `GET _data_stream/metrics-system.*-default`
- Wait 30-60 minutes for initial data collection

### Policies not applying
- Check ILM is running: `GET _ilm/status`
- Verify policies exist: `GET _ilm/policy/system-metrics-downsampled`
- Review Elasticsearch logs for errors

### Downsampling not occurring
- Wait for data to age (2 days minimum)
- Check rollover happened: `GET _cat/indices/.ds-metrics-*`
- Force ILM check: `POST _ilm/poll`

## 📚 Full Documentation

- **Implementation Details**: `/observability/DOWNSAMPLING_IMPLEMENTATION.md`
- **ILM Policies**: `/observability/elasticsearch/system-metrics/README.md`
- **Dashboard Guide**: `/observability/grafana/dashboards/spark-system-metrics-aggregated.md`
- **Variables**: `/variables.yaml` (lines 34-53)

## ✅ Success Criteria

After 2 days:
- [ ] Dashboard displays aggregated metrics
- [ ] ILM shows "warm" phase for 2-day-old data
- [ ] Downsampled indices visible in `_cat/indices`
- [ ] No ILM errors in `_ilm/explain`
- [ ] Granularity dropdown works
- [ ] Storage usage lower than before

## 🎯 Next Steps

1. **Today**: Deploy and verify basic functionality
2. **Day 2**: Check first downsampling (5m) occurred
3. **Day 4**: Check second downsampling (15m) occurred
4. **Day 8**: Check third downsampling (60m) occurred
5. **Day 12**: Verify old data deleted
6. **After testing**: Adjust retention periods in `variables.yaml` for production

## 🔗 Related Dashboards

- **Spark Cluster Metrics** (`/d/spark-system-metrics`): Per-node metrics
- **Spark Logs Viewer** (`/d/spark-logs-viewer`): Detailed log analysis
- **Spark GC Analysis** (`/d/spark-gc-analysis`): GC deep dive

---

**Questions?** See full implementation doc: `/observability/DOWNSAMPLING_IMPLEMENTATION.md`

