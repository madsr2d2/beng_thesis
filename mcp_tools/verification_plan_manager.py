#!/usr/bin/env python3
"""
CAN Verification Plan MCP Server

Manages the CAN verification plan in TOML format.
Handles querying, updating, inserting, deleting, and validating requirements.

Format structure:
  [[requirement]]
  id = "REQ-MAC-001"
  source_clause = "§6.6.8"
  original_wording = "..."
  side = "transmitter" | "receiver" | "both"
  layer = "LLC" | "MAC" | "PCS" | "FCE"
  format_applicability = "CB, CE, FB, FE"
  observability = "black_box" | "white_box"
  notes = ""
  label = ""  # PSL assertion label or testbench procedure name
  file = ""   # Target VHDL source file

Usage:
    python -m mcp_tools.verification_plan_manager
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
_VPLAN_DIR = _PROJECT_ROOT / "verification_plan"

# ── FastMCP Server ────────────────────────────────────────────────────────────
mcp = FastMCP("verification_plan")

# ── Requirements Manager ─────────────────────────────────────────────────────

class RequirementsManager:
    """Manager for ISO-aligned CAN requirements using tomlkit."""

    VALID_LAYERS = {"LLC", "MAC", "PCS", "FCE", "system"}
    VALID_OBSERVABILITIES = {"black_box", "white_box"}
    VALID_FIELD_UPDATES = {
        "layer",
        "side",
        "notes",
        "label",
        "file",
        "original_wording",
        "paraphrase",
        "group_title",
        "source_clause",
        "format_applicability",
        "observability",
        "verification_method",
        "priority",
        "status",
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
        layer: Optional[str] = None,
        side: Optional[str] = None,
        observability: Optional[str] = None,
        is_blank_label: Optional[bool] = None,
        is_blank_file: Optional[bool] = None,
    ) -> list[dict]:
        """Query requirements by layer, side, and observability."""
        data = self._load()
        requirements = data.get("requirement", [])

        filters = {}
        if layer:
            filters["layer"] = layer
        if side:
            filters["side"] = side
        if observability:
            filters["observability"] = observability

        results = []
        for req in requirements:
            if not all(req.get(k) == v for k, v in filters.items()):
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

        if field == "layer" and value not in self.VALID_LAYERS:
            raise ValueError(f"Invalid layer '{value}'. Valid: {self.VALID_LAYERS}")
        if field == "observability" and value not in self.VALID_OBSERVABILITIES:
            raise ValueError(
                f"Invalid observability '{value}'. Valid: {self.VALID_OBSERVABILITIES}"
            )

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

    def bulk_update(self, field: str, value, **filters) -> dict:  # type: ignore[return]
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
        """Get requirement counts by layer, observability, and side."""
        data = self._load()
        requirements = data.get("requirement", [])

        if not requirements:
            return {
                "total_count": 0,
                "by_layer": {},
                "by_observability": {},
                "by_side": {},
                
                "blank_label_count": 0,
                "blank_file_count": 0,
            }

        return {
            "total_count": len(requirements),
            "by_layer": dict(Counter(r.get("layer", "unknown") for r in requirements)),
            "by_observability": dict(
                Counter(r.get("observability", "") or "unset" for r in requirements)
            ),
            "by_side": dict(Counter(r.get("side", "unknown") for r in requirements)),
            
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
        """Renumber all requirement IDs sequentially as REQ-NNN."""
        self._backup()
        data = self._load()
        requirements = data.get("requirement", [])

        id_map: dict[str, str] = {}

        for i, req in enumerate(requirements, start=1):
            old_id = req.get("id", "")
            new_id = f"REQ-{i:03d}"
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
            rid = req.get("id", "")
            try:
                num = int(rid.split("-")[-1])
                max_num = max(max_num, num)
            except (ValueError, IndexError):
                pass
        new_id = f"REQ-{max_num + 1:03d}"

        new_req = tomlkit.table()
        new_req["id"] = new_id
        defaults = {
            "source_clause": "",
            "original_wording": "",
            "paraphrase": "",
            "group_title": "",
            "layer": layer,
            "side": "",
            "format_applicability": "",
            "observability": "",
            "verification_method": "",
            "priority": "",
            "status": "not_started",
            "notes": "",
            "label": "",
            "file": "",
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
            "verification_plan.toml",
        ]:
            path = _VPLAN_DIR / name
            if path.exists():
                toml_path = path
                break
        if toml_path is None:
            raise FileNotFoundError(
                f"No verification plan TOML found in {_VPLAN_DIR}"
            )

    return RequirementsManager(toml_path)

# ── MCP Tools ─────────────────────────────────────────────────────────────────

@mcp.tool()
def query_requirements(
    layer: Optional[str] = None,
    side: Optional[str] = None,
    observability: Optional[str] = None,
    is_blank_label: Optional[bool] = None,
    is_blank_file: Optional[bool] = None,
    toml_path: Optional[str] = None,
) -> str:
    """Query requirements with optional filters.

    Args:
        layer: LLC, MAC, PCS, FCE, or system
        side: transmitter, receiver, or both
        observability: black_box or white_box
        is_blank_label: if true, return only requirements with label=""
        is_blank_file: if true, return only requirements with file=""
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    results = manager.query(
        layer=layer,
        side=side,
        observability=observability,
        is_blank_label=is_blank_label,
        is_blank_file=is_blank_file,
    )

    lines = []
    for req in results:
        line = f"{req.get('id', 'UNKNOWN')}: [{req.get('layer', '?')}]"
        if req.get("observability"):
            line += f" obs={req['observability']}"
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
    lines.append(f"Layer: {req.get('layer')}")
    lines.append(f"Side: {req.get('side', 'N/A')}")
    lines.append(f"Format: {req.get('format_applicability')}")
    lines.append(f"Observability: {req.get('observability', '[UNSET]')}")
    lines.append(f"Priority: {req.get('priority', '[UNSET]')}")
    lines.append(f"Status: {req.get('status', '[UNSET]')}")
    lines.append(f"Verification method: {req.get('verification_method', '[UNSET]')}")
    lines.append(f"Label: {req.get('label', '[BLANK]')}")
    lines.append(f"File: {req.get('file', '[BLANK]')}")
    lines.append("")
    lines.append(f"Original wording:\n  {req.get('original_wording')}")
    lines.append("")
    lines.append(f"Paraphrase:\n  {req.get('paraphrase', '')}")
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
    layer: Optional[str] = None,
    observability: Optional[str] = None,
    is_blank_label: Optional[bool] = None,
    is_blank_file: Optional[bool] = None,
    toml_path: Optional[str] = None,
) -> str:
    """Bulk update a field on requirements matching filters.

    Args:
        field: Field to update
        value: New value
        layer: Filter by layer (LLC, MAC, PCS, FCE, system)
        observability: Filter by observability (black_box, white_box)
        is_blank_label: Filter by blank label
        is_blank_file: Filter by blank file
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.bulk_update(
        field,
        value,
        layer=layer,
        observability=observability,
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
    side: str = "",
    source_clause: str = "",
    format_applicability: str = "",
    observability: str = "",
    notes: str = "",
    toml_path: Optional[str] = None,
) -> str:
    """Insert a new requirement. Auto-assigns next sequential ID for the layer.

    Args:
        layer: LLC, MAC, PCS, FCE, or system
        original_wording: Verbatim ISO requirement text
        side: transmitter, receiver, or both
        source_clause: ISO 11898-1 section reference (e.g. "§6.6.8")
        format_applicability: Comma-separated formats (e.g. "CB, CE, FB, FE")
        observability: black_box or white_box
        notes: How this is verified and any relevant caveats
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    result = manager.insert_requirement(
        layer=layer,
        original_wording=original_wording,
        side=side,
        source_clause=source_clause,
        format_applicability=format_applicability,
        observability=observability,
        notes=notes,
    )
    return f"Inserted {result['id']}. Total: {result['total']} requirements."

@mcp.tool()
def get_statistics(toml_path: Optional[str] = None) -> str:
    """Get statistics on requirements by layer, observability, and side.

    Args:
        toml_path: Path to requirements file (auto-detected if not provided)
    """
    manager = get_manager(Path(toml_path) if toml_path else None)
    stats = manager.get_statistics()

    lines = [
        f"Total requirements: {stats['total_count']}",
        f"By layer: {stats['by_layer']}",
        f"By observability: {stats['by_observability']}",
        f"By side: {stats['by_side']}",
        f"Blank label: {stats['blank_label_count']}",
        f"Blank file: {stats['blank_file_count']}",
        f"",
    ]
    return "\n".join(lines)

# ── Entry Point ───────────────────────────────────────────────────────────────

def main() -> None:
    """Start the MCP server using stdio transport."""
    logger.info("Starting Verification Plan MCP server")
    mcp.run(transport="stdio")

if __name__ == "__main__":
    main()
