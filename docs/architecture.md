# graffeo-mcp: Architecture & Design

**Project:** `lfex/graffeo-mcp`
**Status:** Planning
**Date:** 2026-06-05

---

## 0. Naming

- **OTP application:** `graffeomcp` (in `.app.src`)
- **User-facing modules:** `graffeo-mcp-*` (app, sup, graph, tools)
- **Internal/support modules:** `gmcp-*` (parser, ingest, format)
- **Repo:** `lfex/graffeo-mcp`

---

## 1. What this is

graffeo-mcp is an LFE/OTP application that wraps the `erlsci/graffeo` graph
library in an `erlmcp` 0.6.0 MCP server, using the Mnesia backend for
persistent, transactional graph storage. Its first dataset is 1,664 Erlang
concept cards (from `billosys/ai-engineering`) forming a two-layer knowledge
graph with ~3,061 vertices and ~14,341 edges.

Three simultaneous purposes:

1. **First consumer and integration test for erlmcp 0.6.0.** Bugs found here
   feed directly back into the release. erlmcp does not ship until graffeo-mcp
   demonstrates it working beautifully.
2. **A 3-part LFE blog post series** teaching graph-backed MCP server design
   with a focus on discoverability.
3. **A non-trivial demonstration** of graffeo's multi-backend architecture,
   showing the Mnesia backend doing real work under an MCP tool surface.

### Prior art

The Rust `fabryk-graph` and `fabryk-mcp-graph` crates (in `oxur/textrynum`)
implement the same pattern over `petgraph`. We port the architecture and tool
design, not the code. Key lessons carried forward:

- 17 MCP tools covering navigation, learning paths, analysis, and provenance
- Domain-agnostic graph core with pluggable extractors
- Post-result filtering via trait (Erlang: fun/2 predicate)
- Slot-based naming for tool customisation

The existing LFE code in `graffeo/examples/erlang-concepts/` (parser, ingest,
queries, runner) is the prototype. graffeo-mcp lifts this into a proper OTP
application with erlmcp integration.

---

## 2. Dependencies

| Dependency | Role | Version |
|-----------|------|---------|
| `erlmcp` | MCP server framework | 0.6.0 (pre-release) |
| `graffeo` | Graph library (algorithms + backends) | 0.3.x |
| `lfe` | Lisp Flavoured Erlang | 2.2+ |
| `rebar3_lfe` | LFE compiler plugin | latest |

Runtime: OTP 25+ (Mnesia is stdlib). No additional dependencies — `jsx` and
`jesse` come through `erlmcp`; `cowboy` comes through `erlmcp` for HTTP
transport.

---

## 3. OTP Application Architecture

### 3.1 Application startup

```
graffeo_mcp application
  depends_on: [kernel, stdlib, mnesia, graffeo, erlmcp]

  start/2 →
    1. graffeo_mcp_sup:start_link()       %% our supervisor
    2. start_erlmcp_server()              %% erlmcp:start_server/2
    3. erlmcp:register_handler(Server, graffeo_mcp_tools)
    4. start_transport(Config)            %% stdio or http
```

The erlmcp server and transport are supervised by erlmcp's own supervisor tree.
Our application supervises only the graph engine. This is the right boundary:
erlmcp manages MCP protocol lifecycle; we manage graph lifecycle.

### 3.2 Supervision tree

```
graffeo_mcp_sup (one_for_one)
└── graffeo_mcp_graph (gen_server)
    ├── Opens graffeo_mnesia graph on init
    ├── Runs ingest on first start (or on demand)
    ├── Stores graph handle in persistent_term
    └── Manages lifecycle: open / ingest / close / reingest
```

Why `one_for_one` and not `rest_for_one`: the erlmcp server is NOT a child of
our supervisor — it's under erlmcp_sup. If our graph engine crashes and
restarts, the erlmcp server stays up. The handler module re-reads the graph
handle from persistent_term on the next tool call, which picks up the
restarted engine's new handle transparently.

Why `persistent_term` for the graph handle: Mnesia tables are node-global. Once
the graffeo_mnesia graph is opened, any process can read it (dirty reads for
speed, transactions for consistency). The handler module doesn't need to call
through the gen_server for queries — it just needs the graph handle. Storing it
in persistent_term gives O(1) access from any process, which is exactly the
pattern for a read-heavy workload with rare writes.

### 3.3 Module responsibilities

| Module | Role |
|--------|------|
| `graffeo-mcp-app` | OTP application callback |
| `graffeo-mcp-sup` | Supervisor |
| `graffeo-mcp-graph` | gen_server: Mnesia graph lifecycle, ingest orchestration |
| `graffeo-mcp-tools` | `erlmcp_server_handler` behaviour: tool catalog + dispatch |
| `graffeo-mcp-parser` | Concept card YAML/frontmatter parser (from prototype) |
| `graffeo-mcp-ingest` | Five-phase graph construction pipeline (from prototype) |
| `graffeo-mcp-format` | Response formatting: graffeo results → MCP text/structured content |

### 3.4 The graph engine (graffeo-mcp-graph)

**init/1:**
1. `graffeo_mnesia:open(<<"erlang_concepts">>, #{storage => disc_copies})`
2. Check if graph is populated (`graffeo:no_vertices/1 > 0`)
3. If empty, run ingest (either inline or as supervised task)
4. Store graph handle via `persistent_term:put({graffeo_mcp, graph}, Graph)`

**handle_call:**
- `{reingest, CardDir}` — wipe and rebuild from a card directory
- `get_graph` — return the current graph handle (backup accessor)
- `{ingest_status}` — return `{ok, Count}` or `{ingesting, Progress}`

**handle_info:**
- `{'DOWN', ...}` — ingest task completion

**The ingest decision:** On first start with an empty Mnesia graph, ingest runs
synchronously (the server isn't useful without data). On reingest, it runs as a
supervised task under `erlmcp_task_sup` so the graph engine stays responsive.
During reingest, the old graph remains queryable until the new one is ready
(double-buffer pattern: build into a fresh Mnesia graph name, then swap the
persistent_term pointer).

---

## 4. MCP Tool Catalog

23 tools across 6 categories. Entry points marked with ★.

### 4.1 Category: navigation

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `get_node` | Get detailed info about a concept including degree counts | `id` (required) | ★ |
| `get_node_edges` | Get all edges connected to a concept, filtered by direction | `id`, `direction?` (incoming/outgoing/both) | |
| `related` | Find concepts related to a given concept | `id`, `relationship?`, `limit?` | |
| `neighborhood` | Explore the N-hop neighborhood around a concept | `id`, `radius?` (default 1), `relationship?` | |

### 4.2 Category: learning

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `prerequisites` | Get prerequisite concepts in learning order | `id` | |
| `dependents` | Find concepts that depend on this one (reverse prerequisites) | `id`, `depth?` (default 3) | |
| `learning_path` | Get a step-numbered learning path to reach a target concept | `id` | ★ |
| `topsort` | Get a full topological ordering of the knowledge graph (or a subgraph) | `root?` (if given, only the reachable subgraph) | |

### 4.3 Category: analysis

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `centrality` | Find the most central/important concepts by degree | `limit?` (default 10) | |
| `bridges` | Find gateway concepts that connect different areas of knowledge | `limit?` (default 10) | |
| `components` | Find connected clusters of concepts | | |
| `strong_components` | Find circular dependency groups (strongly connected components) | | |
| `condensation` | Collapse circular groups into a DAG view of the knowledge graph | | |
| `feedback_arc_set` | Find the minimum set of edges to break all cycles | | |

### 4.4 Category: paths

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `shortest_path` | Find the shortest weighted path between two concepts | `from`, `to`, `cost?` | ★ |
| `reachable` | Find all concepts reachable from a starting concept | `id` | |
| `dominators` | Find gateway concepts on all paths from a root to a target | `root`, `target?` | |

### 4.5 Category: sources

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `concept_sources` | Find books and papers that introduce or cover a concept | `id` | |
| `concept_variants` | Find source-specific variants of a canonical concept | `id` | |
| `source_coverage` | Find all concepts that a given source covers | `id` | |
| `bridge_categories` | Find concepts that span two knowledge areas | `category_a`, `category_b`, `limit?` | |

### 4.6 Category: meta

| Tool | Description | Key args | Entry? |
|------|------------|----------|--------|
| `status` | Report whether the knowledge graph is loaded with basic statistics | | ★ |
| `info` | Get detailed graph statistics: vertex/edge counts, category distribution, relationship types | | |

### 4.7 Discoverability metadata strategy

Every tool carries the full erlmcp discoverability vocabulary:

```erlang
#{name => <<"get_node">>,
  description => <<"Get detailed info about an Erlang concept...">>,
  input_schema => ...,
  %% Discoverability (§4 of m2-discoverability-design)
  category => <<"navigation">>,
  when_to_use => <<"When you want to understand a specific Erlang concept...">>,
  returns => <<"Concept name, category, tier, source, degree counts...">>,
  next => [<<"get_node_edges">>, <<"related">>, <<"prerequisites">>],
  entry_point => true,
  %% Behavioral hints (protocol-native annotations)
  annotations => #{readOnlyHint => true, idempotentHint => true}}
```

The `instructions` string (returned on initialize) will follow the
discoverability design's rule: **strategy and categories only, never enumerate
individual tools by name**. Something like:

> This server exposes an Erlang knowledge graph built from 1,664 concept cards.
> Tools are grouped into six categories: navigation (explore individual
> concepts), learning (prerequisite chains and study paths), analysis
> (structural insights like centrality and clustering), paths (shortest paths
> and reachability), sources (provenance — which books cover what), and meta
> (graph health and statistics). Start with `status` to orient, then explore
> with `get_node` or plan a study path with `learning_path`. Use `shortest_path`
> to find how two concepts connect.

**Entry points and `next` chains** form a directed graph of tool recommendations.
The expected primary flows:

```
status → info → get_node → get_node_edges → related → neighborhood
                    ↓
              prerequisites → learning_path
                    ↓
              concept_sources → source_coverage
                    ↓
              shortest_path → reachable → dominators
```

### 4.8 Annotations

All tools are read-only and idempotent (they query, never mutate). Every tool
carries `#{readOnlyHint => true, idempotentHint => true}`. No tool is
destructive. This is a strong signal to an LLM that it can call any tool
freely without side effects.

---

## 5. The Ingest Pipeline

Adapted from the prototype's five-phase pipeline, targeting Mnesia instead of
the map backend.

### 5.1 Card parsing (graffeo-mcp-parser)

Unchanged from the prototype. Reads a `.md` file, extracts YAML frontmatter,
returns a map:

```erlang
#{slug => <<"gen-server">>,
  concept => <<"gen_server Behaviour">>,
  category => <<"otp-behaviours">>,
  tier => <<"foundational">>,
  source => <<"OTP Design Principles">>,
  source_slug => <<"otp-design-principles">>,
  prerequisites => [<<"behaviour">>, <<"callback-module">>],
  extends => [<<"behaviour">>],
  related => [<<"gen-server-call">>, <<"gen-server-cast">>],
  contrasts_with => [<<"gen-statem">>, <<"gen-event">>]}
```

### 5.2 Two-layer graph model

The knowledge graph uses two vertex layers:

- **Source vertices:** `{SourceSlug, ConceptSlug}` tuples representing a
  concept as it appears in a specific source (e.g., `{<<"otp-design-principles">>,
  <<"gen-server">>}`). These carry the full card metadata as vertex labels.
- **Abstract vertices:** bare `ConceptSlug` binaries representing the canonical
  concept (e.g., `<<"gen-server">>`). These are the "real" concepts.

Four edge types:

- **membership:** source vertex → abstract vertex (this card contributes to
  this concept)
- **prerequisite/extends/related/contrasts_with:** abstract → abstract (typed
  concept relationships from card frontmatter)
- **source-internal:** source vertex → source vertex (relationships within a
  single source)

### 5.3 Five ingest phases

1. **Add source vertices.** One per card. Vertex = `{SourceSlug, ConceptSlug}`,
   label = full card metadata map.
2. **Add abstract vertices.** Unique concept slugs across all cards. Vertex =
   `ConceptSlug`, label = `#{concept => Name, category => Cat, tier => Tier}`.
3. **Add membership edges.** Source vertex → abstract vertex, edge meta =
   `#{type => membership}`.
4. **Add source-internal edges.** Within each source, connect source vertices
   according to card relationships.
5. **Add abstract edges.** Connect abstract vertices according to card
   relationships. Edge meta = `#{type => prerequisite}` (or extends, related,
   contrasts_with, with appropriate weights).

### 5.4 Mnesia adaptation

The prototype uses `graffeo:new/0` (map backend). For Mnesia:

```lfe
;; In graffeo-mcp-graph:init/1
(let ((`#(ok ,graph) (graffeo_mnesia:open #"erlang_concepts"
                       (map 'storage 'disc_copies))))
  ;; ... ingest into graph ...
  (persistent_term:put (tuple 'graffeo_mcp 'graph) graph)
  ...)
```

Key difference: Mnesia mutations (`add_vertex`, `add_edge`) are in-place, not
functional. The ingest pipeline folds over cards but doesn't thread an
accumulator — it mutates the Mnesia graph directly. For atomicity, wrap the
entire ingest in `graffeo_mnesia:transaction/1`.

### 5.5 Edge weights

For shortest-path queries to be meaningful, edges need weights:

| Relationship | Weight | Rationale |
|-------------|--------|-----------|
| prerequisite | 1.0 | Direct dependency — one learning step |
| extends | 1.0 | Same distance as prerequisite |
| related | 2.0 | Weaker connection — two steps apart conceptually |
| contrasts_with | 3.0 | Weakest typed connection |
| membership | 0.5 | Source↔abstract is a projection, not a conceptual step |

**Edge merge strategy.** The same abstract-to-abstract edge can be asserted by
multiple source cards (different books covering the same concept pair) or by
multiple relationship types from the same card. When `add-typed-edge` encounters
an existing edge, it merges rather than overwrites: `weight` takes
`erlang:min(new, old)` so the strongest relationship (lowest weight) dominates
path-finding; `types` is the `lists:usort` union of all asserted relationship
types; `asserted_by` is the `lists:usort` union of all asserting source slugs.
Rationale: in a learning-path graph, a prerequisite relationship should always
beat a weaker "related" assertion when computing shortest paths, while the full
type union and attribution list remain available for tool consumers that want
the complete semantic picture.

---

## 6. Implementation Phases

### Phase 1: Skeleton

- OTP application boilerplate (app, sup, graph gen_server)
- Mnesia graph lifecycle (open, close, reingest)
- Parser and ingest pipeline adapted for Mnesia
- `status` and `info` tools only (smoke test: does erlmcp serve tools?)
- stdio transport, test with Claude Desktop

**Blog post 1 content:** This phase IS the planning narrative.

### Phase 2: Core tools

- Navigation tools: get_node, get_node_edges, related, neighborhood
- Learning tools: prerequisites, dependents, learning_path, topsort
- Path tools: shortest_path, reachable
- Source tools: concept_sources, concept_variants, source_coverage
- Full discoverability metadata on every tool

**Blog post 2 content:** The discovery of what works and what doesn't in tool
descriptions, `when_to_use` text, `next` chains. This is where we run LLM
exercises against the tools and iteratively improve discoverability.

### Phase 3: Advanced tools + HTTP

- Analysis tools: centrality, bridges, components, strong_components,
  condensation, feedback_arc_set
- Path tools: dominators
- Source tools: bridge_categories
- HTTP streaming transport for Codex
- Full QA sessions

**Blog post 3 content:** Demonstration of the complete system. QA sessions with
Claude Desktop (stdio) and Codex (HTTP). Focus on the difference good
discoverability makes.

### Phase 4: Polish

- Response formatting refinement
- Error messages that help LLMs recover
- Instructions string tuning
- Performance profiling with the full corpus
- Any erlmcp bugs found → fed back to release

---

## 7. Blog Post ↔ Implementation Mapping

| Post | Focus | Implementation phase | Key content |
|------|-------|---------------------|-------------|
| 1: Planning | Clear thinking | Phase 1 | OTP architecture decisions, supervision tree design, tool catalog rationale, why Mnesia, the two-layer graph model |
| 2: Discoverability | Writing for LLMs | Phase 2 | Tool description iteration, `when_to_use` failures and fixes, `next` chain design, meta-cognitive analysis of what makes a tool findable |
| 3: Demonstration | Proof of benefits | Phase 3–4 | Real QA sessions, before/after discoverability comparison, the full tool surface in action |

---

## 8. API Verification (2026-06-05)

Verified against actual erlmcp source. All architecture assumptions confirmed,
plus one finding to feed back.

### Confirmed

- `erlmcp:start_server(ServerId, Config)` — Config accepts: `name`, `version`,
  `purpose`, `source`, `docs`, `instructions`, `capabilities`, `handler`,
  `handlers`. Returns `{ok, ServerPid}`.
- `erlmcp:register_handler(Server, Module)` — calls `Module:tools()`, tags each
  spec with `handler_module => Module`, stores in ETS, fires
  `notifications/tools/list_changed`.
- `erlmcp_server_handler` behaviour: exactly two callbacks:
  - `-callback tools() -> [map()].`
  - `-callback handle_tool(binary(), map(), erlmcp_ctx:ctx()) -> {ok, term()} | {error, integer(), binary()}.`
- Tool dispatch: per-request process isolation via `spawn_monitor`. Handler
  crashes don't take down the session.
- Schema builders: `object/1`, `field/2,3`, `string/0,1`, `integer/0,1`,
  `number/0,1`, `boolean/0`, `array/1,2`, `enum/1`, `any_of/1`. Field opts:
  `required`, `{doc, Bin}`, `{default, V}`, `{min, N}`, `{max, N}`,
  `{min_length, N}`, `{max_length, N}`, `{pattern, Bin}`.
- Content constructors: `text/1`, `image/2`, `audio/2`, `embedded_resource/1`,
  `resource_link/2`.
- Result format: `{ok, Content}` | `{ok, Content, Structured}` |
  `{error, Code, Message}`.
- `_meta` projection: `io.erlmcp/category`, `io.erlmcp/when_to_use`,
  `io.erlmcp/next`, `io.erlmcp/entry_point`, `io.erlmcp/protocol_features`.
- `erlmcp_instructions:generate/2`: auto-derives from tool metadata. Never
  enumerates individual tools. Includes: identity, categories, entry points,
  protocol features, directory reference.
- `start_stdio_setup/2`: convenience for server + session + stdio under one
  supervisor.

### Finding: `returns` and `summary` not projected into `_meta`

The discoverability design (§4) specifies five metadata keys: `summary`,
`when_to_use`, `returns`, `next`, `category`. The calculator example handler
uses `returns` in tool registration. But `disc_meta/1` in
`erlmcp_server_session.erl` only projects four keys:

```erlang
[{category, <<"io.erlmcp/category">>},
 {when_to_use, <<"io.erlmcp/when_to_use">>},
 {next, <<"io.erlmcp/next">>},
 {entry_point, <<"io.erlmcp/entry_point">>}]
```

`returns` and `summary` are stored in the tool spec but invisible to clients
via `tools/list`. The directory tool's `tool_directory_entry/1` also omits
`returns` (though it includes `when_to_use` and `next`).

**Impact:** Medium. An LLM reading `tools/list` gets `when_to_use` but not
`returns` — it can find the right tool but may not know what to expect back.
Feed this back to erlmcp as a DISC-1 gap.

### Resolved questions

- **Module naming:** `graffeo-mcp-*` (user-facing), `gmcp-*` (internal). ✓
- **Card location:** `priv/concept-cards/` via a `make fetch-cards` target that
  does a shallow clone of `billosys/ai-engineering` and copies the cards. ✓
- **Graph per session:** No. Single node-global Mnesia graph, read-only after
  ingest. ✓

### Resolved questions (round 2)

1. **Reingest as MCP tool?** No. Out of scope — not needed for the blog series
   or normal operation. Reingest is a dev-time operation via the shell.
2. **Filter by tier/category?** Yes, from Phase 2. Tools that return lists of
   concepts (related, neighborhood, prerequisites, dependents, centrality,
   bridges, etc.) accept optional `tier` and `category` args. Implemented as a
   post-query predicate over vertex labels — same pattern as fabryk-mcp-graph's
   `GraphNodeFilter`, but a simple fun/2 in LFE.
3. **Custom `instructions` string vs auto-generated?** Start with auto-generated
   (erlmcp_instructions:generate/2). If the auto-generated output is weak, switch
   to a hand-crafted string. This is itself a discoverability experiment for
   Post 2 — does the auto-generator produce good enough orientation, or do we
   need to hand-tune it?
