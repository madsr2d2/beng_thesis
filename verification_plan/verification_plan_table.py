"""
verification_plan_table.py  --  Manage CAN verification plan TOML file

Usage:
    python verification_plan_table.py                              # saves verification_plan.html
    python verification_plan_table.py --toml path/to/file.toml     # specify TOML file
    python verification_plan_table.py --html out.html              # full HTML table
    python verification_plan_table.py --markdown out.md            # full Markdown table
    python verification_plan_table.py --report-md out.md           # condensed report table (paraphrase + abbrev.)
    python verification_plan_table.py --renumber                   # renumber IDs sequentially
    python verification_plan_table.py --delete REQ-005             # delete requirement and renumber
    python verification_plan_table.py --include 'layer=FCE'        # include only rows matching pattern
    python verification_plan_table.py --exclude 'layer=system'     # exclude rows matching pattern
"""

import argparse
import re
import tomllib
from pathlib import Path

# -- Auto-detect TOML file ----------------------------------------------------

_SCRIPT_DIR = Path(__file__).parent


def _find_toml() -> str:
    for name in ["verification_plan.toml"]:
        path = _SCRIPT_DIR / name
        if path.exists():
            return str(path)
    return "verification_plan.toml"


# -- Load TOML ----------------------------------------------------------------


def load_toml(path: str) -> list[dict]:
    """Load requirements from TOML and return as a list of dicts."""
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    if "requirement" not in raw:
        raise ValueError(f"No [[requirement]] array found in {path}")

    rows = []
    for fields in raw["requirement"]:
        rows.append(
            {
                "id": fields.get("id", ""),
                "iso_ref": fields.get("source_clause", ""),
                "layer": fields.get("layer", ""),
                "side": fields.get("side", ""),
                "format": fields.get("format_applicability", ""),
                "original_wording": fields.get("original_wording", ""),
                "paraphrase": fields.get("paraphrase", ""),
                "observability": fields.get("observability", ""),
                "verification_method": fields.get("verification_method", ""),
                "label": fields.get("label", ""),
                "file": fields.get("file", ""),
                "notes": fields.get("notes", ""),
            }
        )
    return rows


# -- Column sets --------------------------------------------------------------

EXPORT_COLS = [
    "id",
    "iso_ref",
    "layer",
    "side",
    "format",
    "paraphrase",
    "observability",
    "verification_method",
    "label",
    "file",
    "notes",
]

REPORT_COLS = ["id", "iso_ref", "layer", "paraphrase", "method", "label", "file"]

REPORT_HEADERS = ["ID", "ISO ref", "Layer", "Requirement", "Method", "Label", "File"]

# -- Value abbreviations for report table -------------------------------------

_METHOD_ABBREV = {
    "simulation": "sim",
    "code_inspection": "inspection",
    "coverage": "coverage",
    "simulation, coverage": "sim + coverage",
    "simulation, code_inspection": "sim + inspection",
    "code_inspection, simulation": "sim + inspection",
}


def _to_report_row(row: dict) -> dict:
    return {
        "id": row["id"],
        "iso_ref": row["iso_ref"].replace("§", ""),
        "layer": row["layer"],
        "paraphrase": row["paraphrase"].replace("; ", " • "),
        "method": _METHOD_ABBREV.get(
            row["verification_method"], row["verification_method"]
        ),
        "label": row["label"],
        "file": Path(row["file"]).name if row["file"] else "",
    }


# -- Filtering ----------------------------------------------------------------


def apply_filters(
    rows: list[dict], include: list[str] | None, exclude: list[str] | None
) -> list[dict]:
    for pat in include or []:
        if "=" in pat:
            col, val = pat.split("=", 1)
            before = len(rows)
            rows = [r for r in rows if val in r.get(col, "")]
            print(f"Included {len(rows)} of {before} rows matching {pat}")
        else:
            print(f"Warning: --include pattern '{pat}' has no '='")

    for pat in exclude or []:
        if "=" in pat:
            col, val = pat.split("=", 1)
            before = len(rows)
            rows = [r for r in rows if val not in r.get(col, "")]
            print(f"Excluded {before - len(rows)} rows matching {pat}")
        else:
            print(f"Warning: --exclude pattern '{pat}' has no '='")

    return rows


# -- HTML export ---------------------------------------------------------------

CAT_CSS = {
    "LLC": "color: #ffeb3b; font-weight: bold",
    "MAC": "color: #03a9f4; font-weight: bold",
    "PCS": "color: #8bc34a; font-weight: bold",
    "FCE": "color: #9c27b0; font-weight: bold",
    "system": "color: #ff7043; font-weight: bold",
}

_NOWRAP_COLS = {"id", "layer", "side", "iso_ref", "format", "label"}


def _html_cell(col: str, value: str) -> str:
    style = CAT_CSS.get(value, "") if col == "layer" else ""
    nowrap = "white-space: nowrap;" if col in _NOWRAP_COLS else ""
    combined = (style + " " + nowrap).strip()
    value = value.replace("\n", "<br>")
    if combined:
        return f'<td style="{combined}">{value}</td>'
    return f"<td>{value}</td>"


def export_html(rows: list[dict], path: str, cols: list[str] | None = None):
    """Export requirements as an interactive dark-theme HTML table."""
    cols = cols or EXPORT_COLS

    header_cells = "".join(f"<th>{c}</th>" for c in cols)
    body_rows = []
    for row in rows:
        cells = "".join(_html_cell(c, row.get(c, "")) for c in cols)
        body_rows.append(f"<tr>{cells}</tr>")
    body = "\n".join(body_rows)

    html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>CAN Verification Plan</title>
  <style>
    body {{ margin: 0; padding: 16px; background: #1e1e1e; color: #d4d4d4; font-family: monospace; }}
    h1 {{ font-size: 16px; color: #888; margin: 0 0 8px 0; }}
    .info {{ font-size: 13px; color: #666; margin: 0 0 16px 0; }}
    .wrap {{ overflow-x: auto; }}
    table {{ border-collapse: collapse; width: 100%; font-size: 13px; background: #1e1e1e; color: #d4d4d4; }}
    thead tr th {{ background: #2d2d2d; color: #fff; padding: 8px 12px; text-align: left;
                   border-bottom: 2px solid #444; white-space: nowrap;
                   position: sticky; top: 0; z-index: 1; cursor: pointer; user-select: none; }}
    td {{ padding: 6px 12px; border-bottom: 1px solid #333; vertical-align: top;
          white-space: normal; word-wrap: break-word; }}
    tbody tr:hover {{ background: #2a2a2a; }}
    th:hover {{ background: #3a3a3a !important; }}
    th.asc::after  {{ content: " \\25B2"; font-size: 10px; color: #2ecc71; }}
    th.desc::after {{ content: " \\25BC"; font-size: 10px; color: #e74c3c; }}
  </style>
</head>
<body>
  <h1>CAN Verification Plan — {len(rows)} requirements</h1>
  <p class="info">Click column headers to sort</p>
  <div class="wrap">
    <table>
      <thead><tr>{header_cells}</tr></thead>
      <tbody>{body}</tbody>
    </table>
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


def _md_row(values: list[str]) -> str:
    return (
        "| "
        + " | ".join(v.replace("|", "\\|").replace("\n", " ") for v in values)
        + " |"
    )


def export_markdown(rows: list[dict], path: str, cols: list[str] | None = None):
    """Export full requirements table as a Markdown pipe table."""
    cols = cols or EXPORT_COLS
    lines = [
        _md_row(cols),
        _md_row(["---"] * len(cols)),
    ] + [_md_row([row.get(c, "") for c in cols]) for row in rows]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def export_report_markdown(
    rows: list[dict],
    path: str,
    caption: str = "ISO 11898-1 verification requirements.",
    label: str = "tbl:verification-plan",
):
    """Export condensed report table as a Pandoc pipe table with caption and crossref label."""
    report_rows = [_to_report_row(r) for r in rows]
    lines = [
        _md_row(REPORT_HEADERS),
        _md_row(["---"] * len(REPORT_HEADERS)),
    ] + [_md_row([r[c] for c in REPORT_COLS]) for r in report_rows]
    lines += ["", f": {caption} {{#{label}}}"]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# -- Renumber / Delete ---------------------------------------------------------


def renumber(path: str) -> int:
    with open(path, "r") as f:
        lines = f.readlines()

    header_end = next(
        (i for i, l in enumerate(lines) if l.strip() == "[[requirement]]"), 0
    )
    header = lines[:header_end]

    blocks, current = [], []
    for line in lines[header_end:]:
        if line.strip() == "[[requirement]]" and current:
            blocks.append(current)
            current = [line]
        else:
            current.append(line)
    if current:
        blocks.append(current)

    new_lines = header[:]
    counters: dict[str, int] = {}
    for block in blocks:
        for line in block:
            m = re.search(r'id = "(.*?)(\d{3})"', line)
            if m:
                prefix = m.group(1)
                counters[prefix] = counters.get(prefix, 0) + 1
                line = re.sub(
                    r'id = "(.*?)(\d{3})"',
                    f'id = "{prefix}{counters[prefix]:03d}"',
                    line,
                )
            new_lines.append(line)

    with open(path, "w") as f:
        f.writelines(new_lines)
    return sum(counters.values())


def delete_requirement(path: str, req_id: str):
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
    print(f"Deleted {req_id}, renumbered to {count} entries")


# -- CLI -----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Manage CAN verification plan: export tables, renumber, delete",
    )
    parser.add_argument(
        "--toml", default=None, help="Path to TOML file (auto-detected if omitted)"
    )
    parser.add_argument(
        "--html",
        metavar="FILE",
        nargs="?",
        const="verification_plan.html",
        help="Save full table as HTML (default: verification_plan.html)",
    )
    parser.add_argument(
        "--markdown", metavar="FILE", help="Save full table as Markdown pipe table"
    )
    parser.add_argument(
        "--report-md",
        metavar="FILE",
        help="Save condensed Pandoc table (paraphrase, abbreviated values)",
    )
    parser.add_argument(
        "--caption",
        default="ISO 11898-1 verification requirements.",
        help="Caption for --report-md",
    )
    parser.add_argument(
        "--label",
        default="tbl:verification-plan",
        help="Pandoc crossref label for --report-md",
    )
    parser.add_argument(
        "--renumber", action="store_true", help="Renumber IDs sequentially"
    )
    parser.add_argument(
        "--delete", metavar="ID", help="Delete requirement by ID and renumber"
    )
    parser.add_argument(
        "--include",
        metavar="COL=PAT",
        action="append",
        help="Include only rows where COL contains PAT",
    )
    parser.add_argument(
        "--exclude",
        metavar="COL=PAT",
        action="append",
        help="Exclude rows where COL contains PAT",
    )
    parser.add_argument(
        "--hide",
        metavar="COL",
        action="append",
        help="Hide a column from HTML/markdown output",
    )
    args = parser.parse_args()

    toml_path = args.toml or _find_toml()

    if args.delete:
        delete_requirement(toml_path, args.delete)
        return

    if args.renumber:
        print(f"Renumbered {renumber(toml_path)} requirements")
        return

    rows = load_toml(toml_path)
    rows = apply_filters(rows, args.include, args.exclude)

    cols = EXPORT_COLS
    if args.hide:
        cols = [c for c in cols if c not in args.hide]

    if not any([args.html, args.markdown, args.report_md]):
        args.html = "verification_plan.html"

    if args.html:
        export_html(rows, args.html, cols=cols)
        print(f"Saved {len(rows)} requirements to {args.html}")

    if args.markdown:
        export_markdown(rows, args.markdown, cols=cols)
        print(f"Saved {len(rows)} requirements to {args.markdown}")

    if args.report_md:
        export_report_markdown(
            rows, args.report_md, caption=args.caption, label=args.label
        )
        print(f"Saved {len(rows)}-row report table to {args.report_md}")


if __name__ == "__main__":
    main()
