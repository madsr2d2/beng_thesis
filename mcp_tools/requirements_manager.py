#!/usr/bin/env python3
"""
CAN Requirements MCP Server

Manages ISO-aligned requirements in TOML format.
Handles querying, updating, inserting, deleting, and validating requirements.

Format structure:
  [[requirement]]
  id = "REQ-LLC-001"
  shape = "invariant" | "triggered" | "liveness" | "reachability"
  scope = "frame" | "node" | "bus"
  layer = "LLC" | "MAC" | "PCS" | "FCE"
  flags = ["COMPOUND", "AMBIGUOUS", "EXTERNAL_DEP", "SHOULD", "DOC_ONLY"]
  label = ""  # PSL assertion label or testbench procedure name
  file = ""   # Target VHDL source file
  ... etc ...

Usage:
    python -m mcp_tools.requirements_manager
"""

import logging
import sys
from collections import Counter
from pathlib import Path
from typing import Optional

import tomlkit
from mcp.server.fastmcp import FastMCP

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
_PROJECT_ROOT = Path(__file__).parent.parent
_REQUIREMENTS_DIR = _PROJECT_ROOT / "requirements"

# ── FastMCP Server ────────────────────────────────────────────────────────────
mcp = FastMCP("requirements")


# ── Requirements Manager ─────────────────────────────────────────────────────


class RequirementsManager:
    """Manager for ISO-aligned CAN requirements using tomlkit."""

    VALID_SHAPES = {"triggered", "invariant", "liveness", "reachability"}
    VALID_SCOPES = {"frame", "node", "bus"}
    VALID_LAYERS = {"LLC", "MAC", "PCS", "FCE"}
    VALID_FLAGS = {"COMPOUND", "AMBIGUOUS", "EXTERNAL_DEP", "SHOULD", "DOC_ONLY"}
    VALID_FIELD_UPDATES = {
        "shape",
        "scope",
        "layer",
        "side",
        "flags",
        "notes",
        "label",
        "file",
        "precondition",
        "event",
        "postcondition",
        "coverage_target",
        "original_wording",
        "source_clause",
        "format_applicability",
    }

    def __init__(self, toml_path: Path):
        self.toml_path = Path(toml_path)
        self.backup_path = self.toml_path.with_suffix(".toml.bak")

        if not self.toml_path.exists():
            raise FileNotFoundError(f"Requirements file not found: {self.toml_path}")
        logger.info(f"RequirementsManager ready: {self.toml_path}")

    def _load(self) -> dict:
        """Load TOML preserving comments and formatting."""
        with open(self.toml_path, "r") as f:
            return tomlkit.parse(f.read())

    def _save(self, data: dict) -> None:
        """Write TOML back preserving comments and formatting."""
        with open(self.toml_path, "w") as f:
            f.write(tomlkit.dumps(data))
        logger.info(f"Saved: {self.toml_path}")

    def _backup(self) -> None:
        self.toml_path.read_text()  # Verify readable
        self.backup_path.write_text(self.toml_path.read_text())
        logger.info(f"Backup: {self.backup_path}")

    def query(
        self,
        shape: Optional[str] = None,
        scope: Optional[str] = None,
        layer: Optional[str] = None,
        side: Optional[str] = None,
        has_flags: Optional[str] = None,
        is_blank_label: Optional[bool] = None,
        is_blank_file: Optional[bool] = None,
    ) -> list[dict]:
        """Query requirements by shape, scope, layer, side, and flags."""
        data = self._load()
        requirements = data.get("requirement", [])

        filters = {}
        if shape:
            filters["shape"] = shape
        if scope:
            filters["scope"] = scope
        if layer:
            filters["layer"] = layer
        if side:
            filters["side"] = side

        results = []
        for req in requirements:
            if not all(req.get(k) == v for k, v in filters.items()):
                continue

            if has_flags:
                required_flags = set(f.strip() for f in has_flags.split(","))
                req_flags = set(req.get("flags", []))
                if not req_flags & required_flags:
                    continue

            if is_blank_label is not None:
                if (req.get("label", "") == "") != is_blank_label:
                    continue
            if is_blank_file is not None:
                if (req.get("file", "") == "") != is_blank_file:
                    continue

            results.append(req)

        logger.info(f"query() with filters → {len(results)} results")
        return results

    def get_by_id(self, req_id: str) -> Optional[dict]:
        """Get a single requirement by ID."""
        data = self._load()
        requirements = data.get("requirement", [])
        for req in requirements:
            if req.get("id") == req_id:
                return req
        return None

    def update_requirement(self, req_id: str, field: str, value) -> dict:
        """Update a single field on one requirement."""
        if field not in self.VALID_FIELD_UPDATES:
            raise ValueError(
                f"Invalid field '{field}'. Valid: {self.VALID_FIELD_UPDATES}"
            )

        if field == "shape" and value not in self.VALID_SHAPES:
            raise ValueError(f"Invalid shape '{value}'. Valid: {self.VALID_SHAPES}")
        if field == "scope" and value not in self.VALID_SCOPES:
            raise ValueError(f"Invalid scope '{value}'. Valid: {self.VALID_SCOPES}")
        if field == "layer" and value not in self.VALID_LAYERS:
            raise ValueError(f"Invalid layer '{value}'. Valid: {self.VALID_LAYERS}")

        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])

        found = False
        updated_req = None
        for req in requirements:
            if req.get("id") == req_id:
                old_value = req.get(field)
                req[field] = value
                found = True
                updated_req = req
                logger.info(f"Updated {req_id}.{field}: {old_value!r} → {value!r}")
                break

        if not found:
            raise KeyError(f"Requirement {req_id} not found")

        self._save(data)
        return updated_req

    def bulk_update(self, field: str, value, **filters) -> dict:
        """Update a field on all requirements matching the given filters."""
        if field not in self.VALID_FIELD_UPDATES:
            raise ValueError(
                f"Invalid field '{field}'. Valid: {self.VALID_FIELD_UPDATES}"
            )

        matching = self.query(**filters)
        if not matching:
            return {"count": 0, "updated_ids": []}

        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])
        updated_ids = []

        for match in matching:
            match_id = match.get("id")
            for req in requirements:
                if req.get("id") == match_id:
                    req[field] = value
                    updated_ids.append(match_id)
                    break

        self._save(data)
        logger.info(f"bulk_update {field}={value!r} on {len(updated_ids)} requirements")
        return {"count": len(updated_ids), "updated_ids": updated_ids}

    def get_statistics(self) -> dict:
        """Get requirement counts by shape, scope, layer, flags."""
        data = self._load()
        requirements = data.get("requirement", [])

        if not requirements:
            return {
                "total_count": 0,
                "by_shape": {},
                "by_scope": {},
                "by_layer": {},
                "flags_present": {},
                "blank_label_count": 0,
                "blank_file_count": 0,
            }

        return {
            "total_count": len(requirements),
            "by_shape": dict(Counter(r.get("shape", "unknown") for r in requirements)),
            "by_scope": dict(Counter(r.get("scope", "unknown") for r in requirements)),
            "by_layer": dict(Counter(r.get("layer", "unknown") for r in requirements)),
            "flags_present": dict(
                Counter(flag for r in requirements for flag in r.get("flags", []))
            ),
            "blank_label_count": sum(
                1 for r in requirements if r.get("label", "") == ""
            ),
            "blank_file_count": sum(1 for r in requirements if r.get("file", "") == ""),
        }

    def delete_requirement(self, req_id: str) -> dict:
        """Delete a requirement by ID."""
        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])

        for i, req in enumerate(requirements):
            if req.get("id") == req_id:
                del requirements[i]
                self._save(data)
                logger.info(f"Deleted {req_id}, {len(requirements)} remaining")
                return {"deleted": req_id, "remaining": len(requirements)}

        raise KeyError(f"Requirement {req_id} not found")

    def renumber_requirements(self) -> dict:
        """Renumber all requirement IDs sequentially within each layer."""
        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])

        counters: dict[str, int] = {}
        id_map: dict[str, str] = {}

        for req in requirements:
            layer = req.get("layer", "UNK")
            counters[layer] = counters.get(layer, 0) + 1
            old_id = req.get("id", "")
            new_id = f"REQ-{layer}-{counters[layer]:03d}"
            if old_id != new_id:
                id_map[old_id] = new_id
            req["id"] = new_id

        for req in requirements:
            notes = req.get("notes", "")
            if notes:
                for old_id, new_id in id_map.items():
                    notes = notes.replace(old_id, new_id)
                req["notes"] = notes

        self._save(data)
        logger.info(f"Renumbered {len(requirements)} requirements, {len(id_map)} IDs changed")
        return {"total": len(requirements), "changed": len(id_map), "id_map": id_map}

    def insert_requirement(self, **fields) -> dict:
        """Insert a new requirement. Auto-assigns next sequential ID for the layer."""
        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])

        layer = fields.get("layer", "LLC")
        max_num = 0
        for req in requirements:
            if req.get("layer") == layer:
                rid = req.get("id", "")
                try:
                    num = int(rid.split("-")[-1])
                    max_num = max(max_num, num)
                except (ValueError, IndexError):
                    pass
        new_id = f"REQ-{layer}-{max_num + 1:03d}"

        new_req = tomlkit.table()
        new_req["id"] = new_id
        defaults = {
            "source_clause": "",
            "original_wording": "",
            "shape": "triggered",
            "scope": "frame",
            "layer": layer,
            "side": "",
            "format_applicability": "",
            "flags": [],
            "precondition": "",
            "event": "",
            "postcondition": "",
            "coverage_target": "",
            "label": "",
            "file": "",
            "notes": "",
        }
        for key, default in defaults.items():
            new_req[key] = fields.get(key, default)

        requirements.append(new_req)
        self._save(data)
        logger.info(f"Inserted {new_id}")
        return {"id": new_id, "total": len(requirements)}


# ── Singleton ─────────────────────────────────────────────────────────────────
def get_manager(toml_path: Optional[Path] = None):
    """Get or create a manager for the given TOML file."""
    if toml_path is None:
        for name in [
            "requirements.toml",
        ]:
            path = _REQUIREMENTS_DIR / name
            if path.exists():
                toml_path = path
                break
        if toml_path is None:
            raise FileNotFoundError(
                f"No requirements TOML found in {_REQUIREMENTS_DIR}"
            )

    return RequirementsManager(toml_path)


# ── MCP Tools ─────────────────────────────────────────────────────────────────


@mcp.tool()
def query_requirements(
    shape: Optional[str] = None,
    scope: Optional[str] = None,
    layer: Optional[str] = None,
    side: Optional[str] = None,
    has_flags: Optional[str] = None,
    is_blank_label: Optional[bool] = None,
    is_blank_file: Optional[bool] = None,
    toml_path: Optional[str] = None,
) -> str:
    """Query requirements with optional filters.

    Args:
        shape: triggered, invariant, liveness, or reachability
        scope: frame, node, or bus
        layer: LLC, MAC, PCS, or FCE
        side: transmitter, receiver, or both
        has_flags: Comma-separated flags (COMPOUND, AMBIGUOUS, EXTERNAL_DEP, SHOULD, DOC_ONLY)
        is_blank_label: if true, return only requirements with label=""
        is_blank_file: if true, return only requirements with file=""
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    results = manager.query(
        shape=shape,
        scope=scope,
        layer=layer,
        side=side,
        has_flags=has_flags,
        is_blank_label=is_blank_label,
        is_blank_file=is_blank_file,
    )

    lines = []
    for req in results:
        line = f"{req.get('id', 'UNKNOWN')}: [{req.get('layer', '?')}/{req.get('shape', '?')}]"
        if req.get("flags"):
            line += f" {req['flags']}"
        lines.append(line)
        lines.append(f"    {req.get('original_wording', '')[:80]}...")

    if not results:
        return "No requirements matched the query."
    return f"{len(results)} requirements found:\n\n" + "\n".join(lines)


@mcp.tool()
def get_requirement(req_id: str, toml_path: Optional[str] = None) -> str:
    """Get a single requirement by ID with all details.

    Args:
        req_id: Requirement ID (e.g. "REQ-LLC-001")
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    req = manager.get_by_id(req_id)

    if not req:
        return f"Requirement {req_id} not found."

    lines = [f"ID: {req.get('id')}"]
    lines.append(f"Source: {req.get('source_clause')}")
    lines.append(f"Shape: {req.get('shape')}")
    lines.append(f"Scope: {req.get('scope')}")
    lines.append(f"Layer: {req.get('layer')}")
    lines.append(f"Side: {req.get('side', 'N/A')}")
    lines.append(f"Format: {req.get('format_applicability')}")
    lines.append(f"Flags: {req.get('flags', [])}")
    lines.append(f"Label: {req.get('label', '[BLANK]')}")
    lines.append(f"File: {req.get('file', '[BLANK]')}")
    lines.append("")
    lines.append(f"Original wording:\n  {req.get('original_wording')}")
    lines.append("")
    if req.get("precondition"):
        lines.append(f"Precondition:\n  {req.get('precondition')}")
    if req.get("event"):
        lines.append(f"Event:\n  {req.get('event')}")
    if req.get("postcondition"):
        lines.append(f"Postcondition:\n  {req.get('postcondition')}")
    if req.get("coverage_target"):
        lines.append(f"Coverage target:\n  {req.get('coverage_target')}")
    lines.append("")
    lines.append(f"Notes:\n  {req.get('notes')}")

    return "\n".join(lines)


@mcp.tool()
def update_requirement(
    req_id: str,
    field: str,
    value: str,
    toml_path: Optional[str] = None,
) -> str:
    """Update a single field on one requirement.

    Args:
        req_id: Requirement ID (e.g. "REQ-LLC-001")
        field: Field to update (shape, scope, layer, label, file, notes, etc.)
        value: New value
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    manager.update_requirement(req_id, field, value)
    return f"Updated {req_id}.{field} = {value!r}"


@mcp.tool()
def bulk_update(
    field: str,
    value: str,
    shape: Optional[str] = None,
    scope: Optional[str] = None,
    layer: Optional[str] = None,
    has_flags: Optional[str] = None,
    is_blank_label: Optional[bool] = None,
    is_blank_file: Optional[bool] = None,
    toml_path: Optional[str] = None,
) -> str:
    """Bulk update a field on requirements matching filters.

    Args:
        field: Field to update
        value: New value
        shape: Filter by shape
        scope: Filter by scope
        layer: Filter by layer
        has_flags: Filter by flags (CSV)
        is_blank_label: Filter by blank label
        is_blank_file: Filter by blank file
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.bulk_update(
        field,
        value,
        shape=shape,
        scope=scope,
        layer=layer,
        has_flags=has_flags,
        is_blank_label=is_blank_label,
        is_blank_file=is_blank_file,
    )
    return (
        f"Updated {result['count']} requirements:\n{', '.join(result['updated_ids'])}"
    )


@mcp.tool()
def delete_requirement(
    req_id: str,
    toml_path: Optional[str] = None,
) -> str:
    """Delete a requirement by ID.

    Args:
        req_id: Requirement ID (e.g. "REQ-LLC-001")
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.delete_requirement(req_id)
    return f"Deleted {result['deleted']}. {result['remaining']} requirements remaining."


@mcp.tool()
def renumber_requirements(toml_path: Optional[str] = None) -> str:
    """Renumber all requirement IDs sequentially within each layer.

    Args:
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.renumber_requirements()
    lines = [f"Renumbered {result['total']} requirements ({result['changed']} IDs changed)."]
    if result["id_map"]:
        for old, new in list(result["id_map"].items())[:20]:
            lines.append(f"  {old} → {new}")
        if len(result["id_map"]) > 20:
            lines.append(f"  ... and {len(result['id_map']) - 20} more")
    return "\n".join(lines)


@mcp.tool()
def insert_requirement(
    layer: str,
    original_wording: str,
    shape: str = "triggered",
    scope: str = "frame",
    side: str = "",
    source_clause: str = "",
    format_applicability: str = "",
    precondition: str = "",
    event: str = "",
    postcondition: str = "",
    coverage_target: str = "",
    notes: str = "",
    toml_path: Optional[str] = None,
) -> str:
    """Insert a new requirement. Auto-assigns next sequential ID for the layer.

    Args:
        layer: LLC, MAC, PCS, or FCE
        original_wording: Requirement description text
        shape: triggered, invariant, liveness, or reachability
        scope: frame, node, or bus
        side: transmitter, receiver, or both
        source_clause: ISO 11898-1 section reference
        format_applicability: Comma-separated formats (e.g. "CB, CE, FB, FE")
        precondition: What must be true before the triggering event
        event: The condition or action being tested
        postcondition: The observable outcome to assert
        coverage_target: How to verify this requirement
        notes: Additional notes
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.insert_requirement(
        layer=layer,
        original_wording=original_wording,
        shape=shape,
        scope=scope,
        side=side,
        source_clause=source_clause,
        format_applicability=format_applicability,
        precondition=precondition,
        event=event,
        postcondition=postcondition,
        coverage_target=coverage_target,
        notes=notes,
    )
    return f"Inserted {result['id']}. Total: {result['total']} requirements."


@mcp.tool()
def get_statistics(toml_path: Optional[str] = None) -> str:
    """Get statistics on requirements by shape, scope, layer, and flags.

    Args:
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    stats = manager.get_statistics()

    lines = [
        f"Total requirements: {stats['total_count']}",
        f"By shape: {stats['by_shape']}",
        f"By scope: {stats['by_scope']}",
        f"By layer: {stats['by_layer']}",
        f"Flags present: {stats['flags_present']}",
        f"Blank label: {stats['blank_label_count']}",
        f"Blank file: {stats['blank_file_count']}",
    ]
    return "\n".join(lines)


# ── Entry Point ───────────────────────────────────────────────────────────────


def main() -> None:
    """Start the MCP server using stdio transport."""
    logger.info("Starting Requirements MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
