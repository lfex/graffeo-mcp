# Slice 01: Navigation + Learning Tools

**Arc:** 02 (Core Tools + Discoverability)
**Depends on:** Arc 01 complete (commit 738d5f3)

## What this slice delivers

Eight core tools across two categories — navigation (4) and learning (4) —
plus a new query module that encapsulates graph algorithm logic.

**Navigation tools** let an LLM explore the knowledge graph:

- `get_node` (entry point) — look up a concept by slug: name, category, tier,
  degree counts, source count
- `get_node_edges` — list edges for a concept with direction filter
- `related` — find concepts connected by a specific relationship type
- `neighborhood` — BFS walk from a concept within N hops

**Learning tools** let an LLM understand prerequisite structure:

- `prerequisites` — direct and transitive prerequisites for a concept
- `dependents` — concepts that depend on a given concept (with optional depth)
- `learning_path` (entry point) — topologically sorted prerequisite chain
  (foundations first, target last)
- `topsort` — topological ordering of the prerequisite graph (with optional
  root scoping)

## Modules

### New

- **`graffeo-mcp-query`** — graph query logic: subgraph projection, traversal,
  prerequisite/dependent chain computation, BFS neighborhood, learning path
  ordering. Pure functions operating on the graffeo graph handle; no MCP
  coupling. Exports one public function per tool plus a `project-prerequisites/1`
  helper for subgraph projection.

### Modified

- **`graffeo-mcp-tools`** — adds 8 tool specs to `tools/0`, 8 clauses to
  `handle_tool/3` (before the catch-all)
- **`graffeo-mcp-format`** — adds format functions for each new tool's response

### Tests (new/extended)

- **`graffeo-mcp-query-tests`** (new) — tests query logic directly with a
  richer fixture than Arc 1: prerequisite chains, multiple relationship types,
  multiple categories/tiers
- **`graffeo-mcp-tools-tests`** (extended) — dispatch tests for 8 new tools
- **`graffeo-mcp-format-tests`** (extended) — format output tests

## Design decisions

### Edge direction convention

In the graffeo-mcp knowledge graph, `from → to` with type `prerequisites` means
"from-concept lists to-concept as a prerequisite" — the edge goes FROM the
dependent TO the foundational concept. This means:

- `out_neighbours(prereq_subgraph, X)` = X's direct prerequisites
- `in_neighbours(prereq_subgraph, X)` = X's direct dependents
- `reachable_neighbours(prereq_subgraph, [X])` = transitive prerequisites
- `reaching_neighbours(prereq_subgraph, [X])` = transitive dependents
- `topsort` gives dependent-first order; **reverse** for learning order

### Query module isolation

Arc 1's meta tools were simple enough to compute in the format module. Arc 2
involves real graph algorithms (BFS, subgraph projection, topsort, condensation,
prerequisite chain traversal). Separating query logic from formatting keeps both
modules focused and testable.

### Abstract-concept scope

All tools operate on abstract concepts (binary slugs), not source vertices
(tuple keys). Source vertices are internal plumbing; the `concept_sources` tool
(Slice 02) is the proper interface to the source layer.

### BFS filter vs. subgraph construction

`neighborhood` uses `graffeo:bfs/3` with a filter function (only follow edges
between abstract vertices) rather than constructing a subgraph. `bfs` is a
read-half traversal and runs directly on the Mnesia graph. **Note (Amendment
A2):** the filter is **arity-2** (`fun(From, To)`), not the originally-planned
meta-aware arity-3 filter — on Mnesia an arity-3 BFS filter silently skips
incoming edges, collapsing `direction => both` to out-only. Relationship-type
restriction (which needs edge metadata) is therefore applied by projecting a
type-filtered map graph first (`project-by-type/2`) and running the arity-2 BFS
on the projection.

Tools that need `reachable`/`reaching`/`topsort`/`condensation` operate on a
**map-backed projection** of the prerequisite subgraph. **Note (Amendment A1):**
the original plan used `graffeo:filter_edges/2` for this, but `filter_edges` —
like `subgraph` and `condensation` — is a *constructive* op that begins with
`Backend:empty_like/1`, which the Mnesia (and DETS) disk backend deliberately
refuses (`{unsupported_on_backend, empty_like, graffeo_mnesia}`). So
`project-prerequisites/1` instead builds a fresh map-backed graph
(`graffeo:new/0`) by iterating the Mnesia read-half
(`vertices` + `out_neighbours` + `edge_meta`) and copying the
`prerequisites`-typed abstract→abstract edges. Every downstream DAG op then runs
on the map projection, which fully supports the build-half. This is graffeo's
intended pattern: disk backend = durable store + universal reads; memory
backend = derived-graph algorithms.

### Cycle handling

The Erlang concept graph has prerequisite cycles. `learning_path` handles this
via condensation: condense the **map-backed** prerequisite projection, topsort
the DAG of SCCs, expand SCCs in sorted order. `topsort` uses the same approach.
(`condensation` is a constructive op — it only runs because the projection is a
map graph, not the Mnesia graph; see "BFS filter vs. subgraph construction".)

### Missing-graph guard

All new `handle_tool` clauses check persistent_term for the graph handle,
returning `-32603` if absent — same pattern as Arc 1.
