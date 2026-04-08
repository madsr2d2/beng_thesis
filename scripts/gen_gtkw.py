#!/usr/bin/env python3
"""
Generate organized, color-coded GTKWave .gtkw save files from a GHW waveform.

Parses the signal hierarchy with ``ghwdump -h`` and emits a grouped save file:

  * TB signals (clk/reset, interface records, override signals)          - red
  * Per DUT instance: Inputs (blue), Outputs (green), Internals (yellow)
  * Sub-components recursively (color cycles)

Display type mapping:
  std_logic / std_ulogic / boolean    -> @28   (logic bit)
  std_logic_vector / unsigned / ...   -> @22   (hex vector)
  integer / natural / t_* records etc -> @420  (symbolic/decimal)

Usage (from Makefile):
    python scripts/gen_gtkw.py sim/<tb>.ghw src/<mod>/test_case/<tb>.gtkw
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ── Signal type classification ────────────────────────────────────────────

LOGIC_TYPES = {"std_logic", "std_ulogic", "boolean", "bit"}

VECTOR_RE = re.compile(
    r"std_u?logic_vector|unsigned|signed|"
    r"t_byte|t_crc_vector|t_fifo_index_vec|t_tdc_polarity_history"
)

SKIP_RE = re.compile(
    r"streamrectype|coverageidtype|alertlogidtype|randomp|"
    r"predefinedbarriertype|scoreboard|messagelist"
)


def classify_type(type_str: str) -> str:
    """Return the GTKWave display flag for a VHDL type string."""
    t = type_str.lower().strip()
    if SKIP_RE.search(t):
        return "@skip"
    if VECTOR_RE.search(t):
        return "@22"
    if any(re.search(rf"\b{lt}\b", t) for lt in LOGIC_TYPES):
        return "@28"
    if "integer" in t or "natural" in t or "positive" in t:
        return "@28"  # scalar integers - show as value
    if t.startswith("t_"):
        return "@22"  # record types - expand as hex
    return "@22"


# ── Colours ───────────────────────────────────────────────────────────────
# GTKWave trace colours: 0=normal, 1=red, 2=orange, 3=yellow, 4=green,
# 5=blue, 6=indigo, 7=violet.

COLOR_TB       = 1  # red
COLOR_INPUT    = 5  # blue
COLOR_OUTPUT   = 4  # green
COLOR_INTERNAL = 3  # yellow


# ── Hierarchy parsing ─────────────────────────────────────────────────────

@dataclass
class Signal:
    name: str
    type_str: str
    display: str
    kind: str  # "signal" | "port-in" | "port-out" | "port-inout"


@dataclass
class Instance:
    name: str
    signals: list[Signal] = field(default_factory=list)
    children: list["Instance"] = field(default_factory=list)


_INSTANCE_RE = re.compile(r"instance\s+(\w+)\s*:")
_SIGNAL_RE = re.compile(
    r"(signal|port-in|port-out|port-inout)\s+(\w+)\s*:\s*(.+?):\s*#"
)


def parse_ghw_hierarchy(ghw_path: Path) -> Instance | None:
    result = subprocess.run(
        ["ghwdump", "-h", str(ghw_path)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"Error: ghwdump failed: {result.stderr}", file=sys.stderr)
        return None

    root: Instance | None = None
    stack: list[tuple[int, Instance]] = []

    for line in result.stdout.splitlines():
        stripped = line.lstrip()
        if not stripped:
            continue
        if stripped.startswith(("package ", "design", "process ")):
            continue
        indent = len(line) - len(stripped)

        m = _INSTANCE_RE.match(stripped)
        if m:
            inst = Instance(name=m.group(1))
            if root is None:
                root = inst
                stack = [(indent, inst)]
            else:
                while stack and stack[-1][0] >= indent:
                    stack.pop()
                if stack:
                    stack[-1][1].children.append(inst)
                stack.append((indent, inst))
            continue

        m = _SIGNAL_RE.match(stripped)
        if m and stack:
            kind = m.group(1)
            name = m.group(2)
            type_str = m.group(3).strip()
            display = classify_type(type_str)
            if display == "@skip":
                continue
            stack[-1][1].signals.append(Signal(name, type_str, display, kind))

    return root


# ── .gtkw emission ────────────────────────────────────────────────────────

def _path(*parts: str) -> str:
    return "top." + ".".join(parts)


def _write_group(
    lines: list[str],
    name: str,
    color: int,
    sigs: list[tuple[str, str]],
) -> None:
    if not sigs:
        return
    # Group open marker (GTKWave: TR_BLANK | TR_GRP_BEGIN | highlight)
    lines.append("@c00200")
    lines.append(f"-{name}")
    lines.append(f"[color] {color}")
    for display, path in sigs:
        lines.append(display)
        lines.append(path)
    # Group close marker (GTKWave: TR_BLANK | TR_GRP_END | highlight)
    lines.append("@1401200")
    lines.append(f"-{name}")


def _split_ports(inst: Instance) -> tuple[list[Signal], list[Signal], list[Signal]]:
    inputs  = [s for s in inst.signals if s.kind == "port-in"]
    outputs = [s for s in inst.signals if s.kind in ("port-out", "port-inout")]
    internals = [s for s in inst.signals if s.kind == "signal"]
    return inputs, outputs, internals


def _emit_instance(
    lines: list[str],
    inst: Instance,
    path_prefix: tuple[str, ...],
    depth: int = 0,
) -> None:
    inputs, outputs, internals = _split_ports(inst)
    base = path_prefix + (inst.name,)

    def _sigs(group: list[Signal]) -> list[tuple[str, str]]:
        return [(s.display, _path(*base, s.name)) for s in group]

    header = "/".join(base[1:]) if len(base) > 1 else base[0]

    _write_group(lines, f"{header} :: inputs",    COLOR_INPUT,    _sigs(inputs))
    _write_group(lines, f"{header} :: outputs",   COLOR_OUTPUT,   _sigs(outputs))
    _write_group(lines, f"{header} :: internals", COLOR_INTERNAL, _sigs(internals))

    for child in inst.children:
        _emit_instance(lines, child, base, depth + 1)


def generate_gtkw(root: Instance, ghw_path: Path, gtkw_path: Path) -> None:
    tb_name = root.name
    lines: list[str] = []

    # ── Header ────────────────────────────────────────────────────────────
    lines.extend([
        "[*]",
        f"[*] GTKWave save file - auto-generated from {ghw_path.name}",
        "[*]",
        f"[dumpfile] \"{ghw_path.resolve()}\"",
        f"[savefile] \"{gtkw_path.resolve()}\"",
        "[timestart] 0",
        "[size] 1920 1080",
        "[pos] 0 0",
        "*-22.000000 0 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1",
        "[treeopen] top.",
        f"[treeopen] top.{tb_name}.",
        "[sst_width] 320",
        "[signals_width] 460",
        "[sst_expanded] 1",
        "[sst_vpaned_height] 480",
    ])
    for child in root.children:
        lines.append(f"[treeopen] top.{tb_name}.{child.name}.")
        for grand in child.children:
            lines.append(f"[treeopen] top.{tb_name}.{child.name}.{grand.name}.")

    # ── TB group (always open, red) ───────────────────────────────────────
    tb_sigs = [
        (s.display, _path(tb_name, s.name))
        for s in root.signals
        if s.kind == "signal"
    ]
    _write_group(lines, f"{tb_name} :: TB", COLOR_TB, tb_sigs)

    # ── DUT instances (open) and sub-components (closed) ──────────────────
    for dut in root.children:
        _emit_instance(lines, dut, (tb_name,), depth=0)

    lines.extend(["[pattern_trace] 1", "[pattern_trace] 0", ""])
    gtkw_path.write_text("\n".join(lines))


# ── Main ──────────────────────────────────────────────────────────────────

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
