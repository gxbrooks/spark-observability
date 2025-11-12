#!/bin/bash
# Attach downsampling ILM policies to existing data streams
# Run this AFTER apply-ilm-policies.sh or after init-index.sh

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Attaching Downsampling Policies to Data Streams"
echo "=================================================="
echo ""

# Add current directory to PATH for esapi script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="${PATH}:${SCRIPT_DIR}"

# Function to attach policy to a data stream
attach_policy() {
    local data_stream=$1
    local policy_name=$2
    
    echo -n "Attaching '${policy_name}' to '${data_stream}'... "
    
    # Check if data stream exists first
    if ! esapi --allow-errors GET "/_data_stream/${data_stream}" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Data stream does not exist yet (will use policy when created)${NC}"
        return 0
    fi
    
    # Attach policy
    if esapi PUT "${data_stream}/_settings" -d "{\"index.lifecycle.name\":\"${policy_name}\"}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

# System metrics
echo -e "${BLUE}System Metrics Data Streams:${NC}"
attach_policy "metrics-system.cpu-default" "system-metrics-downsampled"
attach_policy "metrics-system.memory-default" "system-metrics-downsampled"
attach_policy "metrics-system.network-default" "system-metrics-downsampled"
attach_policy "metrics-system.diskio-default" "system-metrics-downsampled"
attach_policy "metrics-system.load-default" "system-metrics-downsampled"
echo ""

# Docker metrics
echo -e "${BLUE}Docker Metrics Data Streams:${NC}"
attach_policy "metrics-docker.cpu-default" "docker-metrics-downsampled"
attach_policy "metrics-docker.memory-default" "docker-metrics-downsampled"
attach_policy "metrics-docker.network-default" "docker-metrics-downsampled"
echo ""

# Spark GC
echo -e "${BLUE}Spark GC Data Stream:${NC}"
attach_policy "logs-spark_gc-default" "spark-gc-downsampled"
echo ""

# Spark log metrics
echo -e "${BLUE}Spark Log Metrics Data Stream:${NC}"
attach_policy "metrics-spark-logs-default" "spark-logs-metrics-downsampled"
echo ""

echo "=================================================="
echo "Policy Attachment Complete"
echo "=================================================="
echo ""
echo "Verification commands:"
echo "  esapi GET 'metrics-system.cpu-default/_ilm/explain'"
echo "  esapi GET 'metrics-docker.cpu-default/_ilm/explain'"
echo "  esapi GET 'logs-spark_gc-default/_ilm/explain'"
echo "  esapi GET 'metrics-spark-logs-default/_ilm/explain'"
echo ""
echo "Monitor downsampling (after 2+ days):"
echo "  esapi GET '_cat/indices/.ds-*downsample*?v'"
echo ""

