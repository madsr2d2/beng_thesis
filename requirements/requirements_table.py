"""
requirements_table.py  —  View and filter CAN requirements from TOML

Usage:
    python requirements_table.py
    python requirements_table.py --status Verified
    python requirements_table.py --status Implemented --status Diagnostic
    python requirements_table.py --format FB
    python requirements_table.py --cat ERR
    python requirements_table.py --cat FRM --status Verified
    python requirements_table.py --side RX
    python requirements_table.py --priority H
    python requirements_table.py --search "bit rate"
"""

import argparse
import tomllib
import pandas as pd
from rich.console import Console
from rich.table import Table
from rich import box
from rich.text import Text

# -- Colour scheme --

STATUS_COLORS = {
    "Verified":       "bold green",
    "Implemented":    "yellow",
    "Diagnostic":     "orange1",
    "Partially":      "dark_orange",
    "Not Applicable": "grey50",
    "Not Started":    "bold red",
    "":               "grey50",
}

PRIORITY_COLORS = {
    "C": "bold green",
    "H": "yellow",
    "M": "grey70",
    "":  "grey50",
}

CATEGORY_COLORS = {
    "FRM": "bold cyan",
    "TMG": "bold blue",
    "ERR": "bold red",
    "CRC": "bold magenta",
}

# -- TOML -> DataFrame --

def load_toml(path: str) -> pd.DataFrame:
    with open(path, "rb") as f:
        raw = tomllib.load(f)

    rows = []
    for req_id, fields in raw["requirements"].items():
        # Parse ID into components
        import re
        m = re.match(r'([A-Z]+)(\d+)(TX|RX|SYS)', req_id)
        cat  = m.group(1) if m else ""
        num  = m.group(2) if m else ""
        side = m.group(3) if m else ""

        rows.append({
            "id":                 req_id,
            "cat":                cat,
            "side":               side,
            "description":        fields.get("description", ""),
            "iso_reference":      fields.get("iso_reference", ""),
            "format":             "/".join(fields.get("format", [])),
            "status":             fields.get("status", ""),
            "priority":           fields.get("priority", ""),
            "tests":              fields.get("tests", ""),
            "acceptance_criteria":fields.get("acceptance_criteria", ""),
            "verification":       fields.get("verification", ""),
            "dependencies":       ", ".join(fields.get("dependencies", [])),
            "notes":              fields.get("notes", ""),
        })

    return pd.DataFrame(rows)

# -- Filtering --

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
            df["description"].str.contains(args.search, case=False, na=False) |
            df["notes"].str.contains(args.search, case=False, na=False) |
            df["acceptance_criteria"].str.contains(args.search, case=False, na=False)
        )
        df = df[mask]
    return df

# -- Rich display --

def truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[:n-1] + "…"

def styled(text: str, style: str) -> Text:
    t = Text(text)
    t.stylize(style)
    return t

def display_table(df: pd.DataFrame, console: Console):
    table = Table(
        box=box.ROUNDED,
        show_header=True,
        header_style="bold white on grey23",
        highlight=True,
        expand=False,
        padding=(0, 1),
    )

    table.add_column("ID",          style="bold", width=12, no_wrap=True)
    table.add_column("Description", width=50,  no_wrap=True)
    table.add_column("Fmt",         width=11,  no_wrap=True)
    table.add_column("Status",      width=15,  no_wrap=True)
    table.add_column("P",           width=3,   justify="center", no_wrap=True)
    table.add_column("Tests",       width=12,  no_wrap=True)
    table.add_column("Verif",       width=6,   justify="center", no_wrap=True)
    table.add_column("Deps",        width=16,  no_wrap=True)
    table.add_column("Notes",       width=28,  no_wrap=True)

    prev_cat = None
    for _, row in df.iterrows():
        # Section divider when category changes
        if row["cat"] != prev_cat:
            cat_label = {
                "FRM": "Frame / Arbitration / Control",
                "TMG": "Bit Timing & TDC",
                "ERR": "Error Detection & Handling",
                "CRC": "CRC Generation",
            }.get(row["cat"], row["cat"])
            color = CATEGORY_COLORS.get(row["cat"], "white")
            table.add_section()
            # Empty divider row with category label
            table.add_row(
                styled(f"── {cat_label} ──", color),
                "", "", "", "", "", "", "", "",
            )
            table.add_section()
            prev_cat = row["cat"]

        status_style  = STATUS_COLORS.get(row["status"], "white")
        priority_style = PRIORITY_COLORS.get(row["priority"], "white")
        cat_style     = CATEGORY_COLORS.get(row["cat"], "white")

        table.add_row(
            styled(row["id"], cat_style),
            truncate(row["description"], 44),
            row["format"],
            styled(row["status"], status_style),
            styled(row["priority"], priority_style),
            row["tests"] or "",
            row["verification"] or "",
            truncate(row["dependencies"], 14),
            truncate(row["notes"], 24),
        )

    console.print(table)

def display_summary(df: pd.DataFrame, console: Console):
    total = len(df)
    console.print(f"\n[bold]Total:[/bold] {total} requirements\n")

    # Status breakdown
    status_counts = df["status"].value_counts()
    console.print("[bold]By status:[/bold]")
    for status, count in status_counts.items():
        color = STATUS_COLORS.get(status, "white")
        pct = 100 * count / total if total else 0
        bar = "█" * int(pct / 2)
        console.print(f"  [{color}]{status:<16}[/{color}]  {count:>3}  {pct:>5.1f}%  {bar}")

    # Category breakdown
    console.print("\n[bold]By category:[/bold]")
    for cat, grp in df.groupby("cat"):
        color = CATEGORY_COLORS.get(cat, "white")
        sides = grp["side"].value_counts().to_dict()
        side_str = "  ".join(f"{s}:{n}" for s, n in sorted(sides.items()))
        console.print(f"  [{color}]{cat}[/{color}]  {len(grp):>3} reqs   {side_str}")

# -- CLI --

def main():
    parser = argparse.ArgumentParser(description="View CAN requirements from TOML")
    parser.add_argument("--toml",     default="requirements.toml", help="Path to TOML file")
    parser.add_argument("--status",   action="append", help="Filter by status (repeatable)")
    parser.add_argument("--format",   help="Filter by format code e.g. FB")
    parser.add_argument("--cat",      help="Filter by category: FRM, TMG, ERR, CRC")
    parser.add_argument("--side",     help="Filter by side: TX or RX")
    parser.add_argument("--priority", help="Filter by priority: C, H, M")
    parser.add_argument("--search",   help="Search description/notes/acceptance criteria")
    parser.add_argument("--summary",  action="store_true", help="Show summary stats only")
    parser.add_argument("--html",     metavar="FILE",      help="Save output as HTML e.g. requirements.html")
    parser.add_argument("--markdown", metavar="FILE",      help="Save output as markdown table e.g. requirements.md")
    args = parser.parse_args()

    import io
    export_only = bool(args.markdown and not args.html)
    console = Console()
    html_console = Console(record=True, file=io.StringIO()) if args.html else None

    df = load_toml(args.toml)
    df = apply_filters(df, args)

    if df.empty:
        console.print("[bold red]No requirements match the given filters.[/bold red]")
        return

    if not args.summary and not export_only:
        display_table(df, console)
        if html_console:
            display_table(df, html_console)
            display_summary(df, html_console)

    if not export_only:
        display_summary(df, console)

    if args.html:
        html_console.save_html(args.html)
        print(f"Saved to {args.html}")

    if args.markdown:
        export_cols = ["id", "description", "iso_reference", "format", "status",
                       "priority", "tests", "acceptance_criteria", "verification",
                       "dependencies", "notes"]
        out = df[export_cols].fillna("")
        header = "| " + " | ".join(out.columns) + " |"
        sep    = "| " + " | ".join(["---"] * len(out.columns)) + " |"
        rows   = ["| " + " | ".join(str(v) for v in row) + " |"
                  for _, row in out.iterrows()]
        md = "\n".join([header, sep] + rows)
        with open(args.markdown, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"Saved to {args.markdown}")

if __name__ == "__main__":
    main()