#!/usr/bin/env bash
# Stable entry point for the Dynatrace Terraform provider's built-in
# export/import-state utility (see terraform/README.md and the
# terraform_ansible_learnings.md tmp doc for what -export/-ref/-import-state
# actually do and why -ref matters for cross-environment portability).
#
# Exists so a Claude Code Bash permission rule can target one fixed path
# instead of the provider's version-pinned binary under
# .terraform/providers/.../<version>/linux_amd64/ -- that path changes
# every time the provider version bumps (a lock file update), which would
# silently break a permission rule written against today's version number.
#
# Usage: DYNATRACE_ENV_URL=... DT_API_TOKEN=... DYNATRACE_TARGET_FOLDER=... \
#        terraform/scripts/dt-export.sh -export -ref -id -flat [-import-state] <resource-type>...
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BIN=$(find .terraform/providers -type f -name 'terraform-provider-dynatrace_*' 2>/dev/null | head -n1)
if [[ -z "$BIN" ]]; then
  echo "No terraform-provider-dynatrace binary found under .terraform/providers -- run 'terraform init' first." >&2
  exit 1
fi

exec "$BIN" "$@"
