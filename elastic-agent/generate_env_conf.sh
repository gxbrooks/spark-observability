#!/bin/bash
#
# Generate env.conf from template using elastic_agent_env.sh variables
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the environment variables
if [ -f "$SCRIPT_DIR/elastic_agent_env.sh" ]; then
    source "$SCRIPT_DIR/elastic_agent_env.sh"
else
    echo "Error: elastic_agent_env.sh not found"
    echo "Run: python3 linux/generate_env.py elastic-agent"
    exit 1
fi

# Read template and substitute variables
envsubst < "$SCRIPT_DIR/env.conf.template" > "$SCRIPT_DIR/env.conf"

echo "Generated env.conf from template using elastic_agent_env.sh variables"
echo "  ELASTIC_HOST_EXTERNAL: $ELASTIC_HOST_EXTERNAL"
echo "  ELASTIC_URL_EXTERNAL: $ELASTIC_URL_EXTERNAL"
echo "  LS_HOST_EXTERNAL: $LS_HOST_EXTERNAL"
