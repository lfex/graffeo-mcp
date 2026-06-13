# Arc 01, Slice 01: OTP Skeleton + Mnesia Graph + Ingest Pipeline

**Status:** Open
**Arc:** [01-foundation](../arc-plan.md)
**Project plan:** [plan.md](../../plan.md)
**Architecture:** [architecture.md](../../../architecture.md)

---

## What this slice delivers

A compilable LFE/OTP application that:
1. Starts as an OTP application with a supervision tree
2. Opens a Mnesia graph via `graffeo_mnesia:open/2`
3. Parses 1,664 concept cards from `priv/concept-cards/`
4. Runs the five-phase ingest pipeline to populate the graph
5. Stores the graph handle in `persistent_term` for O(1) access

At slice close, `rebar3 compile` succeeds, `rebar3 eunit` passes, and the
application can start and populate a graph. No MCP tools yet — that is
Slice 02.

## Modules created

| Module | File | Role |
|--------|------|------|
| `graffeo-mcp-app` | `src/graffeo-mcp-app.lfe` | OTP application callback |
| `graffeo-mcp-sup` | `src/graffeo-mcp-sup.lfe` | Supervisor (`one_for_one`) |
| `graffeo-mcp-graph` | `src/graffeo-mcp-graph.lfe` | gen_server: Mnesia lifecycle + ingest |
| `graffeo-mcp-parser` | `src/graffeo-mcp-parser.lfe` | YAML frontmatter parser |
| `graffeo-mcp-ingest` | `src/graffeo-mcp-ingest.lfe` | Five-phase graph builder |

## Build infrastructure

| File | Purpose |
|------|---------|
| `rebar.config` | Deps, plugins, profiles, compiler opts |
| `src/graffeomcp.app.src` | OTP application resource file |
| `Makefile` | `compile`, `test`, `fetch-cards`, `clean` targets |

## Key adaptations from prototype

The prototype code lives in `graffeo/examples/erlang-concepts/src/`. This
slice ports it with three changes:

1. **Map → Mnesia backend.** The prototype uses `graffeo:new/0` (map
   backend) and threads an accumulator. Mnesia mutations are in-place, so
   folds still iterate but don't thread an accumulator — they mutate the
   graph handle directly. Wrap the entire ingest in
   `graffeo_mnesia:transaction/1` for atomicity.

2. **Edge weights.** The prototype stores `#{label => #{types => [...],
   asserted_by => [...]}}` on edges. We add a `weight` key based on
   relationship type: prerequisite=1.0, extends=1.0, related=2.0,
   contrasts_with=3.0, membership=0.5. Weights are consumed by Dijkstra
   in Arc 2's `shortest_path` tool.

3. **gen_server lifecycle.** The prototype is a script. Here, ingest is
   managed by a gen_server that opens the graph on init, runs ingest if
   the graph is empty, and stores the handle in persistent_term.

## Source references

- Parser: `graffeo/examples/erlang-concepts/src/lfeerlcpt-parser.lfe`
- Ingest: `graffeo/examples/erlang-concepts/src/lfeerlcpt-ingest.lfe`
- Queries: `graffeo/examples/erlang-concepts/src/lfeerlcpt-queries.lfe`
- Runner: `graffeo/examples/erlang-concepts/src/lfeerlcpt.lfe`
- Mnesia API: `graffeo/src/graffeo_mnesia.erl` (open/2, transaction/1)

## LFE style notes

Per `lfe-manual/src/part7/ai-resources/style-guide.md`:
- 2-space indentation, 80-char line limit
- Kebab-case module names, alphabetical exports
- No `(export all)` — list every export explicitly with arities
- Docstrings on all public functions
- Pattern match in function heads, not case
- Don't repeat module name in function names
