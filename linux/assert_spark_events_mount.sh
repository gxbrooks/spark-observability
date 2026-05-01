#!/bin/bash
#
# Backward-compatible wrapper.
# Use assert_spark_mounts.sh for full /mnt/spark mount contract.
#

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Warning : assert_spark_events_mount.sh is deprecated; delegating to assert_spark_mounts.sh"
exec "$dir/assert_spark_mounts.sh" "$@"

