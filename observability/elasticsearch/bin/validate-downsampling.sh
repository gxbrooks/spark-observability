#!/bin/bash
# Validate downsampling configuration and data
# This script checks ILM policies, data streams, and downsampled indices

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Load variables from vars/variables.yaml
# Source the appropriate environment file first
if [[ -z "$ES_HOST" ]]; then
    echo "Error: ES_HOST not set. Source the appropriate environment file." >&2
    exit 1
fi
if [[ -z "$ES_PORT" ]]; then
    echo "Error: ES_PORT not set. Source the appropriate environment file." >&2
    exit 1
fi
if [[ -z "$ES_USER" ]]; then
    echo "Error: ES_USER not set. Source the appropriate environment file." >&2
    exit 1
fi
if [[ -z "$ES_PASSWORD" ]]; then
    echo "Error: ES_PASSWORD not set. Source the appropriate environment file." >&2
    exit 1
fi
if [[ -z "$CA_CERT_LINUX_PATH" ]]; then
    echo "Error: CA_CERT_LINUX_PATH not set. Source the appropriate environment file." >&2
    exit 1
fi
CA_CERT="$CA_CERT_LINUX_PATH"
ES_URL="https://${ES_HOST}:${ES_PORT}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Validating Downsampling Configuration"
echo "=================================================="
echo ""

# Function to execute curl and check response
es_get() {
    local endpoint=$1
    curl -s -X GET "${ES_URL}${endpoint}" \
        -H "Content-Type: application/json" \
        -u "${ES_USER}:${ES_PASSWORD}" \
        --cacert "${CA_CERT}" 2>/dev/null
}

# Check ILM status
echo -e "${BLUE}Checking ILM Status...${NC}"
ilm_status=$(es_get "/_ilm/status" | jq -r '.operation_mode')
if [ "$ilm_status" == "RUNNING" ]; then
    echo -e "${GREEN}✓ ILM is running${NC}"
else
    echo -e "${RED}✗ ILM is not running (status: $ilm_status)${NC}"
fi
echo ""

# Check if policies exist
echo -e "${BLUE}Checking ILM Policies...${NC}"
policies=("system-metrics-downsampled" "docker-metrics-downsampled" "spark-gc-downsampled" "spark-logs-metrics-downsampled")

for policy in "${policies[@]}"; do
    result=$(es_get "/_ilm/policy/${policy}")
    if echo "$result" | jq -e ".${policy}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Policy '${policy}' exists${NC}"
        # Check if downsampling is configured
        downsample_count=$(echo "$result" | jq "[.${policy}.policy.phases | to_entries[] | .value.actions.downsample] | length")
        if [ "$downsample_count" -gt 0 ]; then
            echo -e "  ${GREEN}→ Downsampling configured in ${downsample_count} phase(s)${NC}"
        else
            echo -e "  ${YELLOW}→ Warning: No downsampling configured${NC}"
        fi
    else
        echo -e "${RED}✗ Policy '${policy}' not found${NC}"
    fi
done
echo ""

# Check data streams
echo -e "${BLUE}Checking Data Streams...${NC}"
data_streams=("metrics-system.cpu-default" "metrics-system.memory-default" "metrics-system.network-default" 
              "metrics-system.diskio-default" "metrics-system.load-default" "metrics-docker.cpu-default"
              "metrics-docker.memory-default" "metrics-docker.network-default" "logs-spark_gc-default"
              "metrics-spark-logs-default")

for ds in "${data_streams[@]}"; do
    result=$(es_get "/_data_stream/${ds}")
    if echo "$result" | jq -e ".data_streams[0]" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Data stream '${ds}' exists${NC}"
        
        # Check ILM policy association
        ilm_policy=$(es_get "/${ds}/_settings" | jq -r 'to_entries[0].value.settings.index.lifecycle.name // "none"')
        if [ "$ilm_policy" != "none" ] && [ "$ilm_policy" != "null" ]; then
            echo -e "  ${GREEN}→ ILM policy: ${ilm_policy}${NC}"
        else
            echo -e "  ${YELLOW}→ Warning: No ILM policy attached${NC}"
        fi
        
        # Check backing indices
        backing_indices=$(echo "$result" | jq -r '.data_streams[0].indices | length')
        echo -e "  → Backing indices: ${backing_indices}"
    else
        echo -e "${YELLOW}⚠ Data stream '${ds}' not found (may not have data yet)${NC}"
    fi
done
echo ""

# Check for downsampled indices
echo -e "${BLUE}Checking for Downsampled Indices...${NC}"
downsampled=$(es_get "/_cat/indices/.ds-*downsample*?format=json")
if [ "$(echo "$downsampled" | jq '. | length')" -gt 0 ]; then
    echo -e "${GREEN}Found downsampled indices:${NC}"
    echo "$downsampled" | jq -r '.[] | "\(.index) - \(.docs.count) docs, \(.store.size)"' | while read line; do
        echo "  → $line"
    done
else
    echo -e "${YELLOW}⚠ No downsampled indices found yet (data may be too recent)${NC}"
fi
echo ""

# Check ILM explain for sample data streams
echo -e "${BLUE}Checking ILM Execution Status...${NC}"
sample_streams=("metrics-system.cpu-default" "metrics-docker.cpu-default")

for ds in "${sample_streams[@]}"; do
    explain=$(es_get "/${ds}/_ilm/explain")
    if echo "$explain" | jq -e '.indices' > /dev/null 2>&1; then
        echo -e "${BLUE}Data stream: ${ds}${NC}"
        echo "$explain" | jq -r '.indices | to_entries[0] | 
            "  Index: \(.key)\n  Phase: \(.value.phase)\n  Action: \(.value.action // "none")\n  Step: \(.value.step // "none")"'
        
        # Check for errors
        error=$(echo "$explain" | jq -r '.indices | to_entries[0].value.step_info.error // "none"')
        if [ "$error" != "none" ]; then
            echo -e "${RED}  ✗ Error: ${error}${NC}"
        fi
    fi
    echo ""
done

# Check retention settings from vars/variables.yaml
echo -e "${BLUE}Expected Retention Configuration (from vars/variables.yaml):${NC}"
echo "  Base (30s sampling):   2 days  (Hot tier)"
echo "  5-minute downsampled:  4 days  (Warm tier, cumulative)"
echo "  15-minute downsampled: 8 days  (Cold tier, cumulative)"
echo "  60-minute downsampled: 12 days (Frozen tier, cumulative)"
echo ""

# Summary
echo "=================================================="
echo "Validation Complete"
echo "=================================================="
echo ""
echo "Next steps if issues found:"
echo "1. Apply ILM policies: ./apply-ilm-policies.sh"
echo "2. Attach policies to data streams (see README.md)"
echo "3. Wait for ILM to execute (check min_age in policies)"
echo "4. Monitor with: watch -n 60 'curl -s -u ${ES_USER}:${ES_PASSWORD} --cacert ${CA_CERT} ${ES_URL}/_ilm/status'"
echo ""

