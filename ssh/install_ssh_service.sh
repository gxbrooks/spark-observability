#!/usr/bin/env bash
# Delegates to assert_ssh_server.sh (single implementation for install/configure SSH).

set -euo pipefail
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_script_dir/assert_ssh_server.sh" "$@"
