"""
requirements_table.py  --  Manage CAN requirements TOML file

Usage:
    python requirements_table.py                              # saves requirements.html
    python requirements_table.py --html out.html
    python requirements_table.py --markdown out.md
    python requirements_table.py --renumber                   # renumber IDs sequentially
    python requirements_table.py --delete 011                 # delete requirement and renumber
"""

import argparse
import re
import tomllib
import pandas as pd


def load_toml(path: str) -> pd.DataFrame:
    """Load requirements from TOML and convert to DataFrame"""
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    rows = []
    for req_id, fields in raw["requirements"].items():
        # req_id is now numeric (001, 002, etc.)
        # category and side are stored in fields
        cat = fields.get("category", "")
        side = fields.get("side", "")

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
                "acceptance_criteria": fields.get("acceptance_criteria", ""),
                "verification": fields.get("verification", ""),
                "notes": fields.get("notes", ""),
            }
        )

    return pd.DataFrame(rows)


# -- HTML export ---------------------------------------------------------------

EXPORT_COLS = [
    "id",
    "cat",
    "side",
    "description",
    "iso_reference",
    "format",
    "status",
    "priority",
    "acceptance_criteria",
    "verification",
    "notes",
]

STATUS_CSS = {
    "verified": "color: #2ecc71; font-weight: bold",
    "implemented": "color: #f39c12",
    "diagnostic": "color: #e67e22",
    "unverified": "color: #e74c3c; font-weight: bold",
    "not applicable": "color: #95a5a6",
}

PRIORITY_CSS = {
    "critical": "color: #e74c3c; font-weight: bold",
    "high": "color: #f39c12",
    "medium": "color: #95a5a6",
    "low": "color: #7f8c8d",
}

CAT_CSS = {
    "FRM": "color: #00bcd4; font-weight: bold",
    "TMG": "color: #3f51b5; font-weight: bold",
    "ERR": "color: #e74c3c; font-weight: bold",
    "CRC": "color: #9c27b0; font-weight: bold",
}


def export_html(df: pd.DataFrame, path: str):
    """Export requirements as interactive HTML table"""
    out = df[EXPORT_COLS].fillna("").copy()

    def style_status(val):
        return STATUS_CSS.get(val.lower(), "")

    def style_priority(val):
        return PRIORITY_CSS.get(val, "")

    def style_cat(cat_val):
        return CAT_CSS.get(cat_val, "")

    styled = (
        out.style.map(style_status, subset=["status"])
        .map(style_priority, subset=["priority"])
        .map(style_cat, subset=["cat"])
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
                "cat",
                "side",
                "iso_reference",
                "format",
                "status",
                "priority",
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
    body {{ margin: 0; padding: 16px; background: #1e1e1e; color: #d4d4d4; font-family: monospace; }}
    h1 {{ font-size: 16px; color: #888; margin: 0 0 16px 0; }}
    .wrap {{ overflow-x: auto; }}
    th {{ cursor: pointer; user-select: none; }}
    th:hover {{ background: #3a3a3a !important; }}
    th.asc::after {{ content: " ▲"; font-size: 10px; color: #2ecc71; }}
    th.desc::after {{ content: " ▼"; font-size: 10px; color: #e74c3c; }}
  </style>
</head>
<body>
  <h1>CAN Requirements — {len(out)} entries (Click column headers to sort)</h1>
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
        const rows = Array.from(tbody.querySelectorAll("tr"));
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
    """Export requirements as Markdown table"""
    out = df[EXPORT_COLS].fillna("")
    header = "| " + " | ".join(out.columns) + " |"
    sep = "| " + " | ".join(["---"] * len(out.columns)) + " |"
    rows = ["| " + " | ".join(str(v) for v in row) + " |" for _, row in out.iterrows()]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join([header, sep] + rows))


# -- Renumber / Delete ---------------------------------------------------------


def renumber(path: str):
    """Renumber requirement IDs to be sequential (001, 002, ...) preserving order."""
    with open(path, "r") as f:
        lines = f.readlines()

    # Split into header (before first [requirements.) and body
    header_end = 0
    for i, line in enumerate(lines):
        if re.match(r"\[requirements\.\d{3}\]", line):
            header_end = i
            break

    header = lines[:header_end]

    # Split body into groups: each starts at a top-level [requirements.NNN] line
    groups = []
    current = []
    for line in lines[header_end:]:
        if re.match(r"\[requirements\.\d{3}\]\s*$", line) and current:
            groups.append(current)
            current = [line]
        else:
            current.append(line)
    if current:
        groups.append(current)

    # Renumber each group sequentially
    new_lines = header[:]
    for new_idx, group in enumerate(groups, start=1):
        new_id = f"{new_idx:03d}"
        m = re.match(r"\[requirements\.(\d{3})\]", group[0])
        old_id = m.group(1)
        for line in group:
            line = re.sub(
                rf"\[requirements\.{re.escape(old_id)}([\].])",
                rf"[requirements.{new_id}\1",
                line,
            )
            new_lines.append(line)

    with open(path, "w") as f:
        f.writelines(new_lines)

    # Update the ID range in the header comment
    _update_header_id_range(path, len(groups))

    return len(groups)


def delete_requirement(path: str, req_id: str):
    """Delete a requirement by ID and renumber remaining requirements."""
    req_id = req_id.zfill(3)

    with open(path, "r") as f:
        content = f.read()

    # Remove the requirement block (main + simulation + formal sub-tables)
    pattern = rf"\[requirements\.{re.escape(req_id)}\]\n.*?(?=\[requirements\.(?!{re.escape(req_id)}[\].])|$)"
    new_content = re.sub(pattern, "", content, flags=re.DOTALL)

    if new_content == content:
        print(f"Requirement {req_id} not found")
        return

    with open(path, "w") as f:
        f.write(new_content)

    count = renumber(path)
    print(f"Deleted requirement {req_id}, renumbered to 001-{count:03d}")


def _update_header_id_range(path: str, count: int):
    """Update the ID range comment in the file header."""
    with open(path, "r") as f:
        content = f.read()

    content = re.sub(
        r"Unique numeric ID \(\d+-\d+\)",
        f"Unique numeric ID (001-{count:03d})",
        content,
    )

    with open(path, "w") as f:
        f.write(content)


# -- CLI -----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Manage CAN requirements: export tables, renumber, delete",
    )
    parser.add_argument("--toml", default="requirements.toml", help="Path to TOML file")
    parser.add_argument(
        "--html",
        metavar="FILE",
        nargs="?",
        const="requirements.html",
        help="Save as HTML (default: requirements.html)",
    )
    parser.add_argument(
        "--markdown", metavar="FILE", help="Save as Markdown table"
    )
    parser.add_argument(
        "--renumber", action="store_true", help="Renumber IDs sequentially"
    )
    parser.add_argument(
        "--delete", metavar="ID", help="Delete requirement by ID and renumber"
    )
    args = parser.parse_args()

    if args.delete:
        delete_requirement(args.toml, args.delete)
        return

    if args.renumber:
        count = renumber(args.toml)
        print(f"Renumbered {count} requirements: 001-{count:03d}")
        return

    df = load_toml(args.toml)

    # Default to HTML if no output format given
    if not args.html and not args.markdown:
        args.html = "requirements.html"

    if args.html:
        export_html(df, args.html)
        print(f"Saved {len(df)} requirements to {args.html}")

    if args.markdown:
        export_markdown(df, args.markdown)
        print(f"Saved {len(df)} requirements to {args.markdown}")


if __name__ == "__main__":
    main()
