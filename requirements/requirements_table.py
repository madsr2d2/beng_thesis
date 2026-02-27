"""
requirements_table.py  --  Export CAN requirements from TOML to HTML or Markdown

Usage:
    python requirements_table.py                              # saves requirements.html
    python requirements_table.py --html out.html
    python requirements_table.py --markdown out.md
    python requirements_table.py --cat ERR --html err.html
    python requirements_table.py --status Verified --markdown verified.md
    python requirements_table.py --cat FRM --status Verified
    python requirements_table.py --format FB
    python requirements_table.py --side TX
    python requirements_table.py --priority H
    python requirements_table.py --search "bit rate"
"""

import argparse
import tomllib
import re
import pandas as pd

# -- TOML -> DataFrame ---------------------------------------------------------


def load_toml(path: str) -> pd.DataFrame:
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    rows = []
    for req_id, fields in raw["requirements"].items():
        m = re.match(r"([A-Z]+)(\d+)(TX|RX|SYS)", req_id)
        cat = m.group(1) if m else ""
        side = m.group(3) if m else ""

        rows.append(
            {
                "id": req_id,
                "cat": cat,
                "side": side,
                "description": fields.get("description", ""),
                "iso_reference": fields.get("iso_reference", ""),
                "format": "/".join(fields.get("format", [])),
                "status": fields.get("status", ""),
                "priority": fields.get("priority", ""),
                "tests": fields.get("tests", ""),
                "acceptance_criteria": fields.get("acceptance_criteria", ""),
                "verification": fields.get("verification", ""),
                "dependencies": ", ".join(fields.get("dependencies", [])),
                "notes": fields.get("notes", ""),
            }
        )

    return pd.DataFrame(rows)


# -- Filtering -----------------------------------------------------------------


def apply_filters(df: pd.DataFrame, args) -> pd.DataFrame:
    if args.status:
        df = df[df["status"].str.lower().isin([s.lower() for s in args.status])]
    if args.format:
        df = df[df["format"].str.contains(args.format, case=False, na=False)]
    if args.cat:
        df = df[df["cat"].str.upper() == args.cat.upper()]
    if args.side:
        df = df[df["side"].str.upper() == args.side.upper()]
    if args.priority:
        df = df[df["priority"].str.upper() == args.priority.upper()]
    if args.search:
        mask = (
            df["description"].str.contains(args.search, case=False, na=False)
            | df["notes"].str.contains(args.search, case=False, na=False)
            | df["acceptance_criteria"].str.contains(args.search, case=False, na=False)
        )
        df = df[mask]
    return df


# -- HTML export ---------------------------------------------------------------

EXPORT_COLS = [
    "id",
    "description",
    "iso_reference",
    "format",
    "status",
    "priority",
    "tests",
    "acceptance_criteria",
    "verification",
    "dependencies",
    "notes",
]

STATUS_CSS = {
    "Verified": "color: #2ecc71; font-weight: bold",
    "Implemented": "color: #f39c12",
    "Diagnostic": "color: #e67e22",
    "Partially": "color: #e67e22",
    "Not Applicable": "color: #95a5a6",
    "Not Started": "color: #e74c3c; font-weight: bold",
}
PRIORITY_CSS = {
    "C": "color: #2ecc71; font-weight: bold",
    "H": "color: #f39c12",
    "M": "color: #95a5a6",
}
CAT_CSS = {
    "FRM": "color: #00bcd4; font-weight: bold",
    "TMG": "color: #3f51b5; font-weight: bold",
    "ERR": "color: #e74c3c; font-weight: bold",
    "CRC": "color: #9c27b0; font-weight: bold",
}


def export_html(df: pd.DataFrame, path: str):
    out = df[EXPORT_COLS].fillna("").copy()

    def style_status(val):
        return STATUS_CSS.get(val, "")

    def style_priority(val):
        return PRIORITY_CSS.get(val, "")

    def style_id(val):
        m = re.match(r"([A-Z]+)", str(val))
        return CAT_CSS.get(m.group(1) if m else "", "")

    styled = (
        out.style.map(style_status, subset=["status"])
        .map(style_priority, subset=["priority"])
        .map(style_id, subset=["id"])
        .set_table_styles(
            [
                {
                    "selector": "table",
                    "props": "border-collapse: collapse; width: 100%; font-family: monospace; "
                    "font-size: 13px; background: #1e1e1e; color: #d4d4d4;",
                },
                {
                    "selector": "thead tr th",
                    "props": "background: #2d2d2d; color: #ffffff; padding: 8px 12px; "
                    "text-align: left; border-bottom: 2px solid #444; "
                    "white-space: nowrap; position: sticky; top: 0; z-index: 1; "
                    "cursor: pointer; user-select: none;",
                },
                {
                    "selector": "td",
                    "props": "padding: 6px 12px; border-bottom: 1px solid #333; vertical-align: top;",
                },
                {"selector": "tbody tr:hover", "props": "background: #2a2a2a;"},
            ]
        )
        .set_properties(**{"white-space": "normal", "word-wrap": "break-word"})
        .set_properties(
            subset=[
                "id",
                "iso_reference",
                "format",
                "status",
                "priority",
                "tests",
                "verification",
            ],
            **{"white-space": "nowrap"},
        )
    )

    table_html = styled.to_html()
    html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>CAN Requirements</title>
  <style>
    body {{ margin: 0; padding: 16px; background: #1e1e1e; color: #d4d4d4; }}
    h1   {{ font-family: monospace; font-size: 16px; color: #888; margin-bottom: 12px; }}
    .wrap {{ overflow-x: auto; }}
    th.asc::after  {{ content: " ▲"; font-size: 10px; }}
    th.desc::after {{ content: " ▼"; font-size: 10px; }}
    th:hover {{ background: #3a3a3a !important; }}
  </style>
</head>
<body>
  <h1>CAN Requirements &mdash; {len(out)} rows</h1>
  <div class="wrap">
    {table_html}
  </div>
  <script>
    const table = document.querySelector("table");
    const headers = table.querySelectorAll("th");
    let sortCol = -1, sortAsc = true;
    headers.forEach((th, col) => {{
      th.addEventListener("click", () => {{
        const tbody = table.querySelector("tbody");
        const rows  = Array.from(tbody.querySelectorAll("tr"));
        sortAsc = sortCol === col ? !sortAsc : true;
        sortCol = col;
        rows.sort((a, b) => {{
          const av = a.cells[col]?.innerText.trim() || "";
          const bv = b.cells[col]?.innerText.trim() || "";
          return sortAsc ? av.localeCompare(bv) : bv.localeCompare(av);
        }});
        rows.forEach(r => tbody.appendChild(r));
        headers.forEach(h => h.classList.remove("asc", "desc"));
        th.classList.add(sortAsc ? "asc" : "desc");
      }});
    }});
  </script>
</body>
</html>"""

    with open(path, "w", encoding="utf-8") as f:
        f.write(html)


# -- Markdown export -----------------------------------------------------------


def export_markdown(df: pd.DataFrame, path: str):
    out = df[EXPORT_COLS].fillna("")
    header = "| " + " | ".join(out.columns) + " |"
    sep = "| " + " | ".join(["---"] * len(out.columns)) + " |"
    rows = ["| " + " | ".join(str(v) for v in row) + " |" for _, row in out.iterrows()]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join([header, sep] + rows))


# -- CLI -----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Export CAN requirements from TOML")
    parser.add_argument("--toml", default="requirements.toml")
    parser.add_argument(
        "--status", action="append", help="Filter by status (repeatable)"
    )
    parser.add_argument("--format", help="Filter by format code e.g. FB")
    parser.add_argument("--cat", help="Filter by category: FRM, TMG, ERR, CRC")
    parser.add_argument("--side", help="Filter by side: TX or RX")
    parser.add_argument("--priority", help="Filter by priority: C, H, M")
    parser.add_argument("--search", help="Search description/notes/acceptance criteria")
    parser.add_argument(
        "--html",
        metavar="FILE",
        nargs="?",
        const="requirements.html",
        help="Save as HTML (default: requirements.html)",
    )
    parser.add_argument(
        "--markdown", metavar="FILE", help="Save as markdown e.g. requirements.md"
    )
    args = parser.parse_args()

    df = load_toml(args.toml)
    df = apply_filters(df, args)

    if df.empty:
        print("No requirements match the given filters.")
        return

    # Default to HTML if no output flag given
    if not args.html and not args.markdown:
        args.html = "requirements.html"

    if args.html:
        export_html(df, args.html)
        print(f"Saved to {args.html}")

    if args.markdown:
        export_markdown(df, args.markdown)
        print(f"Saved to {args.markdown}")


if __name__ == "__main__":
    main()

