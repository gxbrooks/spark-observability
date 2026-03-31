#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "${ROOT_DIR}/vars/contexts/spark_client_env.sh" ]]; then
  echo "spark_client_env.sh not found; run: python3 ${ROOT_DIR}/vars/generate_contexts.py -f" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${ROOT_DIR}/vars/contexts/spark_client_env.sh"

PYTHON_BIN="${ROOT_DIR}/venv/bin/python3"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "venv python not found at ${PYTHON_BIN}" >&2
  exit 1
fi

echo "[assert] Spark runtime smoke test starting"
"${PYTHON_BIN}" - <<'PY'
from pyspark.sql import SparkSession
import os

builder = SparkSession.builder.appName("assert-spark-runtime-smoke")
master = os.environ.get("SPARK_MASTER_URL") or os.environ.get("SPARK_MASTER")
if master:
    builder = builder.master(master)
driver = os.environ.get("SPARK_DRIVER_HOST")
if driver:
    builder = builder.config("spark.driver.host", driver)
spark = builder.getOrCreate()
spark.sparkContext.setLogLevel("ERROR")
count = spark.range(1000).count()
if count != 1000:
    raise SystemExit(f"unexpected count: {count}")
print("ASSERT_SPARK_RUNTIME_OK count=1000")
spark.stop()
PY

echo "[assert] Spark runtime smoke test passed"
