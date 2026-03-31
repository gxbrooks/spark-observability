#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[test] Running assert_client_node in check mode"
"${ROOT_DIR}/linux/assert_client_node.sh" -c "$@"
echo "[test] Running runtime sanity asserts"
"${ROOT_DIR}/linux/assert_client_sanity.sh"
echo "[test] Client node test passed"
