#!/bin/bash
# AsciiDoc extension PDF export wrapper — always loads asciidoctor-diagram (local Graphviz).
set -euo pipefail
if ! command -v asciidoctor-pdf >/dev/null 2>&1; then
    echo "Error   : asciidoctor-pdf not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi
if ! gem list -i asciidoctor-diagram >/dev/null 2>&1; then
    echo "Error   : gem asciidoctor-diagram not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi
exec asciidoctor-pdf -r asciidoctor-diagram "$@"
