#!/bin/bash
# Apply ILM policies with downsampling for system metrics
# This script creates/updates ILM policies in Elasticsearch

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"

# Load variables from variables.yaml (you may want to use a proper YAML parser)
ES_HOST="${ELASTIC_HOST_CLIENT:-GaryPC.lan}"
ES_PORT="${ELASTIC_PORT:-9200}"
ES_USER="${ELASTIC_USER:-elastic}"
ES_PASSWORD="${ELASTIC_PASSWORD:-myElastic2025}"
CA_CERT="${CA_CERT_LINUX_PATH:-/etc/ssl/certs/elastic/ca.crt}"

ES_URL="https://${ES_HOST}:${ES_PORT}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Applying ILM Policies with Downsampling"
echo "=================================================="
echo ""
echo "Elasticsearch: ${ES_URL}"
echo "User: ${ES_USER}"
echo ""

# Function to apply a policy
apply_policy() {
    local policy_name=$1
    local policy_file=$2
    
    echo -n "Applying policy '${policy_name}'... "
    
    response=$(curl -s -w "\n%{http_code}" -X PUT "${ES_URL}/_ilm/policy/${policy_name}" \
        -H "Content-Type: application/json" \
        -u "${ES_USER}:${ES_PASSWORD}" \
        --cacert "${CA_CERT}" \
        -d @"${policy_file}" 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed (HTTP ${http_code})${NC}"
        echo "Response: $body"
        return 1
    fi
}

# Apply policies
echo "Applying ILM policies..."
echo ""

apply_policy "system-metrics-downsampled" "${CONFIG_DIR}/system-metrics/system-metrics.ilm.json"
apply_policy "docker-metrics-downsampled" "${CONFIG_DIR}/docker-metrics/docker-metrics.ilm.json"
apply_policy "spark-gc-downsampled" "${CONFIG_DIR}/spark-gc/spark-gc-downsampled.ilm.json"
apply_policy "spark-logs-metrics-downsampled" "${CONFIG_DIR}/spark-logs/spark-logs-metrics-downsampled.ilm.json"

echo ""
echo "=================================================="
echo "Policy Application Complete"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Apply policies to existing data streams:"
echo "   PUT metrics-system.cpu-default/_settings"
echo "   {"
echo "     \"index.lifecycle.name\": \"system-metrics-downsampled\""
echo "   }"
echo ""
echo "2. Update index templates to use the policies by default"
echo ""
echo "3. Monitor policy execution:"
echo "   GET metrics-system.cpu-default/_ilm/explain"
echo ""
echo "4. Check ILM status:"
echo "   GET _ilm/status"
echo ""
echo "For more information, see: ${SCRIPT_DIR}/../docs/README.md"
echo ""

