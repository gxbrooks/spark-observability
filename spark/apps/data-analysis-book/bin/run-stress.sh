#!/bin/bash
# Run the chapter suite in N parallel threads with distinct client log dirs.
# Layout: /mnt/spark/client-logs/<SPARK_DRIVER_INSTANCE>/
#
# Each thread runs the selected chapters, --iteration times, back to back.
# --parallel is how many copies of run-chapters.sh to start at once.
#
# Usage:
#   ./bin/run-stress.sh [-p N] [-i N] [--log-dir DIR] [-a] [chapter ...]
#   ./bin/run-stress.sh --parallel 4 --iteration 3
#   ./bin/run-stress.sh -p 2 -i 1 08 09
#
# Defaults: -p 1 -i 1, all chapters under ../chapters if none listed.
#
# Outputs:
#   ${LOG}/<instance>.log
#   ${LOG}/thread-durations.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHAPTERS_DIR="${APP_DIR}/chapters"
RUN_CHAPTERS="${SCRIPT_DIR}/run-chapters.sh"

usage() {
  echo "Usage: $0 [--parallel|-p N] [--iteration|-i N] [--log-dir DIR] [-a] [chapter ...]" >&2
  echo "       $0 --parallel 4 --iteration 3" >&2
  echo "       $0 -p 2 -i 1 03 04 08" >&2
}

normalize_chapter() {
  local n="$1"
  n="${n#Chapter_}"
  n="${n%.py}"
  if [[ "${n}" =~ ^[0-9]+$ ]]; then
    printf '%02d' "$((10#${n}))"
  else
    printf '%s' "${n}"
  fi
}

discover_all_chapters() {
  local chapter_path chapter_name chapter_num
  for chapter_path in "${CHAPTERS_DIR}"/Chapter_*.py; do
    if [ ! -f "${chapter_path}" ]; then
      continue
    fi
    chapter_name="$(basename "${chapter_path}")"
    chapter_num="${chapter_name#Chapter_}"
    chapter_num="${chapter_num%.py}"
    echo "${chapter_num}"
  done | sort -V
}

instance_name() {
  local n="$1"
  local letters=({a..z})
  if [ "${n}" -ge 1 ] && [ "${n}" -le 26 ]; then
    printf 'par-%s' "${letters[$((n - 1))]}"
  else
    printf 'par-%02d' "${n}"
  fi
}

PARALLEL=1
ITERATIONS=1
LOG=""
ALL_CHAPTERS=false
CHAPTER_ARGS=()
FORWARD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--parallel|--paralle)
      if [ $# -lt 2 ]; then
        echo "Error: --parallel requires a positive integer." >&2
        usage
        exit 1
      fi
      PARALLEL="$2"
      shift 2
      ;;
    -i|--iteration|--iterations)
      if [ $# -lt 2 ]; then
        echo "Error: --iteration requires a positive integer." >&2
        usage
        exit 1
      fi
      ITERATIONS="$2"
      shift 2
      ;;
    --log-dir)
      if [ $# -lt 2 ]; then
        echo "Error: --log-dir requires a path." >&2
        usage
        exit 1
      fi
      LOG="$2"
      shift 2
      ;;
    -a|--all)
      ALL_CHAPTERS=true
      shift
      ;;
    -t|--timeout)
      if [ $# -lt 2 ]; then
        echo "Error: --timeout requires a numeric value in seconds." >&2
        usage
        exit 1
      fi
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --no-timeout)
      FORWARD_ARGS+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        CHAPTER_ARGS+=("$1")
        shift
      done
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      CHAPTER_ARGS+=("$1")
      shift
      ;;
  esac
done

if ! [[ "${PARALLEL}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --parallel must be a positive integer (got '${PARALLEL}')" >&2
  exit 1
fi
if ! [[ "${ITERATIONS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --iteration must be a positive integer (got '${ITERATIONS}')" >&2
  exit 1
fi

if [ "${ALL_CHAPTERS}" = true ] || [ ${#CHAPTER_ARGS[@]} -eq 0 ]; then
  CHAPTER_ARGS=()
  while IFS= read -r chapter_num; do
    [ -n "${chapter_num}" ] && CHAPTER_ARGS+=("${chapter_num}")
  done < <(discover_all_chapters)
else
  _normalized=()
  for chapter_num in "${CHAPTER_ARGS[@]}"; do
    _normalized+=("$(normalize_chapter "${chapter_num}")")
  done
  CHAPTER_ARGS=("${_normalized[@]}")
fi

if [ ${#CHAPTER_ARGS[@]} -eq 0 ]; then
  echo "Error: No chapter files specified or discovered in ${CHAPTERS_DIR}." >&2
  usage
  exit 1
fi

if [ -z "${LOG}" ]; then
  LOG="/tmp/chapter-run-p${PARALLEL}-i${ITERATIONS}-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "${LOG}"
echo "${LOG}" > /tmp/latest-chapter-run-dir.txt

INSTANCES=()
for ((n = 1; n <= PARALLEL; n++)); do
  INSTANCES+=("$(instance_name "${n}")")
done

echo "LOG=${LOG}"
echo "parallel=${PARALLEL} iteration=${ITERATIONS}"
echo "Chapters: ${CHAPTER_ARGS[*]}"
echo "Threads: ${INSTANCES[*]}"

run_batch() {
  local instance="$1"
  local batch_label="$2"
  shift 2
  local batch_start batch_end batch_elapsed rc
  batch_start="$(date +%s)"
  echo "===== ${instance} ${batch_label} start $(date -Iseconds) chapters: $* ====="
  set +e
  SPARK_DRIVER_INSTANCE="${instance}" "${RUN_CHAPTERS}" "${FORWARD_ARGS[@]}" "$@"
  rc=$?
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

  for ((iter = 1; iter <= ITERATIONS; iter++)); do
    run_batch "${instance}" "iter=${iter}/${ITERATIONS}" "${CHAPTER_ARGS[@]}"
  done

  thread_end="$(date +%s)"
  thread_elapsed=$((thread_end - thread_start))
  echo "THREAD_END instance=${instance} epoch=${thread_end} $(date -Iseconds)"
  echo "THREAD_DURATION_SECONDS=${thread_elapsed} instance=${instance}"
  printf '%s\n' "${instance} ${thread_elapsed}" > "${LOG}/${instance}.duration"
}

PIDS=()
for instance in "${INSTANCES[@]}"; do
  run_thread "${instance}" >"${LOG}/${instance}.log" 2>&1 &
  PIDS+=("$!")
done

started_msg="Started"
for idx in "${!INSTANCES[@]}"; do
  started_msg="${started_msg} ${INSTANCES[$idx]} pid=${PIDS[$idx]},"
done
echo "${started_msg%,}"

wait "${PIDS[@]}" || true

: > "${LOG}/thread-durations.txt"
for instance in "${INSTANCES[@]}"; do
  if [ -f "${LOG}/${instance}.duration" ]; then
    cat "${LOG}/${instance}.duration" >> "${LOG}/thread-durations.txt"
  fi
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
for instance in "${INSTANCES[@]}"; do
  echo "=== ${instance} ==="
  grep -E 'THREAD_|=====|✅|❌|⏱️|SPARK_LOG_DIR=' "${LOG}/${instance}.log" || true
done
echo ""
echo "Full logs: ${LOG}/"
echo "Durations: ${LOG}/thread-durations.txt"
