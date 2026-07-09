#!/bin/bash
#
# Wait for chapter driver processes to finish.
#
# Usage:
#   ./wait-chapters.sh              # poll until no run-chapters/Chapter_*.py under this dir
#   ./wait-chapters.sh <pid> [...]  # wait on explicit background PIDs (preferred for parallel runs)
#
# Do NOT use: while ps ... | rg 'run-chapters.sh'
# That pattern matches the monitoring shell's own argv and never exits.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${CHAPTER_WAIT_INTERVAL_SECONDS:-10}"

wait_pid() {
    local pid="$1"
    if ! kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi
    echo "Waiting for PID ${pid}..."
    while kill -0 "${pid}" 2>/dev/null; do
        sleep "${INTERVAL}"
    done
}

chapter_process_lines() {
    # Anchor on this directory so generic shell one-liners mentioning run-chapters.sh are ignored.
    pgrep -af "${SCRIPT_DIR}/run-chapters\\.sh" 2>/dev/null || true
    pgrep -af "${SCRIPT_DIR}/Chapter_[0-9]+\\.py" 2>/dev/null || true
}

chapter_processes_running() {
    local line pid cmd
    while IFS= read -r line; do
        [ -z "${line}" ] && continue
        pid="${line%% *}"
        cmd="${line#${pid} }"
        [ "${pid}" = "$$" ] && continue
        case "${cmd}" in
            *wait-chapters.sh*) continue ;;
        esac
        return 0
    done < <(chapter_process_lines)
    return 1
}

if [ "$#" -gt 0 ]; then
    for pid; do
        wait_pid "${pid}"
    done
    echo "All specified PIDs finished."
    exit 0
fi

echo "Polling for chapter drivers under ${SCRIPT_DIR} (every ${INTERVAL}s)..."
while chapter_processes_running; do
    sleep "${INTERVAL}"
done
echo "All chapter drivers finished."
