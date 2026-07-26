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
# SVG exports use --svg-theme light and post-processing so HTML browsers and
# asciidoctor-pdf (prawn-svg / Okular) both render labels without the draw.io
# "Text is not SVG - cannot display" Extensibility fallback.
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
# Force light theme so adaptive light-dark() colors are not emitted (PDF-safe).
if [[ "$FORMAT" == "svg" ]]; then
    DRAWIO_EXTRA+=(--svg-theme light)
fi

# Post-process SVG for HTML + asciidoctor-pdf/prawn-svg:
# - opaque white page background (unless --transparent)
# - brace-aware @supports / light-dark cleanup (naive [^}]* left orphan "}")
# - fill="transparent" → fill="none" (prawn-svg paints transparent as black)
# - strip draw.io's Extensibility footer ("Text is not SVG - cannot display");
#   per-label <switch> PNG fallbacks remain for PDF text
harden_svg_for_pdf() {
    local dest="$1"
    [[ "$FORMAT" == "svg" ]] || return 0
    [[ -f "$dest" ]] || return 0

    python3 - "$dest" "$TRANSPARENT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
transparent = sys.argv[2] == "1"
text = path.read_text(encoding="utf-8")


def replace_light_dark(s: str) -> str:
    """Replace CSS/SVG light-dark(light, dark) with the light value (PDF-safe)."""
    out = []
    i = 0
    while True:
        j = s.find("light-dark(", i)
        if j < 0:
            out.append(s[i:])
            break
        out.append(s[i:j])
        start = j + len("light-dark(")
        depth = 1
        k = start
        while k < len(s) and depth:
            if s[k] == "(":
                depth += 1
            elif s[k] == ")":
                depth -= 1
            k += 1
        inner = s[start : k - 1]
        split_at = None
        d = 0
        for idx, ch in enumerate(inner):
            if ch == "(":
                d += 1
            elif ch == ")":
                d -= 1
            elif ch == "," and d == 0:
                split_at = idx
                break
        light = inner[:split_at].strip() if split_at is not None else inner.strip()
        out.append(light)
        i = k
    return "".join(out)


def remove_at_supports(s: str) -> str:
    """Remove @supports { ... } blocks with nested-brace awareness."""
    out = []
    i = 0
    while True:
        j = s.find("@supports", i)
        if j < 0:
            out.append(s[i:])
            break
        out.append(s[i:j])
        brace = s.find("{", j)
        if brace < 0:
            out.append(s[j:])
            break
        depth = 1
        k = brace + 1
        while k < len(s) and depth:
            if s[k] == "{":
                depth += 1
            elif s[k] == "}":
                depth -= 1
            k += 1
        i = k
    return "".join(out)


def strip_empty_style_blocks(s: str) -> str:
    """Drop <style> blocks left empty after @supports / light-dark cleanup."""
    return re.sub(
        r"<style\b[^>]*>\s*</style>",
        "",
        s,
        flags=re.IGNORECASE,
    )


def strip_drawio_extensibility_warning(s: str) -> str:
    """Remove draw.io footer shown when foreignObject/Extensibility is unsupported."""
    return re.sub(
        r'<switch>\s*'
        r'<g\s+requiredFeatures="http://www\.w3\.org/TR/SVG11/feature#Extensibility"\s*/>\s*'
        r"<a\b[^>]*>\s*"
        r"<text\b[^>]*>Text is not SVG - cannot display</text>\s*"
        r"</a>\s*"
        r"</switch>",
        "",
        s,
        count=1,
        flags=re.IGNORECASE | re.DOTALL,
    )


text = replace_light_dark(text)
text = re.sub(r"\s*color-scheme:\s*light dark;?", "", text)
text = remove_at_supports(text)
text = strip_empty_style_blocks(text)
text = strip_drawio_extensibility_warning(text)
# prawn-svg treats fill="transparent" as opaque black; mxgraph.basic.rect
# exports a full-size transparent overlay that blacks out header fills in PDF.
text = text.replace('fill="transparent"', 'fill="none"')
text = re.sub(r"fill:\s*transparent", "fill: none", text)

if transparent:
    path.write_text(text, encoding="utf-8")
    sys.exit(0)

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
    path.write_text(text, encoding="utf-8")
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

    harden_svg_for_pdf "$dest"

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
