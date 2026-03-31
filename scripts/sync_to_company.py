#!/usr/bin/env python3
"""
Sync local VHDL sources to company folder format.

Copies local src/<module>/hdl_src/*.vhd and hdl_tb/*.vhd into
can_bus_controller_fd/<module>/ with company-specific transformations:

  1. Adds 'use work.pk_man_global.all;' import
  2. Strips inline gen_crc entity from can_mac_crc (company has it separate)
  3. Qualifies t_eth_st_s2d/d2s with pk_eth_st package prefix

Usage:
    python scripts/sync_to_company.py           # Sync all modules
    python scripts/sync_to_company.py --dry-run  # Show what would change
    python scripts/sync_to_company.py --module can_mac_bs  # Sync one module
"""

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL_SRC = ROOT / "src"
COMPANY_DIR = ROOT / "can_bus_controller_fd"

# ── Module mapping ──────────────────────────────────────────────────────────
# local folder name -> company folder name
# Only modules that exist in the company folder are synced.
MODULE_MAP = {
    "can_types_p":    "can_types_p",
    "can_mac_bs":     "can_mac_bs",
    "can_mac_crc":    "can_mac_crc",
    "can_mac_ser_tx": "can_mac_ser_tx",
    "can_mac_fsm_tx": "can_mac_fsm_tx",
    "can_mac_tx":     "can_mac_tx",
}

# Local filename -> company filename (where they differ)
FILE_RENAME = {
    "can_types_pkg.vhd":    "can_types_p.vhd",
    "can_types_pkg_tb.vhd": "can_types_p_tb.vhd",
}


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


def add_company_tb_imports(lines: list[str]) -> list[str]:
    """Add company TB package imports after pk_can_types for testbench files."""
    out = []
    for line in lines:
        out.append(line)
        if re.match(r"\s*use\s+work\.pk_can_types\.all\s*;", line):
            if not any("common_register_interface_pkg" in l for l in lines):
                indent = re.match(r"(\s*)", line).group(1)
                out.insert(-1, f"{indent}use work.common_register_interface_pkg.all;\n")
                out.insert(-1, f"{indent}use work.common_tb_pkg.all;\n")
    return out


def replace_initseed_with_random_seed(lines: list[str]) -> list[str]:
    """Replace local OSVVM seed calls with company random_seed constant."""
    out = []
    for line in lines:
        # Match patterns like: rv.InitSeed(rv'instance_name); or
        # rnd.InitSeed(rnd'instance_name & to_string(now));
        new_line = re.sub(
            r"(\w+)\.InitSeed\((?:[^()]*\([^()]*\))*[^()]*\)",
            r"\1.InitSeed(random_seed)",
            line,
        )
        out.append(new_line)
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


# ── Core sync logic ─────────────────────────────────────────────────────────

def transform(content: str, module: str, filename: str) -> str:
    """Apply all company transformations to a VHDL file."""
    lines = content.splitlines(keepends=True)

    # Types package gets special treatment
    if module == "can_types_p" and "can_types_pkg" in filename:
        lines = strip_eth_st_types(lines)
        lines = qualify_eth_st(lines)
        lines = add_pk_man_global(lines)
        # Don't add pk_eth_st import to types pkg itself - it uses work.pk_eth_st qualification
        return "".join(lines)

    # CRC module: strip gen_crc entity
    if module == "can_mac_crc" and "_tb" not in filename:
        lines = strip_gen_crc_entity(lines)

    # TB files: add company imports and replace seed initialisation
    if "_tb" in filename:
        lines = add_company_tb_imports(lines)
        lines = replace_initseed_with_random_seed(lines)

    lines = add_pk_man_global(lines)
    return "".join(lines)


def sync_module(module: str, dry_run: bool = False) -> int:
    """Sync one module. Returns number of files synced."""
    company_name = MODULE_MAP.get(module)
    if not company_name:
        print(f"  SKIP {module}: not in company mapping")
        return 0

    local_dir = LOCAL_SRC / module
    company_dir = COMPANY_DIR / company_name
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

    return synced


def main():
    parser = argparse.ArgumentParser(description="Sync local VHDL to company folder")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change")
    parser.add_argument("--module", help="Sync only this module")
    args = parser.parse_args()

    modules = [args.module] if args.module else list(MODULE_MAP.keys())
    total = 0

    for module in modules:
        print(f"\n[{module}]")
        total += sync_module(module, dry_run=args.dry_run)

    action = "would sync" if args.dry_run else "synced"
    print(f"\nDone: {action} {total} files.")


if __name__ == "__main__":
    main()
