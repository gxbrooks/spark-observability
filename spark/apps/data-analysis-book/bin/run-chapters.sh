#!/bin/bash
#
# Run Spark chapter files (client mode).
#
# Usage:
#   ./bin/run-chapters.sh 03 04 06 07
#   ./bin/run-chapters.sh 3 10          # numbers are zero-padded
#   ./bin/run-chapters.sh -a            # all Chapter_*.py under ../chapters
#   ./bin/run-chapters.sh -t 900 10     # kill Chapter_10.py after 900s
#   ./bin/run-chapters.sh --no-timeout 10
#
# Parallel stress (distinct SPARK_DRIVER_INSTANCE per thread):
#   ./bin/run-stress.sh -p 4 -i 3
#   ./bin/run-stress.sh --parallel 2 --iteration 1 08 09
#
# Client log layout (node-local, not NFS; separate from Cluster /mnt/spark/logs/<pod>/):
#   /mnt/spark/client-logs/<instance>/spark-app.log
#   <instance> = SPARK_DRIVER_INSTANCE if set, else this shell's PID ($$)
# Override either SPARK_LOG_DIR (full path) or SPARK_DRIVER_INSTANCE (instance label).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHAPTERS_DIR="${APP_DIR}/chapters"
ROOT_DIR="$(cd "${APP_DIR}/../../.." && pwd)"

usage() {
    echo "Usage: $0 <chapter_number> [chapter_number ...]" >&2
    echo "       $0 -a|--all" >&2
    echo "       $0 -t|--timeout <seconds> <chapter_number> [chapter_number ...]" >&2
    echo "       $0 --no-timeout <chapter_number> [chapter_number ...]" >&2
    echo "Example: $0 03 04 06 07 08 09" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

SPARK_CLIENT_ENV_FILE="${ROOT_DIR}/vars/contexts/spark_client_env.sh"
if [ -f "${SPARK_CLIENT_ENV_FILE}" ]; then
    source "${SPARK_CLIENT_ENV_FILE}"
    if [ -n "${HDFS_DEFAULT_FS_CLIENT:-}" ]; then
        export HDFS_DEFAULT_FS="${HDFS_DEFAULT_FS_CLIENT}"
    fi
else
    echo "Error: spark_client_env.sh not found at ${SPARK_CLIENT_ENV_FILE}" >&2
    echo "Please run: python3 ${ROOT_DIR}/vars/generate_contexts.py -f" >&2
    exit 1
fi

if [ -z "${SPARK_MASTER_URL:-}" ] && [ -n "${SPARK_MASTER_HOST:-}" ] && [ -n "${SPARK_MASTER_PORT:-}" ]; then
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
fi

_spark_client_root="/mnt/spark/client-logs"
if [ -n "${SPARK_DRIVER_INSTANCE:-}" ]; then
    _spark_driver_instance="$(printf '%s' "${SPARK_DRIVER_INSTANCE}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\+/-/g;s/^-//;s/-$//')"
    [ -n "${_spark_driver_instance}" ] || _spark_driver_instance="$$"
else
    _spark_driver_instance="$$"
fi
export SPARK_DRIVER_INSTANCE="${_spark_driver_instance}"
export SPARK_LOG_DIR="${SPARK_LOG_DIR:-${_spark_client_root}/${_spark_driver_instance}}"
if ! mkdir -p "${SPARK_LOG_DIR}" 2>/dev/null; then
    echo "Warning: could not create SPARK_LOG_DIR=${SPARK_LOG_DIR}" >&2
fi
chmod 755 "${_spark_client_root}" 2>/dev/null || true
chmod 755 "${SPARK_LOG_DIR}" 2>/dev/null || true
echo "SPARK_LOG_DIR=${SPARK_LOG_DIR} (instance=${_spark_driver_instance})"

if [[ "${PYSPARK_SUBMIT_ARGS:-}" != *"log4j2.configurationFile"* ]]; then
    _log4j_cfg="file://${SPARK_CONF_DIR}/log4j2-client.properties"
    export PYSPARK_SUBMIT_ARGS="--conf spark.driver.extraJavaOptions=-Dlog4j2.configurationFile=${_log4j_cfg} ${PYSPARK_SUBMIT_ARGS}"
fi

if [ -n "${SPARK_MASTER_URL:-}" ]; then
    if [[ "${PYSPARK_SUBMIT_ARGS:-}" == *"--master"* ]]; then
        export PYSPARK_SUBMIT_ARGS="${PYSPARK_SUBMIT_ARGS:-pyspark-shell}"
    else
        export PYSPARK_SUBMIT_ARGS="--master ${SPARK_MASTER_URL} ${PYSPARK_SUBMIT_ARGS:-pyspark-shell}"
    fi
fi

PROJECT_VENV_PYTHON="${ROOT_DIR}/venv/bin/python3"
if [ -f "${PROJECT_VENV_PYTHON}" ]; then
    PYTHON_CMD="${PROJECT_VENV_PYTHON}"
elif [ -n "${VIRTUAL_ENV:-}" ] && [ -f "${VIRTUAL_ENV}/bin/python3" ]; then
    PYTHON_CMD="${VIRTUAL_ENV}/bin/python3"
elif [ -n "${PYSPARK_PYTHON:-}" ] && command -v "${PYSPARK_PYTHON}" >/dev/null 2>&1; then
    PYTHON_CMD="${PYSPARK_PYTHON}"
else
    PYTHON_CMD="python3"
fi

if [[ ! -d /opt/spark/logs ]] && command -v sudo >/dev/null 2>&1; then
    sudo -n mkdir -p /opt/spark/logs 2>/dev/null && sudo -n chmod 1777 /opt/spark/logs 2>/dev/null || true
fi

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

ALL_CHAPTERS=false
CHAPTER_ARGS=()
CHAPTER_TIMEOUT_SECONDS="${CHAPTER_TIMEOUT_SECONDS:-1800}"
CHAPTER_TIMEOUT_ENABLED=true

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)
            ALL_CHAPTERS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -t|--timeout)
            if [ $# -lt 2 ]; then
                echo "Error: --timeout requires a numeric value in seconds." >&2
                usage
                exit 1
            fi
            CHAPTER_TIMEOUT_SECONDS="$2"
            if ! [[ "${CHAPTER_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [ "${CHAPTER_TIMEOUT_SECONDS}" -le 0 ]; then
                echo "Error: --timeout must be a positive integer (seconds)." >&2
                exit 1
            fi
            shift 2
            ;;
        --no-timeout)
            CHAPTER_TIMEOUT_ENABLED=false
            shift
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

if [ "${ALL_CHAPTERS}" = true ]; then
    CHAPTER_ARGS=()
    while IFS= read -r chapter_num; do
        [ -n "${chapter_num}" ] && CHAPTER_ARGS+=("${chapter_num}")
    done < <(discover_all_chapters)
else
    _normalized=()
    for chapter_num in "${CHAPTER_ARGS[@]+"${CHAPTER_ARGS[@]}"}"; do
        _normalized+=("$(normalize_chapter "${chapter_num}")")
    done
    CHAPTER_ARGS=("${_normalized[@]+"${_normalized[@]}"}")
fi

if [ ${#CHAPTER_ARGS[@]} -eq 0 ]; then
    echo "Error: No chapter files specified or discovered." >&2
    usage
    exit 1
fi

TIMINGS_CSV="${APP_DIR}/chapter-timings.csv"
COMMIT_ID="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
RUN_DATE="$(date -Iseconds)"

if [ ! -f "${TIMINGS_CSV}" ]; then
    echo "date,commit,chapter,status,elapsed_s" > "${TIMINGS_CSV}"
fi

for chapter_num in "${CHAPTER_ARGS[@]}"; do
    chapter_file="${CHAPTERS_DIR}/Chapter_${chapter_num}.py"

    if [ ! -f "${chapter_file}" ]; then
        echo "Warning: Chapter file not found: ${chapter_file}" >&2
        echo "${RUN_DATE},${COMMIT_ID},${chapter_num},NOT_FOUND,0" >> "${TIMINGS_CSV}"
        continue
    fi

    echo ""
    echo "========================================"
    echo "Running Chapter_${chapter_num}.py"
    echo "Using Python: ${PYTHON_CMD}"
    if [ "${CHAPTER_TIMEOUT_ENABLED}" = true ]; then
        echo "Timeout: ${CHAPTER_TIMEOUT_SECONDS}s"
    else
        echo "Timeout: disabled"
    fi
    echo "========================================"

    start_epoch=$(date +%s)
    if [ "${CHAPTER_TIMEOUT_ENABLED}" = true ] && command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=30s "${CHAPTER_TIMEOUT_SECONDS}" "${PYTHON_CMD}" "${chapter_file}"
    else
        "${PYTHON_CMD}" "${chapter_file}"
    fi
    exit_code=$?
    end_epoch=$(date +%s)
    elapsed=$(( end_epoch - start_epoch ))

    if [ $exit_code -eq 0 ]; then
        status="OK"
        echo "✅ Completed Chapter_${chapter_num}.py  (${elapsed}s)"
    elif [ $exit_code -eq 124 ]; then
        status="TIMEOUT(${CHAPTER_TIMEOUT_SECONDS}s)"
        echo "⏱️ Chapter_${chapter_num}.py timed out after ${CHAPTER_TIMEOUT_SECONDS}s  (${elapsed}s)" >&2
    else
        status="FAIL(${exit_code})"
        echo "❌ Chapter_${chapter_num}.py failed with exit code $exit_code  (${elapsed}s)" >&2
    fi

    echo "${RUN_DATE},${COMMIT_ID},${chapter_num},${status},${elapsed}" >> "${TIMINGS_CSV}"
    echo ""
done

echo "========================================"
echo "Timings written to ${TIMINGS_CSV}"
echo "========================================"
