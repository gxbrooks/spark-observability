#!/bin/bash
# Render any .adoc file to HTML + PDF with local Graphviz (asciidoctor-diagram).
# Usage: render-adoc.sh path/to/document.adoc
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage   : render-adoc.sh path/to/document.adoc" >&2
    exit 1
fi

adoc="$(readlink -f "$1")"
if [[ ! -f "$adoc" ]]; then
    echo "Error   : not found: $adoc" >&2
    exit 1
fi

for cmd in asciidoctor asciidoctor-pdf dot; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error   : '$cmd' not found. Run: ~/repos/myenv/assert_myenv.sh" >&2
        exit 1
    fi
done

if ! gem list -i asciidoctor-diagram >/dev/null 2>&1 \
    || ! gem list -i asciidoctor-pdf >/dev/null 2>&1; then
    echo "Error   : gems asciidoctor-diagram and asciidoctor-pdf required. Run: ~/repos/myenv/assert_myenv.sh" >&2
    exit 1
fi

dir="$(dirname "$adoc")"
base="$(basename "$adoc" .adoc)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"

if [[ -x "${script_dir}/export-drawio.sh" ]]; then
    "${script_dir}/export-drawio.sh" "$dir" svg
fi

echo "Info    : HTML  → ${dir}/${base}.html"
asciidoctor -r asciidoctor-diagram "$adoc" -o "${base}.html"

# asciidoctor-diagram HTML path does not always merge docinfo/docinfo.html; inject listing CSS explicitly.
_docinfo_css="${dir}/docinfo/docinfo.html"
if [[ -f "${_docinfo_css}" && -f "${base}.html" ]]; then
    python3 - <<'PY' "${base}.html" "${_docinfo_css}"
import pathlib, sys
html_path, docinfo_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")
snippet = docinfo_path.read_text(encoding="utf-8")
if snippet.strip() and snippet.strip() not in html:
    html = html.replace("</head>", snippet + "\n</head>", 1)
    html_path.write_text(html, encoding="utf-8")
PY
fi

echo "Info    : PDF   → ${dir}/${base}.pdf"
_theme="${dir}/../styles/problem-to-incident-theme.yml"
asciidoctor-pdf -r asciidoctor-diagram \
  -a listing-font-size=8 \
  -a "pdf-theme=${_theme}" \
  "$adoc" -o "${base}.pdf"

echo "Result  : Render complete"
