# Verification Plan Reference

File: `verification_plan/verification_plan.toml`. 118 requirements, IDs `REQ-NNN`.

## Fields

| Field | Values |
|---|---|
| `layer` | LLC / MAC / PCS / FCE / system |
| `side` | transmitter / receiver / both |
| `observability` | black_box / white_box |
| `verification_method` | simulation / code_inspection / coverage (or combo) |
| `priority` | P1 / P2 / P3 |
| `status` | not_started / in_progress / complete |

- `black_box`: verified at module ports only, no reference model needed.
- `white_box`: requires internal FSM state, error counters, or non-trivial reference computation.
- `system`: jointly owned by multiple layers or requires two nodes (ACK, error coordination).
- `label`/`file`: blank until linked to a TB assertion/procedure.

## MCP tools

Install: `pip install -r mcp_tools/requirements.txt`

Tools: `query_requirements`, `get_requirement`, `update_requirement`, `bulk_update`, `insert_requirement`, `get_statistics`, `delete_requirement`, `renumber_requirements`.
