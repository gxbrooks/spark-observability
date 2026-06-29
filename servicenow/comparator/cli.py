"""CLI for ServiceNow ↔ Dynatrace compare."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from servicenow.comparator.runner import run_compare


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compare ServiceNow CMDB/CSDM models with Dynatrace entities.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for DT_SN_Model_Comparison*.json (default: tmp/compare/<timestamp>)",
    )
    parser.add_argument(
        "--scope-unit-id",
        help="Compare only this scope unit (e.g. brooks-lab-onprem)",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        help="Repository root (default: auto-detect from package location)",
    )
    parser.add_argument(
        "--filter-by-cmdb-location",
        action="store_true",
        help="Limit ServiceNow Linux servers to scope unit cmdb_location",
    )
    parser.add_argument(
        "--filter-by-dynatrace-mz",
        action="store_true",
        help="Limit Dynatrace entities to scope unit management zone(s)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = run_compare(
            args.output_dir,
            scope_unit_id=args.scope_unit_id,
            repo_root=args.repo_root,
            filter_by_cmdb_location=args.filter_by_cmdb_location,
            filter_by_dynatrace_mz=args.filter_by_dynatrace_mz,
        )
    except Exception as exc:
        print(f"Compare failed: {exc}", file=sys.stderr)
        return 1

    summary = result["report"]["summary"]
    sev = summary.get("findings_by_severity", {})
    print(f"Compare complete for scope unit(s): {', '.join(result['scope_units'])}")
    print(f"Output directory: {result['output_dir']}")
    print(f"Export: {result['export_path']}")
    print(f"Report: {result['report_path']}")
    print(
        f"  subclass_groups={summary.get('findings_subclass_groups', 0)} "
        f"items={summary.get('finding_items_total', 0)} "
        f"(action_required={sev.get('action_required', 0)} warning={sev.get('warning', 0)} "
        f"informational={sev.get('informational', 0)}) "
        f"hosts matched={summary.get('hosts_matched', 0)} "
        f"app_missing_tags={summary.get('app_missing_tags', 0)} "
        f"object_sources={summary.get('object_sources_sgo_dynatrace', 0)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
