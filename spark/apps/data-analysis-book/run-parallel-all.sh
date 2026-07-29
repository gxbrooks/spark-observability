#!/bin/bash
# Run full chapter suite in two parallel batches with distinct client log instance dirs.
# Layout: /mnt/spark/logs/spark-client/<SPARK_DRIVER_INSTANCE>/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${1:-/tmp/chapter-run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "${LOG}"
echo "${LOG}" > /tmp/latest-chapter-run-dir.txt

echo "LOG=${LOG}"

SPARK_DRIVER_INSTANCE=par-a "${SCRIPT_DIR}/run-chapters.sh" 03 04 05 06 >"${LOG}/par-a.log" 2>&1 &
pid_a=$!
SPARK_DRIVER_INSTANCE=par-b "${SCRIPT_DIR}/run-chapters.sh" 07 08 09 10 >"${LOG}/par-b.log" 2>&1 &
pid_b=$!

echo "Started par-a pid=${pid_a}, par-b pid=${pid_b}"
wait "${pid_a}" "${pid_b}" || true

echo "=== par-a ==="
rg '✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-a.log" || true
echo "=== par-b ==="
rg '✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-b.log" || true
