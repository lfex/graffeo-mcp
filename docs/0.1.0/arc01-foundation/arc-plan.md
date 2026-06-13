# Arc 01: Foundation

**Delivers:** A running OTP application that populates a Mnesia-backed Erlang
knowledge graph on startup and serves `status` and `info` tools over stdio.

**Blog post:** Post 1 — "Clear Thinking / Careful Planning." This arc IS the
planning narrative — OTP architecture decisions, supervision tree design, tool
catalog rationale, the two-layer graph model, why Mnesia.

---

## Slices

### Slice 01: OTP Skeleton + Mnesia Graph + Ingest Pipeline

**Delivers:** `rebar3 compile` succeeds. The application starts, opens a
Mnesia graph via `graffeo_mnesia:open/2`, parses concept cards from
`priv/concept-cards/`, runs the five-phase ingest pipeline, and stores the
populated graph handle in `persistent_term`.

**Modules created:**

| Module | Role |
|--------|------|
| `graffeo-mcp-app` | OTP application callback |
| `graffeo-mcp-sup` | Supervisor (`one_for_one`) |
| `graffeo-mcp-graph` | gen_server: Mnesia lifecycle, ingest orchestration |
| `graffeo-mcp-parser` | Concept card YAML/frontmatter parser (port from prototype) |
| `graffeo-mcp-ingest` | Five-phase graph construction pipeline (port from prototype) |

**Also:** `rebar.config`, `graffeomcp.app.src`, `Makefile` with `fetch-cards`
target, `.github/workflows/ci.yml` skeleton.

**Key decisions exercised:**
- `graffeo_mnesia:open(<<"erlang_concepts">>, #{storage => disc_copies})`
- Ingest wraps all mutations in `graffeo_mnesia:transaction/1`
- Graph handle stored via `persistent_term:put({graffeo_mcp, graph}, Graph)`
- Parser is a direct port from `graffeo/examples/erlang-concepts/`

**Acceptance (high-level):**
- Application starts without error on OTP 25+
- Mnesia graph contains ~3,061 vertices and ~14,341 edges after ingest
- `persistent_term:get({graffeo_mcp, graph})` returns a live graph handle
- `graffeo:no_vertices/1` and `graffeo:no_edges/1` return expected counts

**Source code:** Existing LFE prototype in `graffeo/examples/erlang-concepts/`
provides parser and ingest logic. This slice ports and adapts, not greenfield.

---

### Slice 02: Meta Tools + Handler + stdio Transport

**Delivers:** The application registers an `erlmcp_server_handler` with
`status` and `info` tools. A stdio session connects. Claude Desktop can call
`status` and get a response. Smoke test: the full stack works end to end.

**Modules created:**

| Module | Role |
|--------|------|
| `graffeo-mcp-tools` | `erlmcp_server_handler` behaviour implementation (skeleton) |
| `graffeo-mcp-format` | Response formatting: graffeo results → MCP text content |

**Key work:**
- Implement `tools/0` returning tool specs for `status` and `info`
- Implement `handle_tool/3` dispatching to status/info handlers
- Wire `erlmcp:start_server/2` + `erlmcp:register_handler/2` in app startup
- Configure stdio transport via `erlmcp:start_stdio_setup/2`
- Full discoverability metadata on both tools (category, when_to_use, next,
  entry_point, annotations)
- Server identity: name, version, purpose, source

**Acceptance (high-level):**
- `status` tool returns graph health + basic stats
- `info` tool returns vertex/edge counts, category distribution, relationship
  type breakdown
- Claude Desktop connects via stdio and successfully calls both tools
- Tool specs carry full discoverability vocabulary
- `erlmcp_instructions:generate/2` produces a coherent instructions string

**Depends on:** Slice 01 (needs a populated graph to report on).

---

## Arc-level acceptance

The arc is done when:
1. `rebar3 compile` is clean (zero warnings)
2. `rebar3 eunit` passes (parser, ingest, handler unit tests)
3. The application starts, ingests 1,664 cards, and serves tools over stdio
4. Claude Desktop can connect and get meaningful responses from `status`/`info`
5. No erlmcp bugs encountered (or: bugs filed and worked around)
