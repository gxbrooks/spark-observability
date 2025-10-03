#!/bin/bash

# Spark Logging Architecture Verification Script
# Run this after restarting Elastic Agent to verify all components are working

echo "🔍 Spark Logging Architecture Verification"
echo "=========================================="

# Check if Elasticsearch is accessible
echo -n "📊 Checking Elasticsearch connectivity... "
if curl -k -u elastic:myElastic2025 -s "https://localhost:9200" > /dev/null 2>&1; then
    echo "✅ Connected"
else
    echo "❌ Cannot connect to Elasticsearch"
    exit 1
fi

# Check master GC logs
echo -n "🎯 Checking Master GC logs... "
if ls /mnt/spark/logs/spark_spark-master-*/master-gc.log > /dev/null 2>&1; then
    MASTER_SIZE=$(ls -la /mnt/spark/logs/spark_spark-master-*/master-gc.log | awk '{print $5}' | head -1)
    echo "✅ Found (${MASTER_SIZE} bytes)"
else
    echo "❌ No master GC logs found"
fi

# Check worker GC logs
echo -n "👷 Checking Worker GC logs... "
if kubectl exec spark-worker-lab2-75fb765875-sswsp -n spark -- ls /mnt/spark/logs/spark_spark-worker-*/worker-gc.log > /dev/null 2>&1; then
    echo "✅ Found"
else
    echo "❌ No worker GC logs found"
fi

# Check history server GC logs
echo -n "📚 Checking History Server GC logs... "
if ls /mnt/spark/logs/spark_spark-history-*/history-gc.log > /dev/null 2>&1; then
    echo "✅ Found"
else
    echo "❌ No history server GC logs found"
fi

# Check executor GC logs
echo -n "⚡ Checking Executor GC logs... "
if ls /mnt/spark/logs/executor-gc-*.log* > /dev/null 2>&1; then
    EXECUTOR_COUNT=$(ls /mnt/spark/logs/executor-gc-*.log* | wc -l)
    echo "✅ Found (${EXECUTOR_COUNT} files)"
else
    echo "❌ No executor GC logs found"
fi

# Check Elasticsearch for new metadata fields
echo -n "🏷️  Checking for metadata fields in Elasticsearch... "
RECENT_LOG=$(curl -k -u elastic:myElastic2025 -s "https://localhost:9200/.ds-logs-spark-*/_search?size=1&sort=@timestamp:desc&_source=spark.metadata" 2>/dev/null)
if echo "$RECENT_LOG" | grep -q "spark.metadata"; then
    echo "✅ Metadata fields found"
else
    echo "⚠️  No metadata fields found (may need Elastic Agent restart)"
fi

# Check for recent GC pause events
echo -n "⏱️  Checking for recent GC events... "
if grep -q "Pause" /mnt/spark/logs/spark_spark-master-*/master-gc.log 2>/dev/null; then
    echo "✅ GC pause events found"
else
    echo "❌ No GC pause events found"
fi

echo ""
echo "🎉 Verification complete!"
echo ""
echo "Next steps:"
echo "1. Run: sudo systemctl restart elastic-agent"
echo "2. Wait 2-3 minutes for logs to be processed"
echo "3. Check Kibana for new metadata fields"
echo "4. Run this script again to verify metadata is working"
