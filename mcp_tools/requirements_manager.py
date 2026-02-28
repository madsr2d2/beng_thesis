#!/usr/bin/env python3
"""
CAN Requirements Management MCP Server

Provides safe, atomic operations for querying and modifying the requirements.toml file.
Implements the Model Context Protocol to communicate with Claude Code and other clients.

Usage:
    python requirements_mcp_server.py
"""

import logging
import sys
import re
from pathlib import Path
from typing import Any, Optional
import shutil

try:
    from mcp.server import Server
    from mcp.types import Tool, TextContent, CallToolResult
except ImportError:
    raise ImportError(
        "MCP SDK not installed. Install with: pip install mcp"
    )

try:
    import tomlkit
except ImportError:
    raise ImportError(
        "tomlkit not installed. Install with: pip install tomlkit"
    )

# Configure logging for MCP communication
logger = logging.getLogger(__name__)
handler = logging.StreamHandler(sys.stderr)
handler.setFormatter(
    logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Initialize MCP server
server = Server("requirements-manager")


class RequirementsManager:
    """Safe atomic manager for requirements.toml"""

    def __init__(self, toml_path: str = "requirements/requirements.toml"):
        self.toml_path = Path(toml_path)
        self.backup_path = self.toml_path.with_suffix(".toml.bak")

        if not self.toml_path.exists():
            raise FileNotFoundError(f"Requirements file not found: {self.toml_path}")

        logger.info(f"Initialized RequirementsManager with {self.toml_path}")

    def load(self) -> dict:
        """Load requirements from TOML (preserves formatting/comments)"""
        with open(self.toml_path, "r") as f:
            return tomlkit.parse(f.read())

    def backup(self):
        """Create backup before modification"""
        shutil.copy(self.toml_path, self.backup_path)
        logger.info(f"Backup created: {self.backup_path}")

    def query(
        self,
        category: Optional[str] = None,
        side: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[str] = None,
        verification: Optional[str] = None,
    ) -> list[dict]:
        """
        Query requirements with optional filters.

        Args:
            category: FRM, ERR, TMG, CRC
            side: TX, RX
            status: verified, implemented, unverified, diagnostic
            priority: critical, high, medium, low
            verification: simulation, coverage, waveform, assertion

        Returns:
            List of matching requirements with IDs
        """
        filters = {
            "category": category,
            "side": side,
            "status": status,
            "priority": priority,
            "verification": verification,
        }
        filters = {k: v for k, v in filters.items() if v is not None}

        data = self.load()
        results = []

        for req_id, req in data["requirements"].items():
            if all(req.get(k) == v for k, v in filters.items()):
                results.append({"id": req_id, **req})

        logger.info(f"Query returned {len(results)} requirements (filters: {filters})")
        return results

    def update_requirement(self, req_id: str, field: str, value: Any) -> dict:
        """
        Update a single requirement field.

        Valid fields: priority, status, verification, target_module,
                     description, iso_reference, acceptance_criteria, notes

        Args:
            req_id: Requirement ID (001-122, auto-zero-padded)
            field: Field name to update
            value: New value

        Returns:
            Updated requirement dict

        Raises:
            KeyError: If requirement not found
            ValueError: If field is invalid
        """
        req_id = req_id.zfill(3)

        valid_fields = {
            "priority",
            "status",
            "verification",
            "target_module",
            "description",
            "iso_reference",
            "acceptance_criteria",
            "notes",
        }

        if field not in valid_fields:
            raise ValueError(f"Invalid field: {field}. Valid: {valid_fields}")

        self.backup()
        data = self.load()

        if req_id not in data["requirements"]:
            raise KeyError(f"Requirement {req_id} not found")

        old_value = data["requirements"][req_id].get(field)
        data["requirements"][req_id][field] = value

        self._write_toml(data)
        logger.info(
            f"Updated {req_id}.{field}: {old_value!r} -> {value!r}"
        )

        return data["requirements"][req_id]

    def bulk_update(self, field: str, value: Any, **filters) -> dict:
        """
        Update multiple requirements matching filters.

        Args:
            field: Field to update
            value: New value
            **filters: Query filters (category, side, status, priority, verification)

        Returns:
            Dict with count and updated requirement IDs
        """
        matching = self.query(**filters)

        if not matching:
            logger.warning(f"No requirements match filters: {filters}")
            return {"count": 0, "updated_ids": []}

        self.backup()
        data = self.load()

        updated_ids = []
        for req in matching:
            req_id = req["id"]
            data["requirements"][req_id][field] = value
            updated_ids.append(req_id)

        self._write_toml(data)
        logger.info(f"Bulk updated {len(updated_ids)} requirements: {field} = {value!r}")

        return {"count": len(updated_ids), "updated_ids": updated_ids}

    def delete_requirement(self, req_id: str) -> dict:
        """
        Delete requirement and renumber remaining IDs sequentially.

        Args:
            req_id: Requirement to delete (auto-zero-padded)

        Returns:
            Dict with deleted_id and new_total_count
        """
        req_id = req_id.zfill(3)

        self.backup()

        with open(self.toml_path, "r") as f:
            content = f.read()

        # Remove the requirement block
        pattern = rf"\[requirements\.{re.escape(req_id)}\]\n.*?(?=\[requirements\.(?!{re.escape(req_id)}[\].])|$)"
        new_content = re.sub(pattern, "", content, flags=re.DOTALL)

        if new_content == content:
            raise KeyError(f"Requirement {req_id} not found")

        with open(self.toml_path, "w") as f:
            f.write(new_content)

        # Renumber remaining requirements
        count = self._renumber()

        logger.info(f"Deleted {req_id}, renumbered to 001-{count:03d}")

        return {"deleted_id": req_id, "new_total_count": count}

    def renumber(self) -> dict:
        """
        Renumber all requirements sequentially, fixing any ID gaps.

        Returns:
            Dict with total_count and id_range
        """
        count = self._renumber()
        logger.info(f"Renumbered {count} requirements")
        return {"total_count": count, "id_range": f"001-{count:03d}"}

    def _renumber(self) -> int:
        """Internal: Renumber requirements and update header comment"""
        with open(self.toml_path, "r") as f:
            lines = f.readlines()

        # Find header end
        header_end = 0
        for i, line in enumerate(lines):
            if re.match(r"\[requirements\.\d{3}\]", line):
                header_end = i
                break

        header = lines[:header_end]

        # Split body into groups by top-level [requirements.NNN]
        groups = []
        current = []
        for line in lines[header_end:]:
            if re.match(r"\[requirements\.\d{3}\]\s*$", line) and current:
                groups.append(current)
                current = [line]
            else:
                current.append(line)
        if current:
            groups.append(current)

        # Renumber sequentially
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

        with open(self.toml_path, "w") as f:
            f.writelines(new_lines)

        # Update header comment with new ID range
        with open(self.toml_path, "r") as f:
            content = f.read()

        content = re.sub(
            r"Unique numeric ID \(\d+-\d+\)",
            f"Unique numeric ID (001-{len(groups):03d})",
            content,
        )

        with open(self.toml_path, "w") as f:
            f.write(content)

        return len(groups)

    def _write_toml(self, data: dict):
        """Write data back to TOML preserving formatting, comments, and structure"""
        with open(self.toml_path, "w") as f:
            f.write(tomlkit.dumps(data))

        logger.info(f"Wrote updates to {self.toml_path}")

    def get_statistics(self) -> dict:
        """Get statistics about requirements"""
        data = self.load()
        reqs = data["requirements"]

        from collections import Counter

        return {
            "total_count": len(reqs),
            "by_category": dict(Counter(r["category"] for r in reqs.values())),
            "by_side": dict(Counter(r["side"] for r in reqs.values())),
            "by_status": dict(Counter(r["status"] for r in reqs.values())),
            "by_priority": dict(Counter(r["priority"] for r in reqs.values())),
        }


# Initialize manager
manager = RequirementsManager()


# ============================================================================
# MCP Tool Definitions
# ============================================================================


@server.list_tools()
async def list_tools():
    """List available tools"""
    return [
        Tool(
            name="query_requirements",
            description="Query requirements with optional filters (category, side, status, priority, verification)",
            inputSchema={
                "type": "object",
                "properties": {
                    "category": {
                        "type": "string",
                        "description": "FRM, ERR, TMG, or CRC",
                    },
                    "side": {"type": "string", "description": "TX or RX"},
                    "status": {
                        "type": "string",
                        "description": "verified, implemented, unverified, or diagnostic",
                    },
                    "priority": {
                        "type": "string",
                        "description": "critical, high, medium, or low",
                    },
                    "verification": {
                        "type": "string",
                        "description": "simulation, coverage, waveform, or assertion",
                    },
                },
            },
        ),
        Tool(
            name="update_requirement",
            description="Update a single requirement field",
            inputSchema={
                "type": "object",
                "properties": {
                    "req_id": {
                        "type": "string",
                        "description": "Requirement ID (001-122)",
                    },
                    "field": {
                        "type": "string",
                        "description": "Field to update (priority, status, verification, target_module, description, iso_reference, acceptance_criteria, notes)",
                    },
                    "value": {"type": "string", "description": "New value"},
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
                    "field": {
                        "type": "string",
                        "description": "Field to update",
                    },
                    "value": {"type": "string", "description": "New value"},
                    "category": {
                        "type": "string",
                        "description": "Filter by category",
                    },
                    "side": {"type": "string", "description": "Filter by side"},
                    "status": {
                        "type": "string",
                        "description": "Filter by status",
                    },
                    "priority": {
                        "type": "string",
                        "description": "Filter by priority",
                    },
                    "verification": {
                        "type": "string",
                        "description": "Filter by verification",
                    },
                },
                "required": ["field", "value"],
            },
        ),
        Tool(
            name="delete_requirement",
            description="Delete requirement and auto-renumber remaining IDs",
            inputSchema={
                "type": "object",
                "properties": {
                    "req_id": {
                        "type": "string",
                        "description": "Requirement ID to delete",
                    }
                },
                "required": ["req_id"],
            },
        ),
        Tool(
            name="renumber_requirements",
            description="Renumber all requirements sequentially (fix ID gaps)",
            inputSchema={"type": "object", "properties": {}},
        ),
        Tool(
            name="get_statistics",
            description="Get statistics about requirements (counts by category, side, status, priority)",
            inputSchema={"type": "object", "properties": {}},
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> CallToolResult:
    """Execute tool calls"""
    try:
        if name == "query_requirements":
            result = manager.query(**arguments)
            return CallToolResult(content=[TextContent(type="text", text=str(result))])

        elif name == "update_requirement":
            result = manager.update_requirement(
                arguments["req_id"], arguments["field"], arguments["value"]
            )
            return CallToolResult(
                content=[
                    TextContent(
                        type="text",
                        text=f"Updated requirement {arguments['req_id']}: {result}",
                    )
                ]
            )

        elif name == "bulk_update":
            filters = {k: v for k, v in arguments.items() if k not in ["field", "value"] and v}
            result = manager.bulk_update(arguments["field"], arguments["value"], **filters)
            return CallToolResult(
                content=[
                    TextContent(
                        type="text",
                        text=f"Updated {result['count']} requirements: {result['updated_ids']}",
                    )
                ]
            )

        elif name == "delete_requirement":
            result = manager.delete_requirement(arguments["req_id"])
            return CallToolResult(
                content=[
                    TextContent(
                        type="text",
                        text=f"Deleted {result['deleted_id']}, new total: {result['new_total_count']}",
                    )
                ]
            )

        elif name == "renumber_requirements":
            result = manager.renumber()
            return CallToolResult(
                content=[
                    TextContent(
                        type="text",
                        text=f"Renumbered {result['total_count']} requirements: {result['id_range']}",
                    )
                ]
            )

        elif name == "get_statistics":
            result = manager.get_statistics()
            return CallToolResult(
                content=[TextContent(type="text", text=str(result))]
            )

        else:
            return CallToolResult(
                content=[TextContent(type="text", text=f"Unknown tool: {name}")],
                isError=True,
            )

    except Exception as e:
        logger.error(f"Tool {name} failed: {e}", exc_info=True)
        return CallToolResult(
            content=[TextContent(type="text", text=f"Error: {e}")],
            isError=True,
        )


if __name__ == "__main__":
    import asyncio
    from mcp.server.stdio import stdio_server as create_stdio_server

    async def run_server():
        logger.info("Starting Requirements Manager MCP Server")
        # Server communicates with Claude Code via stdio
        async with create_stdio_server() as (read_stream, write_stream):
            logger.info("Server ready")
            await server.run(read_stream, write_stream, server.create_initialization_options())

    asyncio.run(run_server())
