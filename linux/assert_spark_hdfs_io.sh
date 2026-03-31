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

TARGET_HDFS="${HDFS_DEFAULT_FS_CLIENT:-${HDFS_DEFAULT_FS:-hdfs://Lab2.lan:30900}}"
echo "[assert] HDFS IO test target: ${TARGET_HDFS}"

"${PYTHON_BIN}" - <<'PY'
from pyspark.sql import SparkSession
import os
import time

base = os.environ.get("HDFS_DEFAULT_FS_CLIENT") or os.environ.get("HDFS_DEFAULT_FS") or "hdfs://Lab2.lan:30900"
target = f"{base}/spark/assert_hdfs_io_{int(time.time())}"

builder = SparkSession.builder.appName("assert-spark-hdfs-io")
master = os.environ.get("SPARK_MASTER_URL") or os.environ.get("SPARK_MASTER")
if master:
    builder = builder.master(master)
driver = os.environ.get("SPARK_DRIVER_HOST")
if driver:
    builder = builder.config("spark.driver.host", driver)

spark = builder.getOrCreate()
spark.sparkContext.setLogLevel("ERROR")

df = spark.range(50).withColumnRenamed("id", "n")
df.write.mode("overwrite").parquet(target)
check = spark.read.parquet(target).count()
if check != 50:
    raise SystemExit(f"unexpected read count: {check}")
print(f"ASSERT_SPARK_HDFS_IO_OK path={target} count=50")
spark.stop()
PY

echo "[assert] HDFS IO test passed"
