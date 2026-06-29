#!/usr/bin/env python3
"""Build a compact structural outline of DT_SN_Model_Comparison_Report.json and render PNG."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from pygments import highlight
from pygments.formatters import ImageFormatter
from pygments.lexers import JsonLexer
from pygments.style import Style
from pygments.token import Token


class VSCodeDarkPlusJson(Style):
    background_color = "#1e1e1e"
    default_style = "#d4d4d4"

    styles = {
        Token.Text: "#d4d4d4",
        Token.Punctuation: "#d4d4d4",
        Token.Name.Tag: "#9cdcfe",
        Token.Name.Attribute: "#9cdcfe",
        Token.Literal.String: "#ce9178",
        Token.Literal.Number: "#b5cea8",
        Token.Keyword: "#569cd6",
    }


def build_outline(report: dict[str, Any]) -> dict[str, Any]:
    findings = report.get("findings", [])
    by_cat = report.get("findings_by_category", {})
    inv = report.get("inventory", {})
    host_align = inv.get("host_alignment", {})
    summary = report.get("summary", {})

    return {
        "report_version": report.get("report_version"),
        "generated_at": report.get("generated_at"),
        "scope_applied": {
            "dynatrace": {"management_zones": [], "mode": "all"},
            "servicenow": {"location": "", "mode": "all"},
        },
        "csdm_intent_sources": {
            "count": len(report.get("csdm_intent_sources", [])),
            "item": {"registry": "scope_unit_id, region_id, …", "intent": "BA, BS, application_services"},
        },
        "instance": {"servicenow_url": "…", "dynatrace_ui_url": "…"},
        "summary": {
            "findings_total": summary.get("findings_total"),
            "findings_by_severity": summary.get("findings_by_severity"),
            "hosts_matched": summary.get("hosts_matched"),
            "hosts_servicenow_only": summary.get("hosts_servicenow_only"),
            "hosts_dynatrace_only": summary.get("hosts_dynatrace_only"),
            "specified_application_services": summary.get("specified_application_services"),
            "cmdb_application_services": summary.get("cmdb_application_services"),
            "canonical_tag_bindings": summary.get("canonical_tag_bindings"),
            "dt_hosts": summary.get("dt_hosts"),
            "dt_process_groups": summary.get("dt_process_groups"),
        },
        "navigation": {
            "severity_levels": "action_required, warning, informational, ok",
            "categories_count": len(report.get("navigation", {}).get("categories", [])),
        },
        "findings": {
            "count": len(findings),
            "item_keys": "id, severity, category, issue, title, entity, observation, recommendation, resolution",
            "entity_keys": "type, name, url, sys_id, entity_id",
            "resolution_keys": "summary, steps, commands, docs",
        },
        "findings_by_category": {cat: len(items) for cat, items in sorted(by_cat.items())},
        "inventory": {
            "host_alignment": {
                "matched": len(host_align.get("matched", [])),
                "servicenow_only": len(host_align.get("servicenow_only", [])),
                "dynatrace_only": len(host_align.get("dynatrace_only", [])),
            },
            "application_services_diff": len(
                inv.get("application_services", {}).get("diff", [])
            ),
            "servicenow_hosts": len(inv.get("servicenow_hosts", [])),
            "servicenow_tag_bindings": len(inv.get("servicenow_tag_bindings", [])),
            "servicenow_application_services_cmdb": len(
                inv.get("servicenow_application_services_cmdb", [])
            ),
            "dynatrace_entities_summary": {
                "scope_mode": inv.get("dynatrace_entities_summary", {}).get("scope_mode"),
                "hosts": len(inv.get("dynatrace_entities_summary", {}).get("hosts", [])),
                "process_groups_count": summary.get("dt_process_groups"),
                "kubernetes_clusters": len(
                    inv.get("dynatrace_entities_summary", {}).get("kubernetes_clusters", [])
                ),
            },
        },
    }


def render_json_png(json_text: str, out_png: Path, *, font_size: int = 12) -> None:
    formatter = ImageFormatter(
        style=VSCodeDarkPlusJson,
        font_name="DejaVu Sans Mono",
        font_size=font_size,
        line_numbers=False,
        line_pad=1,
        image_pad=10,
    )
    out_png.write_bytes(highlight(json_text, JsonLexer(), formatter))


def write_markdown(outline: dict[str, Any], out_md: Path, source: Path) -> str:
    json_text = json.dumps(outline, indent=2, ensure_ascii=False) + "\n"
    body = (
        f"# DT_SN_Model_Comparison_Report — structural outline\n\n"
        f"Generated from `{source.name}`. "
        f"Numeric inventory values are array lengths from that run.\n\n"
        f"```json\n{json_text}```\n"
    )
    out_md.write_text(body, encoding="utf-8")
    return json_text


def main() -> int:
    repo_root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        type=Path,
        default=repo_root
        / "tmp/compare/20260627_165756/DT_SN_Model_Comparison_Report.json",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=repo_root / "servicenow/docs/DT_SN_Integration_Overview",
    )
    parser.add_argument("--font-size", type=int, default=12)
    args = parser.parse_args()

    report = json.loads(args.report.read_text(encoding="utf-8"))
    outline = build_outline(report)
    out_md = args.out_dir / "compare_report_outline.md"
    out_png = args.out_dir / "compare_report_outline.png"

    json_text = write_markdown(outline, out_md, args.report)
    render_json_png(json_text, out_png, font_size=args.font_size)

    print(f"Wrote {out_md}")
    print(f"Wrote {out_png}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
