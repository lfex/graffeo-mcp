# Slice 02: Meta Tools + Handler + stdio Transport

## What this slice delivers

The application becomes a working MCP server. Two modules are created:
`graffeo-mcp-tools` (the `erlmcp_server_handler` implementation) and
`graffeo-mcp-format` (response formatting). The application startup wires
erlmcp's stdio transport so Claude Desktop can connect and call the `status`
and `info` tools. This is the end-to-end smoke test: does the full stack —
OTP app → Mnesia graph → erlmcp handler → stdio → Claude Desktop — work?

## Modules

| Module | Role |
|--------|------|
| `graffeo-mcp-tools` | `erlmcp_server_handler` behaviour: `tools/0` + `handle_tool/3` |
| `graffeo-mcp-format` | Response formatting: graph data → text binaries for MCP content |

## Modified modules

| Module | Change |
|--------|--------|
| `graffeo-mcp-app` | `start/2` wires erlmcp server + handler + stdio after supervisor is up |

## Key design decisions

### Handler pattern

`graffeo-mcp-tools` implements exactly two callbacks:

- `tools/0` — returns a list of tool spec maps. Each tool carries the full
  erlmcp discoverability vocabulary: `category`, `when_to_use`, `next`,
  `entry_point`, `annotations`. Both tools are `category => <<"meta">>`.
- `handle_tool/3` — pattern-matches on tool name binary, extracts graph
  from `persistent_term`, delegates to format functions, wraps in
  `erlmcp:text/1`.

### Graph access pattern

The handler reads the graph handle from `persistent_term:get({graffeo_mcp,
graph})` — no gen_server call on the hot path. This was established in Slice 01.
If the persistent_term is missing (graph not yet loaded), the handler MUST
return a clear error rather than crashing: `{error, -32603, <<"Graph not loaded.
The server is still starting.">>}`.

### Formatting separation

`graffeo-mcp-format` owns the text representation. The tools module calls format
functions and wraps results in `erlmcp:text/1`. This keeps the handler dispatch
clean and makes format changes independent of handler logic.

### erlmcp wiring

`graffeo-mcp-app:start/2` calls `erlmcp:start_stdio_setup/2` after the
supervisor is running. The config map includes `handler => 'graffeo-mcp-tools'`
plus server identity (`name`, `version`, `purpose`). The erlmcp supervisor tree
is separate from ours — we supervise the graph engine; erlmcp supervises the
MCP protocol stack.

### Tool design

**status** (entry point):
- No required input parameters
- Returns: loaded/not-loaded state, vertex count, edge count, backend type
- `next => [<<"info">>]`
- This is the orientation tool — an LLM's first call

**info** (reachable from status):
- No required input parameters
- Returns: detailed counts, category distribution (how many concepts per
  category), relationship type breakdown (how many edges per type)
- `next => [<<"get_node">>, <<"learning_path">>]` (points to Arc 2 tools)
- `entry_point => false`

## LFE conventions (same as Slice 01)

Per `lfe-manual/src/part7/ai-resources/style-guide.md`:
- 2-space indentation, 80-char line limit
- Kebab-case module names, alphabetical exports
- No `(export all)` — list every export explicitly with arities
- Docstrings on all public functions
- Pattern match in function heads, not case (where natural)
- `mref`/`mset` for map access, `#"..."` for binary strings

## Depends on

- Slice 01 (populated graph in persistent_term)
- erlmcp 0.6.0 API: `erlmcp_server_handler` behaviour, `erlmcp:text/1`,
  `erlmcp:start_stdio_setup/2`, `erlmcp_schema:object/1`, `erlmcp_schema:field/2,3`
