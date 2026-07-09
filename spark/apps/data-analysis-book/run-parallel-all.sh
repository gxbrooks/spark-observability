#!/bin/bash
# Run full chapter suite in two sequential batches (shared hostname log dir on one host).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${1:-/tmp/chapter-run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${LOG}"
echo "${LOG}" > /tmp/latest-chapter-run-dir.txt

echo "LOG=${LOG}"

"${SCRIPT_DIR}/run-chapters.sh" 03 04 05 06 >"${LOG}/par-a.log" 2>&1
"${SCRIPT_DIR}/run-chapters.sh" 07 08 09 10 >"${LOG}/par-b.log" 2>&1

echo "=== par-a ==="
rg '✅|❌|⏱️' "${LOG}/par-a.log" || true
echo "=== par-b ==="
rg '✅|❌|⏱️' "${LOG}/par-b.log" || true
