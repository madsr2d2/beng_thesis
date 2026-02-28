#!/usr/bin/env python3
"""
CAN Requirements Management MCP Server

Provides safe, atomic operations for querying and modifying requirements.toml.
Uses FastMCP (high-level MCP Python SDK) with stdio transport for Claude Code.

Usage:
    python -m mcp_tools.requirements_manager
"""

import logging
import re
import shutil
import sys
from collections import Counter
from pathlib import Path
from typing import Optional

import tomlkit
from mcp.server.fastmcp import FastMCP

# ── Logging ───────────────────────────────────────────────────────────────────
# Must write to stderr only — stdout carries MCP JSON-RPC messages.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
# Resolve relative to this file so the server works regardless of cwd.
_PROJECT_ROOT = Path(__file__).parent.parent
_DEFAULT_TOML = _PROJECT_ROOT / "requirements" / "requirements.toml"

# ── FastMCP Server ────────────────────────────────────────────────────────────
mcp = FastMCP("requirements-manager")


# ── Requirements Manager ──────────────────────────────────────────────────────


class RequirementsManager:
    """Safe, atomic manager for requirements.toml using tomlkit."""

    VALID_FIELDS = {
        "priority",
        "status",
        "verification",
        "target_module",
        "description",
        "iso_reference",
        "acceptance_criteria",
        "notes",
    }

    def __init__(self, toml_path: Path = _DEFAULT_TOML):
        self.toml_path = Path(toml_path)
        self.backup_path = self.toml_path.with_suffix(".toml.bak")

        if not self.toml_path.exists():
            raise FileNotFoundError(f"Requirements file not found: {self.toml_path}")

        logger.info(f"RequirementsManager ready: {self.toml_path}")

    def _load(self) -> dict:
        """Load TOML preserving comments and formatting (via tomlkit)."""
        with open(self.toml_path, "r") as f:
            return tomlkit.parse(f.read())

    def _save(self, data: dict) -> None:
        """Write TOML back preserving comments and formatting."""
        with open(self.toml_path, "w") as f:
            f.write(tomlkit.dumps(data))
        logger.info(f"Saved: {self.toml_path}")

    def _backup(self) -> None:
        shutil.copy(self.toml_path, self.backup_path)
        logger.info(f"Backup: {self.backup_path}")

    def _renumber(self) -> int:
        """Renumber all requirement IDs sequentially and update header."""
        lines = self.toml_path.read_text().splitlines(keepends=True)

        header_end = next(
            (i for i, l in enumerate(lines) if re.match(r"\[requirements\.\d{3}\]", l)),
            len(lines),
        )
        header = lines[:header_end]

        groups: list[list[str]] = []
        current: list[str] = []
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

        content = re.sub(
            r"Unique numeric ID \(\d+-\d+\)",
            f"Unique numeric ID (001-{len(groups):03d})",
            "".join(new_lines),
        )
        self.toml_path.write_text(content)
        return len(groups)

    def query(
        self,
        category: Optional[str] = None,
        side: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[str] = None,
        verification: Optional[str] = None,
    ) -> list[dict]:
        filters = {
            k: v
            for k, v in {
                "category": category,
                "side": side,
                "status": status,
                "priority": priority,
                "verification": verification,
            }.items()
            if v is not None
        }
        data = self._load()
        results = [
            {"id": req_id, **req}
            for req_id, req in data["requirements"].items()
            if all(req.get(k) == v for k, v in filters.items())
        ]
        logger.info(f"query({filters}) → {len(results)} results")
        return results

    def update_requirement(self, req_id: str, field: str, value: str) -> dict:
        req_id = req_id.zfill(3)
        if field not in self.VALID_FIELDS:
            raise ValueError(f"Invalid field '{field}'. Valid: {self.VALID_FIELDS}")
        self._backup()
        data = self._load()
        if req_id not in data["requirements"]:
            raise KeyError(f"Requirement {req_id} not found")
        old = data["requirements"][req_id].get(field)
        data["requirements"][req_id][field] = value
        self._save(data)
        logger.info(f"update {req_id}.{field}: {old!r} → {value!r}")
        return dict(data["requirements"][req_id])

    def bulk_update(self, field: str, value: str, **filters) -> dict:
        if field not in self.VALID_FIELDS:
            raise ValueError(f"Invalid field '{field}'. Valid: {self.VALID_FIELDS}")
        matching = self.query(**filters)
        if not matching:
            return {"count": 0, "updated_ids": []}
        self._backup()
        data = self._load()
        updated_ids = []
        for req in matching:
            data["requirements"][req["id"]][field] = value
            updated_ids.append(req["id"])
        self._save(data)
        logger.info(f"bulk_update {field}={value!r} on {len(updated_ids)} requirements")
        return {"count": len(updated_ids), "updated_ids": updated_ids}

    def delete_requirement(self, req_id: str) -> dict:
        req_id = req_id.zfill(3)
        self._backup()
        content = self.toml_path.read_text()
        pattern = (
            rf"\[requirements\.{re.escape(req_id)}\]\n"
            rf".*?(?=\[requirements\.(?!{re.escape(req_id)}[\].])|$)"
        )
        new_content = re.sub(pattern, "", content, flags=re.DOTALL)
        if new_content == content:
            raise KeyError(f"Requirement {req_id} not found")
        self.toml_path.write_text(new_content)
        count = self._renumber()
        logger.info(f"Deleted {req_id}, renumbered to 001-{count:03d}")
        return {"deleted_id": req_id, "new_total_count": count}

    def renumber(self) -> dict:
        count = self._renumber()
        logger.info(f"Renumbered {count} requirements")
        return {"total_count": count, "id_range": f"001-{count:03d}"}

    def get_statistics(self) -> dict:
        reqs = self._load()["requirements"]
        return {
            "total_count": len(reqs),
            "by_category": dict(Counter(r["category"] for r in reqs.values())),
            "by_side": dict(Counter(r["side"] for r in reqs.values())),
            "by_status": dict(Counter(r["status"] for r in reqs.values())),
            "by_priority": dict(Counter(r["priority"] for r in reqs.values())),
        }


# ── Singleton ─────────────────────────────────────────────────────────────────
manager = RequirementsManager()


# ── MCP Tools ─────────────────────────────────────────────────────────────────


@mcp.tool()
def query_requirements(
    category: Optional[str] = None,
    side: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    verification: Optional[str] = None,
) -> str:
    """Query requirements with optional filters.

    Args:
        category: FRM, ERR, TMG, or CRC
        side: TX or RX
        status: verified, implemented, unverified, or diagnostic
        priority: critical, high, medium, or low
        verification: simulation, coverage, waveform, or assertion
    """
    results = manager.query(category, side, status, priority, verification)
    lines = [
        f"{r['id']}: [{r['category']}/{r['side']}] {r['description']}" for r in results
    ]
    return f"{len(results)} requirements found:\n\n" + "\n".join(lines)


@mcp.tool()
def update_requirement(req_id: str, field: str, value: str) -> str:
    """Update a single field on one requirement.

    Args:
        req_id: Requirement ID (e.g. 012)
        field: priority, status, verification, target_module, description,
               iso_reference, acceptance_criteria, or notes
        value: New value for the field
    """
    result = manager.update_requirement(req_id, field, value)
    return f"Updated {req_id}.{field} = {value!r}\n\n{result}"


@mcp.tool()
def bulk_update(
    field: str,
    value: str,
    category: Optional[str] = None,
    side: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    verification: Optional[str] = None,
) -> str:
    """Update a field on all requirements matching the given filters.

    Args:
        field: Field to update
        value: New value
        category: Filter by category (FRM, ERR, TMG, CRC)
        side: Filter by side (TX, RX)
        status: Filter by status
        priority: Filter by priority
        verification: Filter by verification method
    """
    filters = {
        k: v
        for k, v in {
            "category": category,
            "side": side,
            "status": status,
            "priority": priority,
            "verification": verification,
        }.items()
        if v is not None
    }
    result = manager.bulk_update(field, value, **filters)
    return f"Updated {result['count']} requirements: {result['updated_ids']}"


@mcp.tool()
def delete_requirement(req_id: str) -> str:
    """Delete a requirement and auto-renumber all remaining IDs.

    Args:
        req_id: Requirement ID to delete (e.g. 011)
    """
    result = manager.delete_requirement(req_id)
    return (
        f"Deleted {result['deleted_id']}. "
        f"Remaining: {result['new_total_count']} requirements "
        f"(renumbered 001-{result['new_total_count']:03d})"
    )


@mcp.tool()
def renumber_requirements() -> str:
    """Renumber all requirement IDs sequentially, fixing any gaps."""
    result = manager.renumber()
    return f"Renumbered {result['total_count']} requirements: {result['id_range']}"


@mcp.tool()
def get_statistics() -> str:
    """Get requirement counts by category, side, status, and priority."""
    s = manager.get_statistics()
    return "\n".join(
        [
            f"Total:       {s['total_count']}",
            f"By category: {s['by_category']}",
            f"By side:     {s['by_side']}",
            f"By status:   {s['by_status']}",
            f"By priority: {s['by_priority']}",
        ]
    )


# ── Entry Point ───────────────────────────────────────────────────────────────


def main() -> None:
    """Start the MCP server using stdio transport."""
    logger.info("Starting Requirements Manager MCP server")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
