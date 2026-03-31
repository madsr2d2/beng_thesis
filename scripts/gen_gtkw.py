#!/usr/bin/env python3
"""
Generate GTKWave .gtkw save files from GHDL GHW waveform hierarchy.

Parses the signal hierarchy from a GHW file (via ghwdump -h) and generates
a grouped GTKWave save file with appropriate display types.

Usage (called by Makefile):
    python scripts/gen_gtkw.py sim/<tb>.ghw gtk_wave/<tb>.gtkw

Signal grouping:
  1. TB-level signals (clk, reset, test controls)
  2. One group per DUT port record (interface groups)
  3. One group per DUT sub-component instance (internals)

Display type mapping:
  std_logic / std_ulogic / boolean  -> @28 (logic bit)
  std_logic_vector / std_ulogic_vector / integer range -> @22 (hex)
  enum types / integer              -> @420 (decimal/symbolic)
"""

import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ── Signal type classification ─────────────────────────────────────────────

# Types displayed as single-bit logic (@28)
LOGIC_TYPES = {"std_logic", "std_ulogic", "boolean", "bit"}

# Types displayed as hex vectors (@22)
VECTOR_RE = re.compile(
    r"std_u?logic_vector|std_ulogic_vector|unsigned|signed|"
    r"t_byte|t_crc_vector|t_fifo_index_vec|t_tdc_polarity_history"
)

# Types displayed as decimal/symbolic (@420)
ENUM_RE = re.compile(
    r"^(integer|natural|positive|t_\w+|character)$"
)

# OSVVM and internal types to skip entirely
SKIP_RE = re.compile(
    r"streamrectype|coverageidtype|alertlogidtype|randomp|"
    r"predefinedbarriertype|scoreboard"
)


def classify_type(type_str: str) -> str:
    """Return GTKWave display flag for a VHDL type string."""
    t = type_str.lower().strip()
    if SKIP_RE.search(t):
        return "@skip"
    # Vectors before scalars (std_ulogic_vector contains std_ulogic)
    if VECTOR_RE.search(t):
        return "@22"
    if any(re.search(rf"\b{lt}\b", t) for lt in LOGIC_TYPES):
        return "@28"
    if "integer" in t or "natural" in t or "positive" in t:
        return "@420"
    # Record or enum types starting with t_
    if t.startswith("t_"):
        return "@420"
    return "@22"


# ── GHW hierarchy parsing ─────────────────────────────────────────────────

@dataclass
class Signal:
    name: str
    type_str: str
    display: str  # GTKWave flag


@dataclass
class Instance:
    name: str
    signals: list[Signal] = field(default_factory=list)
    children: list["Instance"] = field(default_factory=list)


def parse_ghw_hierarchy(ghw_path: Path) -> Instance | None:
    """Run ghwdump -h and parse the hierarchy into a tree."""
    result = subprocess.run(
        ["ghwdump", "-h", str(ghw_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Error: ghwdump failed: {result.stderr}", file=sys.stderr)
        return None

    lines = result.stdout.splitlines()
    root: Instance | None = None
    stack: list[tuple[int, Instance]] = []

    for line in lines:
        # Skip package lines
        if line.strip().startswith("package ") or line.strip().startswith("design"):
            continue
        if line.strip().startswith("process "):
            continue

        # Determine indentation level
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        # Instance line: "instance <name>:"
        m = re.match(r"instance\s+(\w+)\s*:", stripped)
        if m:
            inst = Instance(name=m.group(1))
            if root is None:
                root = inst
                stack = [(indent, inst)]
            else:
                # Find parent by indentation
                while stack and stack[-1][0] >= indent:
                    stack.pop()
                if stack:
                    stack[-1][1].children.append(inst)
                stack.append((indent, inst))
            continue

        # Signal or port line
        m = re.match(
            r"(?:signal|port-in|port-out|port-inout)\s+(\w+)\s*:\s*(.+?):\s*#",
            stripped,
        )
        if m and stack:
            sig_name = m.group(1)
            type_str = m.group(2).strip()
            display = classify_type(type_str)
            if display == "@skip":
                continue
            stack[-1][1].signals.append(Signal(sig_name, type_str, display))

    return root


# ── GTKWave .gtkw generation ──────────────────────────────────────────────

def make_gtkw_path(tb_name: str, *parts: str) -> str:
    """Build a GTKWave signal path: top.tb_name.part1.part2..."""
    return "top." + ".".join([tb_name] + list(parts))


def write_group(lines: list[str], name: str, signals: list[tuple[str, str]]) -> None:
    """Write a GTKWave signal group."""
    if not signals:
        return
    lines.append("@c00200")
    lines.append(f"-{name}")
    for display, path in signals:
        lines.append(display)
        lines.append(path)
    lines.append("@1401200")
    lines.append(f"-{name}")


def generate_gtkw(root: Instance, ghw_path: Path, gtkw_path: Path) -> None:
    """Generate a .gtkw save file from the parsed hierarchy."""
    tb_name = root.name
    lines: list[str] = []

    # Header
    lines.extend([
        "[*]",
        f"[*] GTKWave save file - auto-generated from {ghw_path.name}",
        "[*]",
        f"[dumpfile] \"{ghw_path.resolve()}\"",
        f"[savefile] \"{gtkw_path.resolve()}\"",
        "[timestart] 0",
        "[size] 1920 1080",
        "[pos] 0 0",
        "*-28.000000 0 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1",
        f"[treeopen] top.",
        f"[treeopen] top.{tb_name}.",
        "[sst_width] 297",
        "[signals_width] 412",
        "[sst_expanded] 1",
        "[sst_vpaned_height] 434",
    ])

    # Add treeopen for DUT instances
    for child in root.children:
        lines.append(f"[treeopen] top.{tb_name}.{child.name}.")
        for grandchild in child.children:
            lines.append(
                f"[treeopen] top.{tb_name}.{child.name}.{grandchild.name}."
            )

    # Group 1: TB-level signals (clk, reset, controls - not OSVVM internals)
    tb_sigs = []
    for sig in root.signals:
        path = make_gtkw_path(tb_name, sig.name)
        tb_sigs.append((sig.display, path))
    write_group(lines, "TB Signals", tb_sigs)

    # Groups for DUT instances
    for dut in root.children:
        # DUT port signals (interface groups)
        port_sigs = []
        for sig in dut.signals:
            path = make_gtkw_path(tb_name, dut.name, sig.name)
            port_sigs.append((sig.display, path))
        if port_sigs:
            write_group(lines, f"{dut.name} Internals", port_sigs)

        # Sub-component instances
        for sub in dut.children:
            sub_sigs = []
            for sig in sub.signals:
                path = make_gtkw_path(tb_name, dut.name, sub.name, sig.name)
                sub_sigs.append((sig.display, path))
            if sub_sigs:
                write_group(lines, f"{sub.name}", sub_sigs)

    lines.extend([
        "[pattern_trace] 1",
        "[pattern_trace] 0",
        "",
    ])

    gtkw_path.write_text("\n".join(lines))


# ── Main ───────────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <ghw_file> <gtkw_output>", file=sys.stderr)
        sys.exit(1)

    ghw_path = Path(sys.argv[1])
    gtkw_path = Path(sys.argv[2])

    if not ghw_path.exists():
        print(f"Error: GHW file not found: {ghw_path}", file=sys.stderr)
        sys.exit(1)

    root = parse_ghw_hierarchy(ghw_path)
    if root is None:
        sys.exit(1)

    gtkw_path.parent.mkdir(parents=True, exist_ok=True)
    generate_gtkw(root, ghw_path, gtkw_path)
    print(f"Generated {gtkw_path}")


if __name__ == "__main__":
    main()
