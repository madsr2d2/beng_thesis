#!/usr/bin/env python3
"""
Entry point for running mcp_tools.requirements_manager as a module.

This allows: python -m mcp_tools.requirements_manager
"""

from mcp_tools.requirements_manager import main
import asyncio

if __name__ == "__main__":
    asyncio.run(main())
