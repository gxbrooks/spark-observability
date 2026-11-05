#!/usr/bin/env python3
"""Extract a fenced code block from markdown and render syntax-highlighted PNG.

Uses VS Code Dark+–like colors (turquoise keys, pink scalar values, gray background).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from pygments import highlight
from pygments.formatters import ImageFormatter
from pygments.lexers import YamlLexer
from pygments.style import Style
from pygments.token import Token


class VSCodeDarkPlusYaml(Style):
    """Approximate VS Code Dark+ YAML code-block colors."""

    background_color = "#1e1e1e"
    default_style = "#d4d4d4"

    styles = {
        Token.Text: "#d4d4d4",
        Token.Punctuation: "#d4d4d4",
        Token.Name.Tag: "#9cdcfe",
        Token.Literal.Scalar.Plain: "#ce9178",
        Token.Literal.String: "#ce9178",
        Token.Keyword: "#569cd6",
        Token.Comment: "#6a9955",
    }


FENCE_RE = re.compile(
    r"^```(?:yaml|yml)\s*\n(.*?)^```\s*$",
    re.MULTILINE | re.DOTALL,
)


def extract_yaml_block(markdown: str, heading: str | None = None) -> str:
    """Return YAML body from the first ```yaml fence, optionally after a heading."""
    text = markdown
    if heading:
        idx = text.find(heading)
        if idx == -1:
            raise ValueError(f"Heading not found: {heading!r}")
        text = text[idx + len(heading) :]
    match = FENCE_RE.search(text)
    if not match:
        raise ValueError("No ```yaml fenced block found")
    return match.group(1).rstrip("\n") + "\n"


def write_markdown_snippet(yaml_body: str, out_md: Path) -> None:
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(f"```yaml\n{yaml_body}```\n", encoding="utf-8")


def render_png(yaml_body: str, out_png: Path, *, font_size: int = 13) -> None:
    out_png.parent.mkdir(parents=True, exist_ok=True)
    formatter = ImageFormatter(
        style=VSCodeDarkPlusYaml,
        font_name="DejaVu Sans Mono",
        font_size=font_size,
        line_numbers=False,
        line_pad=2,
        image_pad=12,
    )
    png_bytes = highlight(yaml_body, YamlLexer(), formatter)
    out_png.write_bytes(png_bytes)


def render_markdown_file(
    source: Path,
    out_png: Path,
    *,
    heading: str | None = None,
    font_size: int = 22,
) -> str:
    """Extract YAML from markdown source, render PNG; return yaml body."""
    markdown = source.read_text(encoding="utf-8")
    yaml_body = extract_yaml_block(markdown, heading)
    render_png(yaml_body, out_png, font_size=font_size)
    return yaml_body


def main() -> int:
    repo_root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=repo_root / "servicenow/docs/DT_SN_Specification_Guide.md",
        help="Markdown file containing a ```yaml fence",
    )
    parser.add_argument(
        "--heading",
        default="### Docker Compose example",
        help="Only search for the fence after this heading",
    )
    parser.add_argument(
        "--write-snippet-md",
        action="store_true",
        help="Also write yaml-only fenced copy to --out-md",
    )
    parser.add_argument(
        "--out-md",
        type=Path,
        default=repo_root / "tmp/docker_example.md",
    )
    parser.add_argument(
        "--out-png",
        type=Path,
        default=repo_root / "tmp/docker_example.png",
    )
    parser.add_argument(
        "--font-size",
        type=int,
        default=22,
        help="Monospace font size in points for PNG render",
    )
    args = parser.parse_args()

    markdown = args.source.read_text(encoding="utf-8")
    yaml_body = extract_yaml_block(markdown, args.heading)
    if args.write_snippet_md:
        write_markdown_snippet(yaml_body, args.out_md)
    render_png(yaml_body, args.out_png, font_size=args.font_size)

    if args.write_snippet_md:
        print(f"Wrote {args.out_md}")
    print(f"Wrote {args.out_png}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
