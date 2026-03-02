"""
verification_plan_table.py  --  Manage CAN verification plan TOML file

Usage:
    python verification_plan_table.py                              # saves verification_plan.html
    python verification_plan_table.py --toml path/to/file.toml     # specify TOML file
    python verification_plan_table.py --html out.html
    python verification_plan_table.py --markdown out.md
    python verification_plan_table.py --renumber                   # renumber IDs sequentially
    python verification_plan_table.py --delete REQ-LLC-005         # delete requirement and renumber
    python verification_plan_table.py --exclude 'flags=DOC_ONLY'   # exclude rows matching pattern
    python verification_plan_table.py --include 'layer=LLC'          # include only rows matching pattern
"""

import argparse
import re
import tomllib
from pathlib import Path

import pandas as pd

# -- Auto-detect TOML file ----------------------------------------------------

_SCRIPT_DIR = Path(__file__).parent


def _find_toml() -> str:
    """Auto-detect verification plan TOML file."""
    for name in ["verification_plan.toml"]:
        path = _SCRIPT_DIR / name
        if path.exists():
            return str(path)
    return "verification_plan.toml"


# -- Load TOML ----------------------------------------------------------------


def load_toml(path: str) -> pd.DataFrame:
    """Load requirements from TOML and convert to DataFrame."""
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    if "requirement" not in raw:
        raise ValueError(f"No [[requirement]] array found in {path}")

    rows = []
    for fields in raw["requirement"]:
        rows.append(
            {
                "id": fields.get("id", ""),
                "layer": fields.get("layer", ""),
                "side": fields.get("side", ""),
                "original_wording": fields.get("original_wording", ""),
                "source_clause": fields.get("source_clause", ""),
                "format_applicability": fields.get("format_applicability", ""),
                "notes": fields.get("notes", ""),
                "precondition": fields.get("precondition", ""),
                "event": fields.get("event", ""),
                "postcondition": fields.get("postcondition", ""),
                "shape": fields.get("shape", ""),
                "scope": fields.get("scope", ""),
                "flags": ", ".join(fields.get("flags", [])),
                "label": fields.get("label", ""),
                "file": fields.get("file", ""),
            }
        )

    return pd.DataFrame(rows)


# -- HTML export ---------------------------------------------------------------

EXPORT_COLS = [
    "id",
    "layer",
    "side",
    "shape",
    "scope",
    "original_wording",
    "source_clause",
    "format_applicability",
    "notes",
    "precondition",
    "event",
    "postcondition",
    "flags",
    "label",
    "file",
]

CAT_CSS = {
    "LLC": "color: #ffeb3b; font-weight: bold",
    "MAC": "color: #03a9f4; font-weight: bold",
    "PCS": "color: #8bc34a; font-weight: bold",
    "FCE": "color: #9c27b0; font-weight: bold",
}


def export_html(df: pd.DataFrame, path: str, cols=None):
    """Export requirements as interactive HTML table."""
    out = df[cols or EXPORT_COLS].fillna("").copy()
    out = out.reset_index(drop=True)

    def style_cat(cat_val):
        return CAT_CSS.get(cat_val, "")

    active_cols = set(out.columns)
    nowrap_cols = [
        c
        for c in ["id", "layer", "side", "source_clause", "format_applicability", "label", "file"]
        if c in active_cols
    ]

    styled = (
        out.style.map(style_cat, subset=["layer"] if "layer" in active_cols else [])
        .hide(axis="index")
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
    )
    if nowrap_cols:
        styled = styled.set_properties(subset=nowrap_cols, **{"white-space": "nowrap"})

    table_html = styled.to_html()
    html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>CAN Requirements</title>
  <style>
    body {{ margin: 0; padding: 16px; background: #1e1e1e; color: #d4d4d4; font-family: monospace; }}
    h1 {{ font-size: 16px; color: #888; margin: 0 0 8px 0; }}
    .info {{ font-size: 13px; color: #666; margin: 0 0 16px 0; }}
    .wrap {{ overflow-x: auto; }}
    th {{ cursor: pointer; user-select: none; }}
    th:hover {{ background: #3a3a3a !important; }}
    th.asc::after {{ content: " \\25B2"; font-size: 10px; color: #2ecc71; }}
    th.desc::after {{ content: " \\25BC"; font-size: 10px; color: #e74c3c; }}
  </style>
</head>
<body>
  <h1>CAN Requirements — {len(out)} entries</h1>
  <p class="info">Click column headers to sort</p>
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


def export_markdown(df: pd.DataFrame, path: str, cols=None):
    """Export requirements as Markdown table."""
    out = df[cols or EXPORT_COLS].fillna("").reset_index(drop=True)
    header = "| " + " | ".join(out.columns) + " |"
    sep = "| " + " | ".join(["---"] * len(out.columns)) + " |"
    rows = []
    for _, row in out.iterrows():
        cells = [str(v).replace("|", "\\|").replace("\n", " ") for v in row]
        rows.append("| " + " | ".join(cells) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join([header, sep] + rows) + "\n")


# -- Renumber / Delete ---------------------------------------------------------


def renumber(path: str):
    """Renumber requirement IDs sequentially, preserving order and prefixes."""
    with open(path, "r") as f:
        lines = f.readlines()

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
                line = re.sub(
                    r'id = "(.*?)(\d{3})"', f'id = "{prefix}{new_id_num}"', line
                )
            new_lines.append(line)

    with open(path, "w") as f:
        f.writelines(new_lines)
    return sum(counters.values())


def delete_requirement(path: str, req_id: str):
    """Delete a requirement by ID and renumber remaining requirements."""
    with open(path, "r") as f:
        content = f.read()

    pattern = rf"\[\[requirement\]\]\s*\nid = \"{re.escape(req_id)}\".*?(?=\[\[requirement\]\]|$)"
    new_content = re.sub(pattern, "", content, flags=re.DOTALL)

    if new_content == content:
        print(f"Requirement {req_id} not found")
        return

    with open(path, "w") as f:
        f.write(new_content)

    count = renumber(path)
    print(f"Deleted requirement {req_id}, renumbered to {count} entries")


# -- CLI -----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Manage CAN requirements: export tables, renumber, delete",
    )
    parser.add_argument(
        "--toml", default=None, help="Path to TOML file (auto-detected if omitted)"
    )
    parser.add_argument(
        "--html",
        metavar="FILE",
        nargs="?",
        const="verification_plan.html",
        help="Save as HTML (default: verification_plan.html)",
    )
    parser.add_argument("--markdown", metavar="FILE", help="Save as Markdown table")
    parser.add_argument(
        "--renumber", action="store_true", help="Renumber IDs sequentially"
    )
    parser.add_argument(
        "--delete", metavar="ID", help="Delete requirement by ID and renumber"
    )
    parser.add_argument(
        "--exclude",
        metavar="COL=PAT",
        action="append",
        help="Exclude rows where COL contains PAT (e.g. --exclude 'flags=DOC_ONLY')",
    )
    parser.add_argument(
        "--include",
        metavar="COL=PAT",
        action="append",
        help="Include only rows where COL contains PAT (e.g. --include 'layer=LLC')",
    )
    parser.add_argument(
        "--hide",
        metavar="COL",
        action="append",
        help="Hide a column from output (e.g. --hide notes --hide flags)",
    )
    args = parser.parse_args()

    toml_path = args.toml or _find_toml()

    if args.delete:
        delete_requirement(toml_path, args.delete)
        return

    if args.renumber:
        count = renumber(toml_path)
        print(f"Renumbered {count} requirements")
        return

    df = load_toml(toml_path)

    if args.include:
        for incl in args.include:
            if "=" in incl:
                col, pat = incl.split("=", 1)
                if col in df.columns:
                    before = len(df)
                    df = df[df[col].astype(str).str.contains(pat, na=False)]
                    print(f"Included {len(df)} of {before} rows matching {incl}")
                else:
                    print(f"Warning: Column '{col}' not found")

    if args.exclude:
        for excl in args.exclude:
            if "=" in excl:
                col, pat = excl.split("=", 1)
                if col in df.columns:
                    before = len(df)
                    df = df[~df[col].astype(str).str.contains(pat, na=False)]
                    print(f"Excluded {before - len(df)} rows matching {excl}")
                else:
                    print(f"Warning: Column '{col}' not found")

    df = df.reset_index(drop=True)

    cols = EXPORT_COLS
    if args.hide:
        cols = [c for c in cols if c not in args.hide]

    # Default to HTML if no output format given
    if not args.html and not args.markdown:
        args.html = "verification_plan.html"

    if args.html:
        export_html(df, args.html, cols=cols)
        print(f"Saved {len(df)} requirements to {args.html}")

    if args.markdown:
        export_markdown(df, args.markdown, cols=cols)
        print(f"Saved {len(df)} requirements to {args.markdown}")


if __name__ == "__main__":
    main()
