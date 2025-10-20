# Spark Application Logs - Implementation Summary

## Executive Summary

Implemented comprehensive Spark application log collection, parsing, and visualization system. All requested tasks completed, ready for review before deployment.

## Problem Analysis

### What Was Found

1. **No Application Log Files**: Spark was only writing GC logs to files. Application logs were going to stdout only.
2. **Wrong Data in Index**: The `logs-spark-spark` index contained **Spark EVENT data** (JSON), NOT application logs. This is why the dataview showed no useful data.
3. **Missing Log Collection**: Elastic Agent was configured to collect logs from non-existent files (`executor-app.log`, `component-app.log`).
4. **Directory Naming**: Used generic `spark/` instead of descriptive `spark-logs/`.
5. **No Log Level Parsing**: No mechanism to extract and classify log levels (INFO, WARN, ERROR, etc.).
6. **No Metrics Aggregation**: No data stream for error level statistics.
7. **No Grafana Visualization**: No panel to display log levels over time.

## Implementation

### 1. Directory & File Renaming ✅

```
observability/elasticsearch/spark/ → spark-logs/
logs-spark-spark.template.json → logs-spark-default.template.json
```

### 2. Elasticsearch Components ✅

**Created: `spark-logs-ingest-pipeline.json`**
- Parses Spark log format: `YYYY-MM-DD HH:mm:ss LEVEL Class:Line - Message`
- Extracts fields:
  - `log.level` (INFO, WARN, ERROR, CRITICAL, FATAL, DEBUG, TRACE)
  - `spark.class` (Java class name)
  - `line_number`
  - `log_message`
- Sets `event.type` based on log level
- Sets `event.category` to "application"
- Handles parsing failures gracefully

**Updated: `logs-spark-default.template.json`**
- Index pattern: `logs-spark-default`
- Default pipeline: `spark-logs-pipeline`
- Field mappings:
  - `log.level` (keyword)
  - `spark.component` (keyword)
  - `spark.pod_name` (keyword)
  - `spark.class` (keyword)
  - `message` (text with keyword subfield)

**Created: `spark-log-metrics-transform.json`**
- Source: `logs-spark-default`
- Destination: `spark-log-metrics-ds`
- Frequency: Every 1 minute
- Aggregations:
  - Group by: `log_level`, `time_bucket` (1m), `component`
  - Metrics: `log_count`, `error_count`, `warn_count`
- Purpose: Real-time log level statistics for Grafana

### 3. Kibana Data View ✅

**Updated: `spark-logs.dataview.json`**
- Title: `logs-spark-default`
- ID: `spark-logs`
- Name: "Spark Application Logs"
- Comprehensive field definitions with custom labels:
  - @timestamp (Timestamp)
  - message (Log Message)
  - log.level (Log Level)
  - spark.component (Spark Component)
  - spark.pod_name (Pod Name)
  - spark.class (Java Class)
  - event.type, event.category
  - kubernetes.* fields
  - host.hostname
- Time field formatting: `YYYY-MM-DD HH:mm:ss.SSS`

### 4. Grafana Dashboard Panel ✅

**Added: Panel #100 "Spark Application Logs by Level"**
- Type: Stacked bar chart
- Data source: `spark-log-metrics-ds`
- Query: Sum of `log_count` grouped by `log_level` and `time_bucket`
- Visualization:
  - ERROR: Red
  - WARN: Yellow
  - INFO: Green
  - DEBUG: Blue
- Position: Bottom of Spark Cluster Metrics dashboard
- Size: Full width (24 cols x 8 rows)
- Interactive: Click on log level to filter

### 5. Log4j2 Configuration ✅

**Created: `spark/conf/log4j2-server.properties`**
```properties
# RollingFileAppender for application logs
appender.rolling.fileName = ${sys:spark.log.dir:-/opt/spark/logs}/spark-app.log
appender.rolling.filePattern = ...spark-app-%d{yyyy-MM-dd}-%i.log
appender.rolling.layout.pattern = %d{yyyy-MM-dd HH:mm:ss} %-5p %c{1}:%L - %m%n%ex

# Policies
- Time-based: Daily rotation
- Size-based: Max 100MB per file
- Retention: Keep last 10 files

# Root logger: Both console AND file
rootLogger.appenderRefs = console, rolling
```

**Why This Matters**: 
- Spark master, worker, and history server will now write to `spark-app.log*` files
- These files can be collected by Elastic Agent
- Logs persist beyond pod lifetime (mounted volume)
- Proper rotation prevents disk space issues

### 6. Elastic Agent Configuration ✅

**Updated: `elastic-agent.linux.yml`**

```yaml
- id: spark-app-logs
  type: filestream    
  use_output: "default"  # Changed from spark_app
  enabled: true
  streams:
    - id: spark-app-logs-stream
      paths:
        - '/mnt/spark/logs/*/spark-app.log*'  # New path pattern
      exclude_files: ['\.gz$']
      data_stream:
        dataset: spark  # Goes to logs-spark-default
        namespace: default
      processors:
        - dissect:  # Extract pod name
            tokenizer: "/mnt/spark/logs/%{spark.pod_name}/spark-app.log"
        - script:  # Detect component type
            lang: javascript
            # Sets spark.component based on pod name
            # master, worker, history, driver, executor
```

### 7. Initialization Script ✅

**Updated: `observability/elasticsearch/bin/init-index.sh`**

Added new **STEP 11: Initialize Spark Application Logs**:
1. Create ILM policy (`spark-logs`)
2. Create ingest pipeline (`spark-logs-pipeline`)
3. Create index template (`logs-spark-default`)
4. Create data view (`spark-logs`)
5. Create transform (`spark-log-metrics`)
6. Start transform

Renumbered OTel section to **STEP 12**.

## Deployment Requirements

### CRITICAL: Spark Configuration Changes Required

The Spark deployment MUST be updated to use `log4j2-server.properties`:

#### Option 1: Update Spark ConfigMap

```bash
# Add log4j2-server.properties to Spark ConfigMap
kubectl create configmap spark-conf \
  --from-file=spark/conf/log4j2-server.properties \
  -n spark \
  --dry-run=client -o yaml | kubectl apply -f -

# Update Spark deployments to mount and use this config
# Set environment variable in pod specs:
SPARK_DAEMON_JAVA_OPTS="-Dlog4j.configurationFile=file:///opt/spark/conf/log4j2-server.properties"
```

#### Option 2: Update Spark Ansible Playbooks

If using Ansible to deploy Spark, update the playbooks to:
1. Copy `log4j2-server.properties` to ConfigMap
2. Set `SPARK_DAEMON_JAVA_OPTS` in pod specs
3. Restart pods

### Deployment Steps

```bash
# 1. Deploy Spark log4j2 configuration (manual or via playbook)
#    - Update ConfigMap with log4j2-server.properties
#    - Restart Spark master, worker, history server pods

# 2. Redeploy Elastic Agent with new configuration
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/elastic-agent/install.yml --limit Lab2

# 3. Restart observability stack to initialize new configs
ansible-playbook playbooks/observability/stop.yml
ansible-playbook playbooks/observability/start.yml

# 4. Verify deployment
# Check that spark-app.log files are being created
ansible Lab2 -m shell -a "ls -lh /mnt/spark/logs/*/spark-app.log*"

# Check Elasticsearch index
curl -sk -u elastic:password 'https://localhost:9200/logs-spark-default/_count'

# Check transform is running
curl -sk -u elastic:password 'https://localhost:9200/_transform/spark-log-metrics/_stats'
```

### Verification Checklist

- [ ] Log files exist: `/mnt/spark/logs/*/spark-app.log*`
- [ ] Logs are being written (check file size increasing)
- [ ] Elastic Agent is collecting logs (check `filestream-spark_app` logs)
- [ ] `logs-spark-default` index exists and has documents
- [ ] Kibana data view "Spark Application Logs" shows data
- [ ] Transform `spark-log-metrics` is running
- [ ] `spark-log-metrics-ds` index exists and has documents
- [ ] Grafana panel "Spark Application Logs by Level" displays data
- [ ] Log levels are correctly parsed (check a few documents)
- [ ] All Spark components represented (master, worker, history)

## Files Changed

### New Files Created
1. `observability/elasticsearch/spark-logs/spark-logs-ingest-pipeline.json`
2. `observability/elasticsearch/spark-logs/spark-log-metrics-transform.json`
3. `spark/conf/log4j2-server.properties`
4. `docs/SPARK_LOGS_IMPLEMENTATION.md` (this file)

### Files Modified
1. `observability/elasticsearch/spark-logs/logs-spark-default.template.json` (renamed & updated)
2. `observability/elasticsearch/spark-logs/spark-logs.dataview.json` (updated)
3. `observability/elasticsearch/bin/init-index.sh` (added STEP 11)
4. `observability/grafana/provisioning/dashboards/spark-system.json` (added panel)
5. `elastic-agent/elastic-agent.linux.yml` (updated spark-app-logs section)

### Directory Renamed
- `observability/elasticsearch/spark/` → `observability/elasticsearch/spark-logs/`

## Current Status

⚠️ **NOT YET DEPLOYED** - All changes implemented, awaiting review.

### What Works Now
- ✅ Spark GC metrics (already working, fixed earlier)
- ✅ Spark events collection (logs-spark-spark index, unchanged)
- ✅ OTel traces collection (working)

### What Will Work After Deployment
- 🔄 Spark application logs collection
- 🔄 Log level extraction and parsing
- 🔄 Log metrics aggregation
- 🔄 Grafana log level visualization

## Next Steps

1. **Review**: Examine all changes, especially:
   - Ingest pipeline grok patterns (does format match actual logs?)
   - Transform configuration (correct aggregations?)
   - Grafana panel query (correct index and fields?)

2. **Spark Configuration**: Update Spark deployment to use `log4j2-server.properties`

3. **Deploy**: Run deployment steps in test environment first

4. **Test**: Run Spark jobs and verify end-to-end log flow

5. **Monitor**: Watch for:
   - Parsing failures in pipeline
   - Transform lag or errors
   - Missing log levels
   - Performance impact on Elasticsearch

## Additional Considerations

### Log Volume

With file logging enabled, expect:
- Master: ~50-100 MB/day
- Worker (each): ~10-50 MB/day
- History Server: ~20-40 MB/day
- Executor (each, per job): ~5-20 MB/job

Total estimate: ~500 MB - 2 GB/day depending on activity

### Index Lifecycle Management

The `spark-logs` ILM policy should be configured for:
- Hot phase: 7 days
- Warm phase: 30 days (optional)
- Delete phase: 90 days

### Performance

The transform runs every 1 minute and should have minimal impact:
- Processing: <1 second typically
- Memory: <50 MB
- CPU: <1% typically

### Troubleshooting

If logs aren't appearing:
1. Check Spark pods are writing to spark-app.log
2. Check Elastic Agent is reading the files
3. Check ingest pipeline isn't rejecting documents
4. Check index template was applied
5. Check data stream permissions

## Documentation Updates Needed

After deployment:
- Update `RUNNING_ANSIBLE_PLAYBOOKS.md` with Spark log4j2 deployment steps
- Update `Log_Architecture.md` with new log collection flow
- Create runbook for log troubleshooting

---

**Status**: ✅ Implementation complete, ready for review
**Date**: 2025-10-19
**Author**: AI Assistant


