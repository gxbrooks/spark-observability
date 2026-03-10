#!/bin/bash
# Convenience script to verify the local development environment is ready
# Context files are used directly from vars/contexts/ -- no copying required

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "🔧 Checking local development environment..."
echo ""

# Check if vars/contexts exists
if [ ! -d "vars/contexts" ]; then
    echo "❌ Error: vars/contexts/ directory not found"
    echo "   Run: python3 vars/generate_contexts.py -f"
    exit 1
fi

# Verify key context files exist
MISSING=0
for ctx_file in \
    "vars/contexts/observability_docker.env" \
    "vars/contexts/devops_env.sh" \
    "vars/contexts/spark_client_env.sh"; do
    if [ -f "${ctx_file}" ]; then
        echo "✅ ${ctx_file}"
    else
        echo "❌ Missing: ${ctx_file}"
        MISSING=1
    fi
done

if [ "${MISSING}" -eq 1 ]; then
    echo ""
    echo "⚠️  Some context files are missing. Regenerate with:"
    echo "   bash vars/generate_contexts.sh -f"
    exit 1
fi

echo ""
echo "✅ Local development environment ready!"
echo ""
echo "Next steps:"
echo "  - Start observability: docker compose --env-file vars/contexts/observability_docker.env -f observability/docker-compose.yml up -d"
echo "  - Source env files:    source vars/contexts/devops_env.sh"
echo "  - Run Spark apps:      source vars/contexts/spark_client_env.sh"

