#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "FAIL kubeconfig: kubectl not installed"
  exit 1
fi

KCFG="${KUBECONFIG:-$HOME/.kube/config}"
if [[ ! -r "${KCFG}" ]]; then
  echo "FAIL kubeconfig: missing or unreadable ${KCFG}"
  exit 1
fi

if kubectl --kubeconfig "${KCFG}" cluster-info >/dev/null 2>&1; then
  echo "PASS kubeconfig: cluster-info reachable"
  exit 0
fi

echo "FAIL kubeconfig: kubectl cluster-info failed"
exit 1
