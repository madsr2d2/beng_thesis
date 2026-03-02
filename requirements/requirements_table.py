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
    
    # Handle New Format: [[requirement]]
    if "requirement" in raw:
        for fields in raw["requirement"]:
            # Map new format fields to DataFrame columns
            rows.append(
                {
                    "id": fields.get("id", ""),
                    "cat": fields.get("layer", ""),
                    "side": fields.get("side", ""),
                    "description": fields.get("original_wording", ""),
                    "iso_reference": fields.get("source_clause", ""),
                    "format": fields.get("format_applicability", ""),
                    "notes": fields.get("notes", ""),
                    "pre": fields.get("precondition", ""),
                    "evt": fields.get("event", ""),
                    "post": fields.get("postcondition", ""),
                    "shape": fields.get("shape", ""),
                    "scope": fields.get("scope", ""),
                    "flags": ", ".join(fields.get("flags", [])),
                    "label": fields.get("label", ""),
                    "file": fields.get("file", ""),
                }
            )
    
    # Handle Legacy Format: [requirements.NNN]
    elif "requirements" in raw:
        for req_id, fields in raw["requirements"].items():
            rows.append(
                {
                    "id": req_id,
                    "cat": fields.get("category", ""),
                    "side": fields.get("side", ""),
                    "description": fields.get("description", ""),
                    "iso_reference": fields.get("iso_reference", ""),
                    "format": "/".join(fields.get("format", [])),
                    "notes": fields.get("notes", ""),
                    "pre": fields.get("pre", ""),
                    "evt": fields.get("evt", ""),
                    "post": fields.get("post", ""),
                    "shape": "",
                    "scope": "",
                    "flags": "",
                    "label": "",
                    "file": "",
                }
            )

    return pd.DataFrame(rows)


# -- HTML export ---------------------------------------------------------------

EXPORT_COLS = [
    "id",
    "cat",
    "side",
    "shape",
    "scope",
    "description",
    "iso_reference",
    "format",
    "notes",
    "pre",
    "evt",
    "post",
    "flags",
    "label",
    "file",
]

CAT_CSS = {
    "FRM": "color: #00bcd4; font-weight: bold",
    "TMG": "color: #3f51b5; font-weight: bold",
    "ERR": "color: #e74c3c; font-weight: bold",
    "CRC": "color: #9c27b0; font-weight: bold",
    "LLC": "color: #ffeb3b; font-weight: bold",
    "MAC": "color: #03a9f4; font-weight: bold",
    "PCS": "color: #8bc34a; font-weight: bold",
}


def export_html(df: pd.DataFrame, path: str):
    """Export requirements as interactive HTML table"""
    out = df[EXPORT_COLS].fillna("").copy()

    def style_cat(cat_val):
        return CAT_CSS.get(cat_val, "")

    styled = (
        out.style.map(style_cat, subset=["cat"])
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
                "label",
                "file",
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
    """Renumber requirement IDs sequentially, preserving order and prefixes for new format."""
    with open(path, "r") as f:
        lines = f.readlines()

    is_new_format = any(line.strip() == "[[requirement]]" for line in lines)

    if is_new_format:
        # Split into header and blocks
        header_end = 0
        for i, line in enumerate(lines):
            if line.strip() == "[[requirement]]":
                header_end = i
                break
        header = lines[:header_end]
        
        blocks = []
        current = []
        for line in lines[header_end:]:
            if line.strip() == "[[requirement]]" and current:
                blocks.append(current)
                current = [line]
            else:
                current.append(line)
        if current:
            blocks.append(current)

        new_lines = header[:]
        counters = {}
        for block in blocks:
            for line in block:
                m = re.search(r'id = "(.*?)(\d{3})"', line)
                if m:
                    prefix = m.group(1)
                    counters[prefix] = counters.get(prefix, 0) + 1
                    new_id_num = f"{counters[prefix]:03d}"
                    line = re.sub(r'id = "(.*?)(\d{3})"', f'id = "{prefix}{new_id_num}"', line)
                new_lines.append(line)
        
        with open(path, "w") as f:
            f.writelines(new_lines)
        return sum(counters.values())

    else:
        # Legacy Format
        header_end = 0
        for i, line in enumerate(lines):
            if re.match(r"\[requirements\.\d{3}\]", line):
                header_end = i
                break

        header = lines[:header_end]
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

        new_lines = header[:]
        for new_idx, group in enumerate(groups, start=1):
            new_id = f"{new_idx:03d}"
            m = re.match(r"\[requirements\.(\d{3})\]", group[0])
            if not m:
                continue
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

        _update_header_id_range(path, len(groups))
        return len(groups)


def delete_requirement(path: str, req_id: str):
    """Delete a requirement by ID and renumber remaining requirements."""
    with open(path, "r") as f:
        content = f.read()

    is_new_format = "[[requirement]]" in content

    if is_new_format:
        # New format deletion: look for [[requirement]] followed by id = "req_id"
        pattern = rf"\[\[requirement\]\]\s*\nid = \"{re.escape(req_id)}\".*?(?=\[\[requirement\]\]|$)"
        new_content = re.sub(pattern, "", content, flags=re.DOTALL)
    else:
        # Legacy format deletion
        req_id = req_id.zfill(3)
        pattern = rf"\[requirements\.{re.escape(req_id)}\]\n.*?(?=\[requirements\.(?!{re.escape(req_id)}[\].])|$)"
        new_content = re.sub(pattern, "", content, flags=re.DOTALL)

    if new_content == content:
        print(f"Requirement {req_id} not found")
        return

    with open(path, "w") as f:
        f.write(new_content)

    count = renumber(path)
    print(f"Deleted requirement {req_id}, renumbered to {count} entries")


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
    parser.add_argument("--markdown", metavar="FILE", help="Save as Markdown table")
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
