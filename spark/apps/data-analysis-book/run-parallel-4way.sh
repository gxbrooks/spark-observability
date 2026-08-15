#!/bin/bash
# Run the full chapter suite in four parallel threads with distinct client log dirs.
# Layout: /mnt/spark/client-logs/<SPARK_DRIVER_INSTANCE>/
#
# Each thread runs all chapters (03–10), N times. N is the number of full-suite
# iterations per thread (not a chapter-split scheme).
#
# Usage:
#   ./run-parallel-4way.sh [LOG_DIR] [N]
#   N=3 ./run-parallel-4way.sh
#
# Outputs:
#   ${LOG}/par-a.log … ${LOG}/par-d.log
#   ${LOG}/thread-durations.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${1:-/tmp/chapter-run-4way-$(date +%Y%m%d-%H%M%S)}"
N="${2:-${N:-1}}"

if ! [[ "${N}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: N must be a positive integer (got '${N}')" >&2
  exit 1
fi

mkdir -p "${LOG}"
echo "${LOG}" > /tmp/latest-chapter-run-dir.txt

ALL_CHAPTERS=(03 04 05 06 07 08 09 10)

echo "LOG=${LOG}"
echo "N=${N} (each thread runs all chapters N times)"
echo "Chapters: ${ALL_CHAPTERS[*]}"
echo "Threads: 4 (par-a, par-b, par-c, par-d)"

run_batch() {
  local instance="$1"
  local batch_label="$2"
  shift 2
  local batch_start batch_end batch_elapsed
  batch_start="$(date +%s)"
  echo "===== ${instance} ${batch_label} start $(date -Iseconds) chapters: $* ====="
  set +e
  SPARK_DRIVER_INSTANCE="${instance}" "${SCRIPT_DIR}/run-chapters.sh" "$@"
  local rc=$?
  set -e
  batch_end="$(date +%s)"
  batch_elapsed=$((batch_end - batch_start))
  echo "===== ${instance} ${batch_label} end rc=${rc} elapsed_s=${batch_elapsed} ====="
  return 0
}

run_thread() {
  local instance="$1"
  local thread_start thread_end thread_elapsed iter
  thread_start="$(date +%s)"
  echo "THREAD_START instance=${instance} epoch=${thread_start} $(date -Iseconds)"

  for ((iter = 1; iter <= N; iter++)); do
    run_batch "${instance}" "iter=${iter}/${N} all-chapters" "${ALL_CHAPTERS[@]}"
  done

  thread_end="$(date +%s)"
  thread_elapsed=$((thread_end - thread_start))
  echo "THREAD_END instance=${instance} epoch=${thread_end} $(date -Iseconds)"
  echo "THREAD_DURATION_SECONDS=${thread_elapsed} instance=${instance}"
  printf '%s\n' "${instance} ${thread_elapsed}" > "${LOG}/${instance}.duration"
}

run_thread par-a >"${LOG}/par-a.log" 2>&1 &
pid_a=$!
run_thread par-b >"${LOG}/par-b.log" 2>&1 &
pid_b=$!
run_thread par-c >"${LOG}/par-c.log" 2>&1 &
pid_c=$!
run_thread par-d >"${LOG}/par-d.log" 2>&1 &
pid_d=$!

echo "Started par-a pid=${pid_a}, par-b pid=${pid_b}, par-c pid=${pid_c}, par-d pid=${pid_d}"
wait "${pid_a}" "${pid_b}" "${pid_c}" "${pid_d}" || true

: > "${LOG}/thread-durations.txt"
for f in "${LOG}/par-a.duration" "${LOG}/par-b.duration" "${LOG}/par-c.duration" "${LOG}/par-d.duration"; do
  [ -f "${f}" ] && cat "${f}" >> "${LOG}/thread-durations.txt"
done

echo ""
echo "=== thread durations (seconds) ==="
if [ -s "${LOG}/thread-durations.txt" ]; then
  while read -r name secs; do
    printf '  %s: %ss (%dm%02ds)\n' "${name}" "${secs}" "$((secs / 60))" "$((secs % 60))"
  done < "${LOG}/thread-durations.txt"
else
  echo "  (none recorded — threads may have failed before THREAD_END)"
fi

echo ""
echo "=== par-a ==="
rg 'THREAD_|=====|✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-a.log" || true
echo "=== par-b ==="
rg 'THREAD_|=====|✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-b.log" || true
echo "=== par-c ==="
rg 'THREAD_|=====|✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-c.log" || true
echo "=== par-d ==="
rg 'THREAD_|=====|✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/par-d.log" || true
echo ""
echo "Full logs: ${LOG}/par-a.log ${LOG}/par-b.log ${LOG}/par-c.log ${LOG}/par-d.log"
echo "Durations: ${LOG}/thread-durations.txt"
