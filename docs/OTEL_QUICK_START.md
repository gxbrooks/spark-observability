# OpenTelemetry Traces - Quick Start Guide

## Prerequisites

- Spark 4.0.1 deployed in Kubernetes ✅
- PySpark 4.0.1 in project venv ✅
- OTel Collector running in observability namespace ✅
- Elasticsearch accessible at GaryPC.lan:9200 ✅

## Run Spark with Traces (3 Steps)

### Step 1: Set Environment
```bash
cd /home/gxbrooks/repos/elastic-on-spark
source venv/bin/activate
source vars/contexts/spark-client/spark_env.sh
export OTEL_EXPORTER_OTLP_ENDPOINT="http://Lab2.lan:31317"
```

### Step 2: Create Spark Session with OTel
```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName('Your Application Name') \
    .config('spark.extraListeners', 'com.elastic.spark.otel.OTelSparkListener') \
    .config('spark.jars', '/home/gxbrooks/repos/elastic-on-spark/spark/otel-listener/target/spark-otel-listener-1.0.0.jar') \
    .getOrCreate()

# Your Spark code here
df = spark.range(1000)
df.count()

spark.stop()
```

### Step 3: View Traces in Kibana
1. Open: http://GaryPC.lan:5601
2. Go to: **Discover**
3. Select: **OpenTelemetry Traces** data view
4. Filter: `Name: "spark.application*"` to see your apps

## Quick Verification

```bash
# Check trace count
curl -k -u elastic:myElastic2025 "https://GaryPC.lan:9200/traces-generic-default/_count"

# See recent applications
curl -k -u elastic:myElastic2025 -s \
  "https://GaryPC.lan:9200/traces-generic-default/_search?q=spark.application*&size=5" \
  | python3 -m json.tool | grep "spark.app.name"
```

## Current Status

- **Index:** traces-generic-default
- **Spans:** 62+ (growing with each job)
- **Applications Traced:** 6+
- **Data View:** OpenTelemetry Traces ✅

## Example Output

```
Application: Chapter 03: Pride and Prejudice Analysis
├── Job 0 (1.41ms)
│   └── Stage 0 (1.40ms) - Word extraction
├── Job 1 (0.16ms)
│   ├── Stage 2 (0.15ms) - Lowercase conversion
│   └── Stage 3 (0.18ms) - Cleaning
└── Job 2 (0.18ms)
    └── Stage 4 (varies) - Group & count
```

## Troubleshooting

**No traces appearing?**
1. Verify OTel endpoint: `echo $OTEL_EXPORTER_OTLP_ENDPOINT`
2. Check collector: `kubectl get pods -n observability -l app=otel-collector`
3. Confirm JAR path is correct in `.config('spark.jars', ...)`

**See docs/OTEL_TRACES_WORKING.md for complete details.**
