#!/bin/bash
# Convenience script to set up local development environment
# Copies generated files from vars/contexts/ to their required locations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "🔧 Setting up local development environment..."
echo ""

# Check if vars/contexts exists
if [ ! -d "vars/contexts" ]; then
    echo "❌ Error: vars/contexts/ directory not found"
    echo "   Run: python3 vars/generate_contexts.py -f"
    exit 1
fi

# Copy observability .env file
if [ -f "vars/contexts/observability_docker.env" ]; then
    if [ ! -f "observability/.env" ] || [ "vars/contexts/observability_docker.env" -nt "observability/.env" ]; then
        cp "vars/contexts/observability_docker.env" "observability/.env"
        echo "✅ Copied observability/.env"
    else
        echo "ℹ️  observability/.env already up to date"
    fi
else
    echo "⚠️  Warning: vars/contexts/observability_docker.env not found"
    echo "   Run: bash vars/generate_contexts.sh -f observability"
fi

echo ""
echo "✅ Local development environment ready!"
echo ""
echo "Next steps:"
echo "  - Start observability: cd observability && docker compose up -d"
echo "  - Source env files: source vars/contexts/devops/devops_env.sh"
echo "  - Run Spark apps: source vars/contexts/spark_client_env.sh"

