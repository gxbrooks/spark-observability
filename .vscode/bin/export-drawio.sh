#!/bin/bash
# Export draw.io (.drawio) sources to SVG/PNG for AsciiDoc image:: inclusion.
#
# Usage:
#   export-drawio.sh [-t|--transparent] path/to/diagram.drawio [svg|png|pdf]
#   export-drawio.sh [-t|--transparent] path/to/docs/dir [svg|png|pdf]
#
# Flags:
#   -t, --transparent
#       Pass draw.io's -t/--transparent through (PNG transparent background).
#       For SVG, draw.io always emits a transparent page background; omitting
#       this flag post-processes the SVG to a solid white background instead.
#
# Prefers the local draw.io desktop CLI (drawio) over Docker when both exist.
# Requires Docker (draw.io desktop headless) OR draw.io desktop CLI on PATH.
set -euo pipefail

TRANSPARENT=0
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--transparent)
            TRANSPARENT=1
            shift
            ;;
        -h|--help)
            echo "Usage   : export-drawio.sh [-t|--transparent] <file.drawio|directory> [svg|png|pdf]"
            exit 0
            ;;
        -*)
            echo "Error   : unknown option: $1" >&2
            echo "Usage   : export-drawio.sh [-t|--transparent] <file.drawio|directory> [svg|png|pdf]" >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -lt 1 ]]; then
    echo "Usage   : export-drawio.sh [-t|--transparent] <file.drawio|directory> [svg|png|pdf]" >&2
    exit 1
fi

TARGET_ARG="${POSITIONAL[0]}"
FORMAT="${POSITIONAL[1]:-svg}"
IMAGE="${DRAWIO_DOCKER_IMAGE:-rlespinasse/drawio-desktop-headless:minimal}"

DRAWIO_EXTRA=()
if [[ "$TRANSPARENT" -eq 1 ]]; then
    DRAWIO_EXTRA+=(-t)
fi

# draw.io leaves SVG page backgrounds transparent even without -t. CSS background on
# <svg> is ignored by many viewers (browser img, VS Code, PDF), so inject a full-bleed
# white <rect> unless the caller requested --transparent.
ensure_svg_opaque_background() {
    local dest="$1"
    [[ "$FORMAT" == "svg" ]] || return 0
    [[ "$TRANSPARENT" -eq 0 ]] || return 0
    [[ -f "$dest" ]] || return 0

    python3 - "$dest" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Prefer CSS opaque style when present (harmless; some renderers honor it).
text, _ = re.subn(
    r"background:\s*transparent;\s*background-color:\s*transparent",
    "background: #ffffff; background-color: #ffffff",
    text,
    count=1,
)

# Idempotent: skip if we already injected a page background rect.
if 'id="export-drawio-page-bg"' in text:
    path.write_text(text, encoding="utf-8")
    sys.exit(0)

m = re.search(r"<svg\b[^>]*>", text)
if not m:
    print(f"Warning : no <svg> root in {path}", file=sys.stderr)
    sys.exit(0)

svg_tag = m.group(0)
vb = re.search(r'\bviewBox="([^"]+)"', svg_tag)
if vb:
    parts = vb.group(1).split()
    if len(parts) == 4:
        x, y, w, h = parts
    else:
        x, y, w, h = "0", "0", "100%", "100%"
else:
    x, y = "0", "0"
    wm = re.search(r'\bwidth="([0-9.]+)(?:px)?"', svg_tag)
    hm = re.search(r'\bheight="([0-9.]+)(?:px)?"', svg_tag)
    w = wm.group(1) if wm else "100%"
    h = hm.group(1) if hm else "100%"

rect = (
    f'<rect id="export-drawio-page-bg" x="{x}" y="{y}" width="{w}" height="{h}" '
    f'fill="#ffffff" stroke="none"/>'
)
# Insert immediately after the opening <svg ...> tag.
text = text[: m.end()] + rect + text[m.end() :]
path.write_text(text, encoding="utf-8")
PY
}

export_one() {
    local src="$1"
    local out_dir
    out_dir="$(dirname "$src")/images"
    mkdir -p "$out_dir"
    local base
    base="$(basename "$src" .drawio)"
    local dest="${out_dir}/${base}.${FORMAT}"

    rm -f "$dest"

    if command -v drawio >/dev/null 2>&1; then
        echo "Info    : exporter=drawio-cli"
        drawio -x -f "$FORMAT" "${DRAWIO_EXTRA[@]}" -o "$dest" "$src"
    elif command -v docker >/dev/null 2>&1; then
        echo "Info    : exporter=docker (${IMAGE})"
        docker run --rm \
            -u "$(id -u):$(id -g)" \
            -v "$(dirname "$(readlink -f "$src")"):/data" \
            -w /data \
            "$IMAGE" \
            -x -f "$FORMAT" "${DRAWIO_EXTRA[@]}" -o "images/${base}.${FORMAT}" "$(basename "$src")"
    else
        echo "Error   : install draw.io desktop (drawio CLI) or Docker image ${IMAGE}" >&2
        exit 1
    fi

    if [[ ! -s "$dest" ]]; then
        echo "Error   : export produced empty or missing file: ${dest}" >&2
        exit 1
    fi

    ensure_svg_opaque_background "$dest"

    if [[ "$TRANSPARENT" -eq 1 ]]; then
        echo "Info    : background=transparent (-t)"
    else
        echo "Info    : background=opaque"
    fi
    echo "Info    : source mtime=$(stat -c '%y' "$src" 2>/dev/null || stat -f '%Sm' "$src")"
    echo "Info    : ${src} → ${dest}"
}

TARGET="$(readlink -f "$TARGET_ARG")"
if [[ -d "$TARGET" ]]; then
    # Only peer .drawio files in the document directory (not deprecated figures/ subtrees).
    mapfile -t files < <(find "$TARGET" -maxdepth 1 -name '*.drawio' -type f | sort)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "Info    : no .drawio files under ${TARGET}"
        exit 0
    fi
    for f in "${files[@]}"; do
        export_one "$f"
    done
else
    export_one "$TARGET"
fi

echo "Result  : draw.io export complete (${FORMAT})"
