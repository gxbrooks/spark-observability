#!/bin/bash
# AsciiDoc extension PDF export wrapper — always loads asciidoctor-diagram (local Graphviz)
# and Rouge for colored source listings (highlight.js does not apply to PDF).
set -euo pipefail
if ! command -v asciidoctor-pdf >/dev/null 2>&1; then
    echo "Error   : asciidoctor-pdf not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi
if ! gem list -i asciidoctor-diagram >/dev/null 2>&1; then
    echo "Error   : gem asciidoctor-diagram not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi
if ! gem list -i rouge >/dev/null 2>&1; then
    echo "Error   : gem rouge not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi
exec asciidoctor-pdf -r asciidoctor-diagram -a source-highlighter=rouge "$@"
