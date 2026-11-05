# Spark Cluster Metrics Dashboard

**Dashboard Name**: Spark Cluster Metrics  
**UID**: `spark-system-metrics`  
**File**: `provisioning/dashboards/spark-system.json`  
**URL**: `http://garypc.local:3000/d/spark-system-metrics/spark-cluster-metrics`

## Purpose

This dashboard provides comprehensive monitoring of Spark cluster infrastructure and application performance across both host-level system metrics and Spark-specific application metrics.

## Rationale

### Why Monitor Spark at Multiple Levels?

1. **Infrastructure Health**: Host metrics reveal resource contention, bottlenecks, and capacity issues
2. **Application Performance**: GC and heap metrics show Java/Spark efficiency
3. **Correlation**: Combining both views helps identify root causes (e.g., high page faults indicating memory pressure)
4. **Proactive Monitoring**: Detect issues before they impact jobs

## Panels

### 1. Host CPU Utilization %
**Query**: `metrics-system.cpu-default`  
**Field**: `system.cpu.total.pct`  
**Visualization**: Time series

**What it shows**: Total CPU usage percentage for each host (Lab1, Lab2)

**Why it matters**:
- High sustained CPU (>80%) indicates resource saturation
- Correlate with Spark job execution to verify resource allocation
- Identify which host is under heavier load

**Action triggers**:
- CPU >90% for >5 minutes: Consider scaling horizontally
- Unbalanced load between hosts: Check Spark worker distribution

### 2. Host Memory Utilization %
**Query**: `metrics-system.memory-default`  
**Field**: `system.memory.used.pct`  
**Visualization**: Time series

**What it shows**: Memory usage percentage for each host

**Why it matters**:
- High memory (>85%) can trigger OOM kills
- Memory pressure causes increased GC activity
- Indicates if executors are properly sized

**Action triggers**:
- Memory >90%: Reduce executor memory or add nodes
- Sudden spikes: Check for memory leaks in application code

### 3. Network Byte Rate (In/Out)
**Query**: `metrics-system.network-default`  
**Fields**: `system.network.in.bytes`, `system.network.out.bytes` (derivative)  
**Visualization**: Time series with dual series

**What it shows**: Network throughput in bytes/second for ingress and egress

**Why it matters**:
- Spark shuffle operations are network-intensive
- High network I/O during shuffle phases is expected
- Network saturation causes job slowdowns

**Action triggers**:
- Sustained high throughput: Verify network capacity (1Gbps vs 10Gbps)
- Unbalanced traffic: Check data locality and partition distribution
- Network errors: Check `system.network.in.errors`

### 4. Disk I/O Rate (Read/Write)
**Query**: `metrics-system.diskio-default`  
**Fields**: `system.diskio.read.bytes`, `system.diskio.write.bytes` (derivative)  
**Visualization**: Time series

**What it shows**: Disk read/write throughput in bytes/second

**Why it matters**:
- Spark spills to disk when memory is insufficient
- High disk I/O indicates memory pressure or large shuffles
- Persistent high I/O suggests under-provisioned memory

**Action triggers**:
- High write rates: Increase executor memory to reduce spill
- High read rates: Check if data is properly cached
- I/O wait time correlation: Disk becoming bottleneck

### 5. Page Fault Rate
**Query**: `metrics-system.memory-default`  
**Fields**: `system.memory.page_stats.pgfault.rate`, `system.memory.page_stats.pgmajfault.rate`  
**Visualization**: Time series

**What it shows**: 
- **Minor page faults**: Memory access requiring page load from disk cache
- **Major page faults**: Memory access requiring disk I/O (very expensive)

**Why it matters**:
- Page faults indicate memory pressure
- Major page faults significantly slow application performance
- High page fault rates suggest insufficient physical memory

**Action triggers**:
- Major page faults >100/sec: Critical memory pressure
- Rising trend: Memory leak or insufficient allocation
- Correlate with GC activity and heap usage

### 6. Filesystem Usage % by Host
**Query**: `metrics-system.filesystem-default`  
**Field**: `system.filesystem.used.pct`  
**Visualization**: Gauge with thresholds

**What it shows**: Disk space utilization per host

**Why it matters**:
- Spark needs disk space for shuffle spill and event logs
- Full disks cause job failures
- Gradual increase indicates log accumulation or data retention issues

**Action triggers**:
- >70% (yellow): Plan for cleanup or expansion
- >85% (red): Immediate action required
- Rapid growth: Check for log accumulation or abandoned temp files

### 7. System Load Average
**Query**: `metrics-system.load-default`  
**Fields**: `system.load.1`, `system.load.5`, `system.load.15`  
**Visualization**: Time series

**What it shows**: Number of processes waiting for CPU (1/5/15 minute averages)

**Why it matters**:
- Load average >CPU cores indicates oversubscription
- Trend (1m vs 15m) shows if load is increasing/decreasing
- High load with low CPU suggests I/O wait

**Action triggers**:
- Load >2x CPU cores: Overcommitted, reduce workload
- Increasing trend: Resource demand growing
- Load high but CPU low: Disk I/O bottleneck

### 8. Spark GC Pause Time
**Query**: `logs-spark_gc-default`  
**Field**: `gc.paused.millis`  
**Visualization**: Time series

**What it shows**: Duration of garbage collection pauses in milliseconds

**Why it matters**:
- GC pauses stop all application threads (stop-the-world)
- Long pauses (>100ms) impact job latency
- Frequent GC indicates memory pressure

**Action triggers**:
- Pauses >500ms: Tune GC settings or increase heap
- Frequent pauses: Reduce executor memory or adjust heap ratios
- Correlate with heap usage trends

### 9. Spark Heap Usage (Before/After GC)
**Query**: `logs-spark_gc-default AND gc.stats:paused`  
**Fields**: `gc.paused.before`, `gc.paused.after`, `gc.paused.heapsize`  
**Visualization**: Time series with three series

**What it shows**: 
- Heap usage before GC
- Heap usage after GC
- Total heap size

**Why it matters**:
- Gap between before/after shows GC effectiveness
- After-GC approaching heap size indicates insufficient memory
- Helps size executor heap appropriately

**Action triggers**:
- After-GC >80% of heap: Increase executor memory
- Small reclamation: Potential memory leak
- Sawtooth pattern: Normal, healthy GC behavior

### 10. Spark Memory Reclaimed by GC
**Query**: `logs-spark_gc-default AND gc.stats:paused`  
**Field**: `gc.paused.reclaimed`  
**Visualization**: Time series

**What it shows**: Amount of memory freed by each GC cycle (MB)

**Why it matters**:
- Effective GC reclaims significant memory
- Declining reclamation suggests memory leak
- Zero reclamation with high CPU indicates thrashing

**Action triggers**:
- Reclaimed <10% of heap: Investigate memory leak
- Increasing frequency with low reclamation: Add memory or optimize code
- Correlate with pause times for GC efficiency

## Time Range Recommendations

| Use Case | Time Range | Refresh Interval |
|----------|------------|------------------|
| Active monitoring | Last 15 minutes | 10 seconds |
| Job investigation | Last 6 hours | 30 seconds |
| Trend analysis | Last 7 days | 5 minutes |
| Capacity planning | Last 30 days | 1 hour |

## Accessing Dashboards

### Direct URL
```
http://garypc.local:3000/d/<uid>/<dashboard-name>
```

### Via UI
1. Navigate to Grafana home
2. Click "Search dashboards" (magnifying glass icon)
3. Browse or search by name
4. Click to open

### Via API
```bash
# List all dashboards
curl -u admin:password http://garypc.local:3000/api/search?type=dash-db

# Get specific dashboard
curl -u admin:password http://garypc.local:3000/api/dashboards/uid/<uid>
```

## Customization

### Adding Panels
1. Open dashboard in Grafana UI
2. Click "Add panel" button (top right)
3. Configure query and visualization
4. Save dashboard
5. Export JSON and commit to repository

### Modifying Queries
1. Edit panel (click title → Edit)
2. Adjust query in Query tab
3. Test and refine
4. Save and export

### Creating Variables
```json
"templating": {
  "list": [
    {
      "name": "host",
      "type": "query",
      "datasource": "spark-elasticsearch",
      "query": "_index:metrics-system.cpu-default | terms:host.name"
    }
  ]
}
```

## Alerting

Grafana can trigger alerts based on panel queries:

### Recommended Alerts
1. **High CPU**: CPU >90% for >5 minutes
2. **Memory Pressure**: Memory >85% for >5 minutes
3. **Disk Full**: Filesystem >90%
4. **Long GC Pauses**: GC pause >1000ms
5. **Major Page Faults**: >1000/sec

### Alert Channels
Configure notification channels in Grafana:
- Email
- Slack
- PagerDuty
- Webhook

## Performance Optimization

### Dashboard Loading
- Limit time range for large datasets
- Use aggregations (avg, max) instead of raw values
- Set appropriate query intervals
- Cache results where possible

### Query Optimization
- Use specific index patterns (not wildcards)
- Add filters to reduce data volume
- Use metric aggregations over document queries
- Leverage Elasticsearch query cache

## Troubleshooting

### No Data Showing
**Check**:
1. Time range includes data timestamps
2. Elasticsearch indices exist: `curl -k -u elastic:password https://garypc.local:9200/_cat/indices`
3. Datasource connection: Configuration → Data Sources → Test
4. Query inspector: Panel menu → Inspect → Query

### Slow Performance
**Solutions**:
1. Reduce time range
2. Increase query interval
3. Add index filters
4. Use aggregations

### Authentication Errors
**Check**:
1. Elasticsearch credentials in datasource
2. User permissions in Elasticsearch
3. Certificate validity if using TLS

## Maintenance

### Regular Tasks
- **Weekly**: Review dashboard usage and remove unused panels
- **Monthly**: Archive old data or adjust retention policies
- **Quarterly**: Update queries for new metric fields
- **Yearly**: Review and optimize dashboard organization

### Version Control
- All dashboard JSON files are version controlled
- Document changes in commit messages
- Test dashboards after Grafana upgrades

## Future Enhancements

### Planned Additions
1. **Kubernetes Container Metrics**: Pod CPU/memory, container restarts
2. **Docker Metrics**: Container resource usage on GaryPC
3. **HDFS Metrics**: Namenode/datanode health
4. **Application-Specific Metrics**: Custom business metrics
5. **Correlation Dashboards**: Link metrics across infrastructure layers

### Integration Opportunities
- Link to Kibana for log analysis
- Embed Prometheus metrics
- Add distributed tracing (Jaeger/Zipkin)
- Custom metric collectors for application KPIs

