#!/bin/bash
# Export draw.io (.drawio) sources to SVG/PNG for AsciiDoc image:: inclusion.
#
# Usage:
#   export-drawio.sh path/to/diagram.drawio [svg|png|pdf]
#   export-drawio.sh path/to/docs/dir          # export all *.drawio under dir
#
# Requires Docker (draw.io desktop headless) OR draw.io desktop CLI on PATH.
set -euo pipefail

FORMAT="${2:-svg}"
IMAGE="${DRAWIO_DOCKER_IMAGE:-rlespinasse/drawio-desktop-headless:minimal}"

export_one() {
    local src="$1"
    local out_dir
    out_dir="$(dirname "$src")/figures"
    mkdir -p "$out_dir"
    local base
    base="$(basename "$src" .drawio)"
    local dest="${out_dir}/${base}.${FORMAT}"

    if command -v drawio >/dev/null 2>&1; then
        drawio -x -f "$FORMAT" -o "$dest" "$src"
    elif command -v docker >/dev/null 2>&1; then
        docker run --rm \
            -u "$(id -u):$(id -g)" \
            -v "$(dirname "$(readlink -f "$src")"):/data" \
            -w /data \
            "$IMAGE" \
            -x -f "$FORMAT" -o "figures/${base}.${FORMAT}" "$(basename "$src")"
    else
        echo "Error   : install draw.io desktop (drawio CLI) or Docker image ${IMAGE}" >&2
        exit 1
    fi
    echo "Info    : ${src} → ${dest}"
}

if [[ $# -lt 1 ]]; then
    echo "Usage   : export-drawio.sh <file.drawio|directory> [svg|png|pdf]" >&2
    exit 1
fi

TARGET="$(readlink -f "$1")"
if [[ -d "$TARGET" ]]; then
    mapfile -t files < <(find "$TARGET" -name '*.drawio' -type f | sort)
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
