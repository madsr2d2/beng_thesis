#!/usr/bin/env python3
"""
Requirements Search Tool

Search the CAN system requirements from requirements.toml

Usage:
    python scripts/req_search.py --query "CRC"
    python scripts/req_search.py --status "Verified"
    python scripts/req_search.py --priority "H" --format "FE"
    python scripts/req_search.py --req-id "FRM001TX"
"""

import argparse
import sys
import tomllib
from pathlib import Path
from typing import Optional


def find_requirements_file() -> Path:
    """Find requirements.toml in project structure."""
    candidates = [
        Path("requirements/requirements.toml"),
        Path("./requirements/requirements.toml"),
        Path(__file__).parent.parent / "requirements/requirements.toml",
    ]

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    raise FileNotFoundError(
        "Could not find requirements.toml. "
        "Please run from project root or specify path."
    )


def load_requirements(path: Path) -> dict:
    """Load requirements from TOML file."""
    with open(path, "rb") as f:
        data = tomllib.load(f)
    return data.get("requirements", {})


def search_requirements(
    requirements: dict,
    query: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    format_type: Optional[str] = None,
    req_id: Optional[str] = None,
) -> dict:
    """Search requirements with filters."""
    results = {}

    for rid, req in requirements.items():
        # Exact ID match
        if req_id and rid != req_id:
            continue

        # Status filter
        if status and req.get("status") != status:
            continue

        # Priority filter
        if priority and req.get("priority") != priority:
            continue

        # Format filter
        if format_type:
            formats = req.get("format", [])
            if isinstance(formats, str):
                formats = [formats]
            if format_type not in formats:
                continue

        # Full-text search
        if query:
            query_lower = query.lower()
            searchable = " ".join([
                req.get("description", ""),
                req.get("notes", ""),
                req.get("iso_reference", ""),
                rid,
            ]).lower()

            if query_lower not in searchable:
                continue

        results[rid] = req

    # Sort by requirement ID
    return {k: results[k] for k in sorted(results.keys())}


def format_short(req_id: str, req: dict) -> str:
    """Format requirement for list view."""
    desc = req.get("description", "")[:70]
    status = req.get("status", "?")
    priority = req.get("priority", "-")

    return f"{req_id:12s} | {status:12s} | {priority:3s} | {desc}..."


def format_full(req_id: str, req: dict) -> str:
    """Format requirement for detailed view."""
    lines = [
        f"REQUIREMENT: {req_id}",
        f"{'=' * 70}",
        f"\nDescription:",
        f"  {req.get('description', 'N/A')}",
        f"\nMetadata:",
        f"  Status:      {req.get('status', 'N/A')}",
        f"  Priority:    {req.get('priority', '(none)')}",
        f"  Formats:     {', '.join(req.get('format', []))}",
        f"  ISO Ref:     {req.get('iso_reference', 'N/A')}",
        f"\nTest & Verification:",
        f"  Tests:       {req.get('tests', 'None')}",
        f"  Verification: {req.get('verification', 'N/A')}",
        f"  Acceptance:  {req.get('acceptance_criteria', 'N/A')}",
        f"\nRelationships:",
        f"  Dependencies: {', '.join(req.get('dependencies', [])) or 'None'}",
        f"  Notes:       {req.get('notes', 'None')}",
    ]

    return "\n".join(lines)


def print_results(results: dict, detailed: bool = False) -> None:
    """Print search results."""
    if not results:
        print("No requirements matched.")
        return

    if detailed and len(results) == 1:
        # Show single result in detail
        req_id = list(results.keys())[0]
        print(format_full(req_id, results[req_id]))
    else:
        # Show list
        print(f"Found {len(results)} requirements:\n")
        for req_id in sorted(results.keys()):
            print(format_short(req_id, results[req_id]))


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Search CAN system requirements from requirements.toml"
    )

    parser.add_argument(
        "-q", "--query",
        help="Search in description, notes, ISO reference (substring match)"
    )
    parser.add_argument(
        "-s", "--status",
        help="Filter by status (Verified, Implemented, Diagnostic, Not Applicable)"
    )
    parser.add_argument(
        "-p", "--priority",
        help="Filter by priority (C, H, M)"
    )
    parser.add_argument(
        "-f", "--format",
        dest="format_type",
        help="Filter by format (CB, CE, FB, FE)"
    )
    parser.add_argument(
        "-r", "--req-id",
        help="Get specific requirement by ID"
    )
    parser.add_argument(
        "--file",
        help="Path to requirements.toml (auto-detected if not specified)"
    )
    parser.add_argument(
        "--list-statuses",
        action="store_true",
        help="List all available statuses"
    )
    parser.add_argument(
        "--list-priorities",
        action="store_true",
        help="List all available priorities"
    )
    parser.add_argument(
        "--list-formats",
        action="store_true",
        help="List all available formats"
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Show summary statistics"
    )

    args = parser.parse_args()

    try:
        # Load requirements
        req_file = Path(args.file) if args.file else find_requirements_file()
        requirements = load_requirements(req_file)

        # Handle list operations
        if args.list_statuses:
            statuses = sorted(set(r.get("status") for r in requirements.values()))
            print("Available statuses:")
            for s in statuses:
                print(f"  - {s}")
            return 0

        if args.list_priorities:
            priorities = sorted(set(r.get("priority") for r in requirements.values()),
                              key=lambda x: (x is None, x))
            print("Available priorities:")
            for p in priorities:
                print(f"  - {p or '(none)'}")
            return 0

        if args.list_formats:
            formats = set()
            for req in requirements.values():
                for fmt in req.get("format", []):
                    formats.add(fmt)
            print("Available formats:")
            for f in sorted(formats):
                print(f"  - {f}")
            return 0

        if args.summary:
            # Summary statistics
            total = len(requirements)
            by_status = {}
            by_priority = {}
            by_format = {}

            for req in requirements.values():
                s = req.get("status", "Unknown")
                by_status[s] = by_status.get(s, 0) + 1

                p = req.get("priority", "(none)")
                by_priority[p] = by_priority.get(p, 0) + 1

                for fmt in req.get("format", []):
                    by_format[fmt] = by_format.get(fmt, 0) + 1

            print(f"REQUIREMENTS SUMMARY")
            print(f"{'=' * 60}")
            print(f"\nTotal: {total}\n")

            print("By Status:")
            for s in sorted(by_status.keys()):
                count = by_status[s]
                pct = (count / total * 100) if total > 0 else 0
                print(f"  {s:20s}: {count:3d} ({pct:5.1f}%)")

            print("\nBy Priority:")
            for p in sorted(by_priority.keys()):
                count = by_priority[p]
                pct = (count / total * 100) if total > 0 else 0
                print(f"  {p:20s}: {count:3d} ({pct:5.1f}%)")

            if by_format:
                print("\nBy Format:")
                for fmt in sorted(by_format.keys()):
                    count = by_format[fmt]
                    print(f"  {fmt:20s}: {count:3d}")

            return 0

        # Regular search
        results = search_requirements(
            requirements,
            query=args.query,
            status=args.status,
            priority=args.priority,
            format_type=args.format_type,
            req_id=args.req_id,
        )

        # Show results (detailed if single requirement)
        print_results(results, detailed=True)
        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
