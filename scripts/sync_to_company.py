#!/usr/bin/env python3
"""
Sync local VHDL sources to company folder format.

Copies local src/<module>/hdl_src/*.vhd and hdl_tb/*.vhd into
can_bus_controller_fd/<module>/ with company-specific transformations:

  1. Adds 'use work.pk_man_global.all;' import
  2. Strips inline gen_crc entity from can_mac_crc (company has it separate)
  3. Qualifies t_eth_st_s2d/d2s with pk_eth_st package prefix
  4. Generates Riviera-PRO TCL waveform files from local GTKWave .gtkw files

Usage:
    python scripts/sync_to_company.py                      # Sync all modules
    python scripts/sync_to_company.py --dry-run             # Show what would change
    python scripts/sync_to_company.py --module can_mac_bs   # Sync one src/ module
"""

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL_SRC = ROOT / "src"
COMPANY_DIR = ROOT / "can_bus_controller_fd"
# GTKWave files are stored per-module in src/<module>/test_case/

# ── Module discovery ────────────────────────────────────────────────────────
# Auto-discover syncable modules: every directory in can_bus_controller_fd/
# that has a matching directory in src/ (by name).
# Non-module directories (e.g. doc/) are excluded automatically.

def discover_modules() -> list[str]:
    """Return sorted list of module names present in both src/ and company dir."""
    if not COMPANY_DIR.is_dir():
        return []
    company_dirs = {d.name for d in COMPANY_DIR.iterdir() if d.is_dir()}
    local_dirs = {d.name for d in LOCAL_SRC.iterdir() if d.is_dir()}
    return sorted(company_dirs & local_dirs)

# Local filename -> company filename (where they differ)
FILE_RENAME = {}


# ── Transformations ─────────────────────────────────────────────────────────

def add_pk_man_global(lines: list[str]) -> list[str]:
    """Insert 'use work.pk_man_global.all;' after numeric_std import."""
    out = []
    for line in lines:
        out.append(line)
        if re.match(r"\s*use\s+ieee\.numeric_std\.all\s*;", line):
            # Check if pk_man_global already present nearby
            if not any("pk_man_global" in l for l in lines):
                # Match indentation of the current line
                indent = re.match(r"(\s*)", line).group(1)
                out.append(f"\n{indent}use work.pk_man_global.all;\n")
    return out


def qualify_eth_st(lines: list[str]) -> list[str]:
    """Replace bare t_eth_st_s2d/d2s with pk_eth_st. qualified form."""
    out = []
    for line in lines:
        # Only qualify usage in record fields, not type definitions
        if "type t_eth_st_" in line or "end record t_eth_st_" in line:
            out.append(line)
            continue
        line = re.sub(r"(?<!pk_eth_st\.)(?<!\w)(t_eth_st_s2d)\b", "pk_eth_st.t_eth_st_s2d", line)
        line = re.sub(r"(?<!pk_eth_st\.)(?<!\w)(t_eth_st_d2s)\b", "pk_eth_st.t_eth_st_d2s", line)
        out.append(line)
    return out


def strip_eth_st_types(lines: list[str]) -> list[str]:
    """Remove inline t_eth_st_s2d and t_eth_st_d2s type definitions.

    The company version imports these from pk_eth_st instead.
    """
    out = []
    skip = False
    for line in lines:
        if re.match(r"\s*type\s+t_eth_st_(s2d|d2s)\s+is\s+record", line):
            skip = True
            continue
        if skip and re.match(r"\s*end\s+record\s+t_eth_st_(s2d|d2s)\s*;", line):
            skip = False
            continue
        if skip:
            continue
        out.append(line)
    return out


def add_eth_st_import(lines: list[str]) -> list[str]:
    """Add 'use work.pk_eth_st.all;' for the types package."""
    out = []
    for line in lines:
        out.append(line)
        if re.match(r"\s*use\s+work\.pk_can_types\.all\s*;", line):
            if not any("pk_eth_st" in l for l in lines):
                indent = re.match(r"(\s*)", line).group(1)
                out.append(f"{indent}use work.pk_eth_st.all;\n")
    return out


def insert_random_seed_init(lines: list[str]) -> list[str]:
    """Insert 'RV.InitSeed(random_seed);' after the first 'begin' in p_init."""
    out = []
    in_init = False
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted:
            if re.match(r"\s*p_init\s*:", line):
                in_init = True
            elif in_init and re.match(r"\s*begin\s*$", line):
                indent = re.match(r"(\s*)", line).group(1)
                out.append(f"{indent}  RV.InitSeed(random_seed);\n")
                inserted = True
                in_init = False
    return out


# Canonical TB import block inserted before pk_can_types:
#   library osvvm; context; scoreboard; library osvvm_common; context;
#   use work.pk_man_global.all;
#   use work.common_register_interface_pkg.all;
#   use work.common_tb_pkg.all;
COMPANY_TB_IMPORTS = """\
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_types.all;
"""


def normalize_tb_imports(lines: list[str]) -> list[str]:
    """Replace everything from 'library ieee' to 'entity' with canonical imports."""
    out = []
    skipping = False
    inserted = False
    for line in lines:
        low = line.strip().lower()
        if not skipping and low.startswith("library ieee"):
            skipping = True
            continue
        if skipping:
            if low.startswith("entity "):
                # Insert canonical imports + blank line before entity
                out.extend(l + "\n" for l in COMPANY_TB_IMPORTS.splitlines())
                out.append("\n")
                inserted = True
                skipping = False
                out.append(line)
            continue
        out.append(line)
    return out


def replace_barrier_type(lines: list[str]) -> list[str]:
    """Replace std_logic barriers with integer_barrier for company OSVVM."""
    out = []
    for line in lines:
        line = re.sub(
            r"(\bsignal\s+\w*barrier\w*\s*:\s*)std_logic(\s*:=\s*)'0'",
            r"\1integer_barrier\g<2>1",
            line,
        )
        out.append(line)
    return out


def strip_gen_crc_entity(lines: list[str]) -> list[str]:
    """Remove the gen_crc entity and architecture from can_mac_crc.vhd.

    The company has gen_crc as a separate module at modules/ip_lib/gen_crc/.
    Strips everything from 'entity gen_crc is' through 'end architecture rtl;'
    of gen_crc, plus its library/use preamble.
    """
    out = []
    skip = False
    preamble_skip = False
    i = 0
    while i < len(lines):
        line = lines[i]

        # Detect the comment and library block that precedes gen_crc
        if "-- Serial CRC engine" in line:
            preamble_skip = True
            i += 1
            continue

        if preamble_skip:
            # Skip library ieee / use ieee lines before gen_crc entity
            if re.match(r"\s*(library|use)\s+ieee", line) or line.strip() == "":
                i += 1
                continue
            if re.match(r"\s*entity\s+gen_crc\b", line):
                preamble_skip = False
                skip = True
                i += 1
                continue
            else:
                preamble_skip = False

        if skip:
            if re.match(r"\s*end\s+architecture\s+rtl\s*;", line):
                skip = False
                i += 1
                # Skip blank line after end architecture
                if i < len(lines) and lines[i].strip() == "":
                    i += 1
                continue
            i += 1
            continue

        out.append(line)
        i += 1
    return out


# ── GTKWave to Riviera-PRO TCL conversion ──────────────────────────────────

# GTKWave display flags -> Riviera-PRO wave type
# @28/@29 = single-bit logic, @22 = hex/literal (vectors), @420/@421 = decimal/enum
GTKW_TYPE_MAP = {
    0x28: "-logic",
    0x29: "-logic",
    0x22: "-literal",
    0x420: "-decimal",
    0x421: "-decimal",
}

# Group open/close markers
GTKW_GROUP_OPEN = {0xC00200, 0x800200, 0x800201}
GTKW_GROUP_CLOSE = {0x1401200, 0x1000200, 0x1000201}


def gtkw_to_tcl(gtkw_path: Path) -> str:
    """Convert a GTKWave .gtkw save file to a Riviera-PRO TCL waveform script."""
    lines = gtkw_path.read_text().splitlines()

    groups: list[tuple[str, list[tuple[str, str]]]] = []
    current_type = "-logic"
    current_group_name: str | None = None
    current_signals: list[tuple[str, str]] = []

    for line in lines:
        line = line.strip()

        # Display type flag
        if line.startswith("@"):
            try:
                flag = int(line[1:], 16)
            except ValueError:
                continue
            if flag in GTKW_TYPE_MAP:
                current_type = GTKW_TYPE_MAP[flag]
            elif flag in GTKW_GROUP_OPEN:
                pass  # group name comes on the next signal-like line
            elif flag in GTKW_GROUP_CLOSE:
                if current_group_name is not None:
                    groups.append((current_group_name, current_signals))
                    current_group_name = None
                    current_signals = []
            continue

        # Group name line (prefixed with - in gtkw)
        if line.startswith("-"):
            name = line[1:].strip()
            if current_group_name is not None and current_signals:
                groups.append((current_group_name, current_signals))
            current_group_name = name
            current_signals = []
            continue

        # Skip gtkw metadata, color, composite signals (#{ ... })
        if (line.startswith("[") or line.startswith("*") or line.startswith("#")
                or line.startswith("(") or not line):
            continue

        # Signal path: top.entity.signal -> /entity/signal
        if line.startswith("top."):
            sig_path = "/" + line[4:].replace(".", "/")
            # Expand bit-slice notation: signal[0] is fine as-is
            current_signals.append((current_type, sig_path))

    # Flush last group
    if current_group_name is not None and current_signals:
        groups.append((current_group_name, current_signals))

    # Build TCL output
    tcl_lines = [
        "onerror { resume }",
        "set curr_transcript [transcript]",
        "transcript off",
        "",
    ]

    for group_name, signals in groups:
        if not signals:
            continue
        # Quote group name if it contains spaces
        gname = f'"{group_name}"' if " " in group_name else group_name
        tcl_lines.append(f"add wave -vgroup {gname} \\")
        for i, (wtype, spath) in enumerate(signals):
            cont = " \\" if i < len(signals) - 1 else ""
            tcl_lines.append(f"\t( {wtype} {spath} ){cont}")
        tcl_lines.append("")

    tcl_lines.extend([
        "wv.cursors.add -time 0ns -name {Default cursor}",
        "wv.cursors.setactive -name {Default cursor}",
        "wv.zoom.range -from 0ns -to 100000ns",
        "wv.time.unit.auto.set",
        "transcript $curr_transcript",
        "",
    ])

    return "\n".join(tcl_lines)


# ── Core sync logic ─────────────────────────────────────────────────────────

def transform(content: str, module: str, filename: str) -> str:
    """Apply all company transformations to a VHDL file."""
    lines = content.splitlines(keepends=True)

    # Types package gets special treatment
    if module == "can_types_p" and "can_types_p" in filename and "_tb" not in filename:
        lines = strip_eth_st_types(lines)
        lines = qualify_eth_st(lines)
        lines = add_pk_man_global(lines)
        # Don't add pk_eth_st import to types pkg itself - it uses work.pk_eth_st qualification
        return "".join(lines)

    # CRC module: strip gen_crc entity
    if module == "can_mac_crc" and "_tb" not in filename:
        lines = strip_gen_crc_entity(lines)

    # TB files: normalize imports and replace seed initialisation
    if "_tb" in filename:
        lines = normalize_tb_imports(lines)
        lines = insert_random_seed_init(lines)
        lines = replace_barrier_type(lines)
        return "".join(lines)

    lines = add_pk_man_global(lines)
    return "".join(lines)


def sync_module(module: str, dry_run: bool = False) -> int:
    """Sync one module. Returns number of files synced."""
    local_dir = LOCAL_SRC / module
    company_dir = COMPANY_DIR / module

    if not local_dir.is_dir():
        print(f"  SKIP {module}: not found in src/")
        return 0
    if not company_dir.is_dir():
        print(f"  SKIP {module}: not found in {COMPANY_DIR.name}/")
        return 0
    synced = 0

    for subdir in ("hdl_src", "hdl_tb"):
        local_sub = local_dir / subdir
        company_sub = company_dir / subdir
        if not local_sub.exists():
            continue

        for vhd_file in sorted(local_sub.glob("*.vhd")):
            # Determine company filename (may differ)
            company_filename = FILE_RENAME.get(vhd_file.name, vhd_file.name)
            company_path = company_sub / company_filename

            content = vhd_file.read_text()
            transformed = transform(content, module, vhd_file.name)

            if dry_run:
                if company_path.exists():
                    existing = company_path.read_text()
                    if existing == transformed:
                        print(f"  UNCHANGED {company_path.relative_to(ROOT)}")
                    else:
                        print(f"  WOULD UPDATE {company_path.relative_to(ROOT)}")
                else:
                    print(f"  WOULD CREATE {company_path.relative_to(ROOT)}")
            else:
                company_sub.mkdir(parents=True, exist_ok=True)
                company_path.write_text(transformed)
                print(f"  SYNCED {company_path.relative_to(ROOT)}")
            synced += 1

    # Generate TCL waveform files from local GTKWave .gtkw files
    local_test_case = local_dir / "test_case"
    if not local_test_case.exists():
        return synced
    for gtkw_file in sorted(local_test_case.glob("*.gtkw")):

        tcl_name = f"sim_wave_{module}.tcl"
        tcl_path = company_dir / "test_case" / tcl_name
        tcl_content = gtkw_to_tcl(gtkw_file)

        if dry_run:
            if tcl_path.exists():
                if tcl_path.read_text() == tcl_content:
                    print(f"  UNCHANGED {tcl_path.relative_to(ROOT)}")
                else:
                    print(f"  WOULD UPDATE {tcl_path.relative_to(ROOT)}")
            else:
                print(f"  WOULD CREATE {tcl_path.relative_to(ROOT)}")
        else:
            tcl_path.parent.mkdir(parents=True, exist_ok=True)
            tcl_path.write_text(tcl_content)
            print(f"  SYNCED {tcl_path.relative_to(ROOT)}")
        synced += 1

    return synced


def main():
    parser = argparse.ArgumentParser(description="Sync local VHDL to company folder")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change")
    parser.add_argument("--module", help="Sync only this src/ module (default: all matching)")
    args = parser.parse_args()

    modules = [args.module] if args.module else discover_modules()
    total = 0

    for module in modules:
        print(f"\n[{module}]")
        total += sync_module(module, dry_run=args.dry_run)

    action = "would sync" if args.dry_run else "synced"
    print(f"\nDone: {action} {total} files.")


if __name__ == "__main__":
    main()
