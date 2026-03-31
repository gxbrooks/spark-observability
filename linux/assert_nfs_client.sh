#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/vars/contexts/spark_client_env.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "FAIL nfs: missing ${ENV_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

SPARK_DATA_MOUNT="${SPARK_DATA_MOUNT:-/mnt/spark/data}"
fail=0

if ! mountpoint -q "${SPARK_DATA_MOUNT}"; then
  echo "WARN nfs: ${SPARK_DATA_MOUNT} not mounted; attempting mount -a"
  sudo -n mount -a >/dev/null 2>&1 || true
fi

if mountpoint -q "${SPARK_DATA_MOUNT}"; then
  echo "PASS nfs: mount present ${SPARK_DATA_MOUNT}"
else
  echo "FAIL nfs: mount missing ${SPARK_DATA_MOUNT}"
  fail=1
fi

if [[ -d "${SPARK_DATA_MOUNT}" ]] && touch "${SPARK_DATA_MOUNT}/.assert_write_test.$$" 2>/dev/null; then
  rm -f "${SPARK_DATA_MOUNT}/.assert_write_test.$$"
  echo "PASS nfs: writable ${SPARK_DATA_MOUNT}"
else
  echo "WARN nfs: not writable as $(id -un); attempting spark-group fix"
  sudo -n chgrp -R spark "${SPARK_DATA_MOUNT}" >/dev/null 2>&1 || true
  sudo -n chmod -R g+rwX "${SPARK_DATA_MOUNT}" >/dev/null 2>&1 || true
  if touch "${SPARK_DATA_MOUNT}/.assert_write_test.$$" 2>/dev/null; then
    rm -f "${SPARK_DATA_MOUNT}/.assert_write_test.$$"
    echo "PASS nfs: writable after fix ${SPARK_DATA_MOUNT}"
  else
    echo "WARN nfs: still not writable ${SPARK_DATA_MOUNT} (non-fatal in shell sanity mode)"
  fi
fi

if [[ -d "${SPARK_DATA_MOUNT}/gutenberg_books" ]] && ls "${SPARK_DATA_MOUNT}/gutenberg_books/"*.txt >/dev/null 2>&1; then
  echo "PASS nfs: gutenberg_books has txt files"
else
  echo "FAIL nfs: gutenberg_books missing or empty"
  fail=1
fi

[[ "${fail}" -eq 0 ]]
