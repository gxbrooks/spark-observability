#!/bin/bash
#
# Run Spark Chapter Files
#
# Usage: ./run-chapters.sh 03 04 06 07 08 09
#        ./run-chapters.sh 03        # Run single chapter

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source spark_client_env.sh
SPARK_CLIENT_ENV_FILE="${ROOT_DIR}/vars/contexts/spark_client_env.sh"
if [ -f "${SPARK_CLIENT_ENV_FILE}" ]; then
    source "${SPARK_CLIENT_ENV_FILE}"
    # Align default FS with NodePort URL so PySpark/Hadoop on the host do not use in-cluster DNS (hdfs-namenode).
    if [ -n "${HDFS_DEFAULT_FS_CLIENT:-}" ]; then
        export HDFS_DEFAULT_FS="${HDFS_DEFAULT_FS_CLIENT}"
    fi
else
    echo "Error: spark_client_env.sh not found at ${SPARK_CLIENT_ENV_FILE}" >&2
    echo "Please run: python3 ${ROOT_DIR}/vars/generate_contexts.py -f" >&2
    exit 1
fi

# Ensure chapter scripts run against the Spark cluster in client mode.
if [ -z "${SPARK_MASTER_URL:-}" ] && [ -n "${SPARK_MASTER_HOST:-}" ] && [ -n "${SPARK_MASTER_PORT:-}" ]; then
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
fi

# Preserve existing submit args (e.g. spark.ui.enabled=false) and prepend cluster master.
if [ -n "${SPARK_MASTER_URL:-}" ]; then
    if [[ "${PYSPARK_SUBMIT_ARGS:-}" == *"--master"* ]]; then
        export PYSPARK_SUBMIT_ARGS="${PYSPARK_SUBMIT_ARGS:-pyspark-shell}"
    else
        export PYSPARK_SUBMIT_ARGS="--master ${SPARK_MASTER_URL} ${PYSPARK_SUBMIT_ARGS:-pyspark-shell}"
    fi
fi

# Determine which Python to use - prioritize venv Python from project root
# This is where Spark 4.0 compatible Python packages (including PySpark) are installed
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

# Spark 4.x UI analytics (DiskLog) prefers /opt/spark/logs; create it when passwordless sudo allows (avoids one startup WARN).
if [[ ! -d /opt/spark/logs ]] && command -v sudo >/dev/null 2>&1; then
    sudo -n mkdir -p /opt/spark/logs 2>/dev/null && sudo -n chmod 1777 /opt/spark/logs 2>/dev/null || true
fi

# Check if chapter numbers were provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <chapter_number> [chapter_number ...]" >&2
    echo "Example: $0 03 04 06 07 08 09" >&2
    exit 1
fi

TIMINGS_CSV="${SCRIPT_DIR}/chapter-timings.csv"
COMMIT_ID="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
RUN_DATE="$(date -Iseconds)"

if [ ! -f "${TIMINGS_CSV}" ]; then
    echo "date,commit,chapter,status,elapsed_s" > "${TIMINGS_CSV}"
fi

# Run each chapter file
for chapter_num in "$@"; do
    chapter_file="${SCRIPT_DIR}/Chapter_${chapter_num}.py"
    
    if [ ! -f "${chapter_file}" ]; then
        echo "Warning: Chapter file not found: ${chapter_file}" >&2
        echo "${RUN_DATE},${COMMIT_ID},${chapter_num},NOT_FOUND,0" >> "${TIMINGS_CSV}"
        continue
    fi
    
    echo ""
    echo "========================================"
    echo "Running Chapter_${chapter_num}.py"
    echo "Using Python: ${PYTHON_CMD}"
    echo "========================================"
    
    start_epoch=$(date +%s)
    "${PYTHON_CMD}" "${chapter_file}"
    exit_code=$?
    end_epoch=$(date +%s)
    elapsed=$(( end_epoch - start_epoch ))

    if [ $exit_code -eq 0 ]; then
        status="OK"
        echo "✅ Completed Chapter_${chapter_num}.py  (${elapsed}s)"
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

