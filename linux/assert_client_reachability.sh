#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/vars/contexts/spark_client_env.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "FAIL reachability: missing ${ENV_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

pass=0
fail=0

check_tcp() {
  local host="$1" port="$2" label="$3"
  if nc -z -w2 "${host}" "${port}" >/dev/null 2>&1; then
    echo "PASS ${label} ${host}:${port}"
    pass=$((pass+1))
  else
    echo "FAIL ${label} ${host}:${port}"
    fail=$((fail+1))
  fi
}

for required in KUBERNETES_API_SERVER SPARK_MASTER_HOST HDFS_DEFAULT_FS_CLIENT NFS_SERVER ES_HOST SPARK_MASTER_PORT ES_PORT; do
  if [[ -z "${!required:-}" ]]; then
    echo "FAIL reachability: required variable ${required} is not set in ${ENV_FILE}"
    exit 1
  fi
done

api_host="${KUBERNETES_API_SERVER}"
spark_host="${SPARK_MASTER_HOST}"
hdfs_host="$(echo "${HDFS_DEFAULT_FS_CLIENT}" | sed -E 's#hdfs://([^:/]+):?([0-9]+)?.*#\1#')"
hdfs_port="$(echo "${HDFS_DEFAULT_FS_CLIENT}" | sed -E 's#hdfs://[^:/]+:([0-9]+).*#\1#')"
[[ -n "${hdfs_port}" ]] || hdfs_port=30900
nfs_host="${NFS_SERVER}"
es_host="${ES_HOST}"

check_tcp "${api_host}" 6443 "k8s-api"
check_tcp "${spark_host}" "${SPARK_MASTER_PORT}" "spark-master"
check_tcp "${hdfs_host}" "${hdfs_port}" "hdfs-namenode"
check_tcp "${nfs_host}" 2049 "nfs"
check_tcp "${es_host}" "${ES_PORT}" "elasticsearch"

echo "SUMMARY reachability pass=${pass} fail=${fail}"
[[ "${fail}" -eq 0 ]]
