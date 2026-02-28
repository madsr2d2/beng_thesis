#!/usr/bin/env python3
"""
CAN Requirements Management MCP Server

Provides safe, atomic operations for querying and modifying requirements.toml.
Communicates with Claude Code via the Model Context Protocol (stdio transport).

Usage:
    python -m mcp_tools.requirements_manager
"""

import asyncio
import logging
import re
import shutil
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Optional

import tomlkit
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

# ── Logging ──────────────────────────────────────────────────────────────────
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

# ── MCP Server ────────────────────────────────────────────────────────────────
server = Server("requirements-manager")


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

    # ── Internal helpers ──────────────────────────────────────────────────────

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

        # Find where requirements start
        header_end = next(
            (i for i, l in enumerate(lines) if re.match(r"\[requirements\.\d{3}\]", l)),
            len(lines),
        )
        header = lines[:header_end]

        # Group lines by top-level [requirements.NNN] blocks
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

        # Rewrite with sequential IDs
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

        content = "".join(new_lines)

        # Update ID range in header comment
        content = re.sub(
            r"Unique numeric ID \(\d+-\d+\)",
            f"Unique numeric ID (001-{len(groups):03d})",
            content,
        )

        self.toml_path.write_text(content)
        return len(groups)

    # ── Public API ────────────────────────────────────────────────────────────

    def query(
        self,
        category: Optional[str] = None,
        side: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[str] = None,
        verification: Optional[str] = None,
    ) -> list[dict]:
        """Return requirements matching all provided filters."""
        filters = {
            k: v for k, v in {
                "category": category,
                "side": side,
                "status": status,
                "priority": priority,
                "verification": verification,
            }.items() if v is not None
        }
        data = self._load()
        results = [
            {"id": req_id, **req}
            for req_id, req in data["requirements"].items()
            if all(req.get(k) == v for k, v in filters.items())
        ]
        logger.info(f"query({filters}) → {len(results)} results")
        return results

    def update_requirement(self, req_id: str, field: str, value: Any) -> dict:
        """Update a single field on one requirement."""
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

    def bulk_update(self, field: str, value: Any, **filters) -> dict:
        """Update a field on all requirements matching filters."""
        if field not in self.VALID_FIELDS:
            raise ValueError(f"Invalid field '{field}'. Valid: {self.VALID_FIELDS}")

        matching = self.query(**filters)
        if not matching:
            logger.warning(f"bulk_update: no matches for {filters}")
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
        """Delete a requirement and renumber remaining IDs."""
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
        """Renumber all IDs sequentially (fix gaps after manual edits)."""
        count = self._renumber()
        logger.info(f"Renumbered {count} requirements")
        return {"total_count": count, "id_range": f"001-{count:03d}"}

    def get_statistics(self) -> dict:
        """Return counts by category, side, status and priority."""
        reqs = self._load()["requirements"]
        return {
            "total_count": len(reqs),
            "by_category": dict(Counter(r["category"] for r in reqs.values())),
            "by_side":     dict(Counter(r["side"]     for r in reqs.values())),
            "by_status":   dict(Counter(r["status"]   for r in reqs.values())),
            "by_priority": dict(Counter(r["priority"] for r in reqs.values())),
        }


# ── Singleton manager (resolved against project root) ─────────────────────────
manager = RequirementsManager()


# ── MCP Tool Registration ─────────────────────────────────────────────────────

@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="query_requirements",
            description="Query requirements with optional filters",
            inputSchema={
                "type": "object",
                "properties": {
                    "category":     {"type": "string", "description": "FRM, ERR, TMG, or CRC"},
                    "side":         {"type": "string", "description": "TX or RX"},
                    "status":       {"type": "string", "description": "verified, implemented, unverified, or diagnostic"},
                    "priority":     {"type": "string", "description": "critical, high, medium, or low"},
                    "verification": {"type": "string", "description": "simulation, coverage, waveform, or assertion"},
                },
            },
        ),
        Tool(
            name="update_requirement",
            description="Update a single requirement field",
            inputSchema={
                "type": "object",
                "properties": {
                    "req_id": {"type": "string", "description": "Requirement ID (001-122)"},
                    "field":  {"type": "string", "description": "priority, status, verification, target_module, description, iso_reference, acceptance_criteria, or notes"},
                    "value":  {"type": "string", "description": "New value"},
                },
                "required": ["req_id", "field", "value"],
            },
        ),
        Tool(
            name="bulk_update",
            description="Update multiple requirements matching filters",
            inputSchema={
                "type": "object",
                "properties": {
                    "field":        {"type": "string", "description": "Field to update"},
                    "value":        {"type": "string", "description": "New value"},
                    "category":     {"type": "string", "description": "Filter by category"},
                    "side":         {"type": "string", "description": "Filter by side"},
                    "status":       {"type": "string", "description": "Filter by status"},
                    "priority":     {"type": "string", "description": "Filter by priority"},
                    "verification": {"type": "string", "description": "Filter by verification"},
                },
                "required": ["field", "value"],
            },
        ),
        Tool(
            name="delete_requirement",
            description="Delete a requirement and auto-renumber remaining IDs",
            inputSchema={
                "type": "object",
                "properties": {
                    "req_id": {"type": "string", "description": "Requirement ID to delete"},
                },
                "required": ["req_id"],
            },
        ),
        Tool(
            name="renumber_requirements",
            description="Renumber all requirement IDs sequentially (fix ID gaps)",
            inputSchema={"type": "object", "properties": {}},
        ),
        Tool(
            name="get_statistics",
            description="Get requirement counts by category, side, status, and priority",
            inputSchema={"type": "object", "properties": {}},
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    """Dispatch MCP tool calls to RequirementsManager."""
    try:
        if name == "query_requirements":
            results = manager.query(**arguments)
            text = "\n".join(
                f"{r['id']}: [{r['category']}/{r['side']}] {r['description']}"
                for r in results
            )
            return [TextContent(type="text", text=f"{len(results)} requirements found:\n\n{text}")]

        elif name == "update_requirement":
            result = manager.update_requirement(
                arguments["req_id"], arguments["field"], arguments["value"]
            )
            return [TextContent(type="text", text=f"Updated {arguments['req_id']}.{arguments['field']} = {arguments['value']!r}\n\n{result}")]

        elif name == "bulk_update":
            filters = {k: v for k, v in arguments.items() if k not in ("field", "value") and v}
            result = manager.bulk_update(arguments["field"], arguments["value"], **filters)
            return [TextContent(type="text", text=f"Updated {result['count']} requirements: {result['updated_ids']}")]

        elif name == "delete_requirement":
            result = manager.delete_requirement(arguments["req_id"])
            return [TextContent(type="text", text=f"Deleted {result['deleted_id']}. Remaining: {result['new_total_count']} requirements (renumbered 001-{result['new_total_count']:03d})")]

        elif name == "renumber_requirements":
            result = manager.renumber()
            return [TextContent(type="text", text=f"Renumbered {result['total_count']} requirements: {result['id_range']}")]

        elif name == "get_statistics":
            s = manager.get_statistics()
            lines = [
                f"Total: {s['total_count']}",
                f"By category: {s['by_category']}",
                f"By side:     {s['by_side']}",
                f"By status:   {s['by_status']}",
                f"By priority: {s['by_priority']}",
            ]
            return [TextContent(type="text", text="\n".join(lines))]

        else:
            raise ValueError(f"Unknown tool: {name}")

    except Exception as e:
        logger.error(f"Tool '{name}' failed: {e}", exc_info=True)
        raise


# ── Entry Point ───────────────────────────────────────────────────────────────

async def main() -> None:
    """Start the MCP server using stdio transport."""
    logger.info("Starting Requirements Manager MCP server")
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
