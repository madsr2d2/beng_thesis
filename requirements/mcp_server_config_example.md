# MCP Server Configuration for Claude Code

To use the Requirements Manager MCP server with Claude Code, add this to your Claude Code settings:

## Option 1: Direct Python Script (Recommended)

In `~/.claude/settings.json` or Claude Code config:

```json
{
  "mcpServers": {
    "requirements": {
      "command": "python",
      "args": ["/path/to/beng_thesis/requirements/requirements_mcp_server.py"]
    }
  }
}
```

## Option 2: Via stdio

```json
{
  "mcpServers": {
    "requirements": {
      "command": "python",
      "args": ["-m", "requirements_mcp_server"],
      "env": {
        "PYTHONPATH": "/path/to/beng_thesis/requirements"
      }
    }
  }
}
```

## Usage in Claude Code

Once configured, you can call the tools directly:

```
Use the query_requirements tool to find all unverified CRC requirements
Use bulk_update to set their status to implemented
Use delete_requirement to remove 011
```

The MCP server will handle all TOML operations safely with automatic:
- Backup creation before modifications
- Type validation
- Atomic writes
- Logging of all changes
