#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/vars/contexts/spark_client_env.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "FAIL env: missing ${ENV_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

fail=0
for v in SPARK_MASTER_HOST SPARK_DRIVER_HOST HDFS_DEFAULT_FS_CLIENT; do
  if [[ -z "${!v:-}" ]]; then
    echo "FAIL env: ${v} is not set"
    fail=1
  else
    echo "PASS env: ${v}=${!v}"
  fi
done

resolve_host() {
  local h="$1" label="$2"
  if getent hosts "${h}" >/dev/null 2>&1; then
    echo "PASS env: ${label} resolves (${h})"
  else
    echo "FAIL env: ${label} does not resolve (${h})"
    fail=1
  fi
}

resolve_host "${SPARK_MASTER_HOST:-}" "SPARK_MASTER_HOST"
resolve_host "${SPARK_DRIVER_HOST:-}" "SPARK_DRIVER_HOST"

hdfs_host="$(echo "${HDFS_DEFAULT_FS_CLIENT:-hdfs://Lab2.lan:30900}" | sed -E 's#hdfs://([^:/]+):?([0-9]+)?.*#\1#')"
resolve_host "${hdfs_host}" "HDFS_DEFAULT_FS_CLIENT host"

[[ "${fail}" -eq 0 ]]
