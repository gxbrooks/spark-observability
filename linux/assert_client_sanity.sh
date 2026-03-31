#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

checks=(
  "assert_client_reachability.sh"
  "assert_client_kubeconfig.sh"
  "assert_nfs_client.sh"
  "assert_spark_client_env.sh"
)

pass=0
fail=0
declare -a failed_checks=()

for c in "${checks[@]}"; do
  script="${ROOT_DIR}/linux/${c}"
  if [[ ! -x "${script}" ]]; then
    echo "FAIL ${c}: script missing or not executable"
    fail=$((fail+1))
    failed_checks+=("${c} (missing)")
    continue
  fi
  if "${script}"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    failed_checks+=("${c}")
  fi
done

echo "------------------------------------------------------------"
echo "Client Sanity Summary: pass=${pass} fail=${fail}"
if [[ "${fail}" -gt 0 ]]; then
  echo "Failed checks:"
  for f in "${failed_checks[@]}"; do
    echo "  - ${f}"
  done
  echo "Remediation:"
  echo "  - Re-run: ./linux/assert_client_node.sh"
  echo "  - Re-run this check: ./linux/assert_client_sanity.sh"
  echo "  - Verify playbooks: cd ansible && ansible-playbook -i inventory.yml playbooks/diagnose.yml"
  exit 1
fi

echo "All client sanity checks passed."
