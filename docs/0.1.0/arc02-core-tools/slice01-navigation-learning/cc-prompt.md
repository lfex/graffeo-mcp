# CC Prompt — Slice 01: Navigation + Learning Tools

**Arc:** 02 (Core Tools + Discoverability)
**Depends on:** Arc 01 complete (commit 738d5f3)
**Iteration cap:** 5

## What to read first

1. **This prompt** (you're reading it)
2. **Slice doc:** `docs/0.1.0/arc02-core-tools/slice01-navigation-learning/slice-doc.md`
3. **Ledger:** `docs/0.1.0/arc02-core-tools/slice01-navigation-learning/ledger.md` (19 rows)
4. **Arc plan:** `docs/0.1.0/arc02-core-tools/arc-plan.md`
5. **Architecture doc:** `docs/architecture.md`
6. **LFE style guide:** `lfe-manual/src/part7/ai-resources/style-guide.md`
7. **LFE language guide:** `lfe/doc/src/lfe_guide.7.md`
8. **Existing source:** all files in `src/` and `test/` (Arc 1 baseline)
9. **Prototype queries:** `graffeo/examples/erlang-concepts/src/lfeerlcpt-queries.lfe`

You MUST load the erlang-guidelines skill before writing any code.

---

## CRITICAL: Edge direction convention

In the graffeo-mcp knowledge graph, an edge `from → to` with type
`prerequisites` means **"from-concept lists to-concept as a prerequisite"** —
the edge goes FROM the dependent TO the foundational concept.

Example: if `gen-server` has `prerequisites: [process, message-passing]`, the
ingest module creates edges `gen-server → process` and
`gen-server → message-passing`.

This means:

| Operation | Returns |
|-----------|---------|
| `out_neighbours(prereq_subgraph, X)` | X's direct **prerequisites** |
| `in_neighbours(prereq_subgraph, X)` | X's direct **dependents** |
| `reachable_neighbours(prereq_subgraph, [X])` | **transitive prerequisites** |
| `reaching_neighbours(prereq_subgraph, [X])` | **transitive dependents** |
| `topsort` | dependent-first order |
| `lists:reverse(topsort result)` | **learning order** (foundations first) |

Get this wrong and every learning/prerequisite tool returns inverted results.
Verify against the test fixture before proceeding.

---

## erlmcp API reference (verified against source)

You MUST use these exact API patterns. Do not guess at erlmcp APIs.

### Behaviour

```erlang
%% erlmcp_server_handler
-callback tools() -> [map()].
-callback handle_tool(binary(), map(), erlmcp_ctx:ctx()) ->
    {ok, term()} | {ok, term(), map()} | {error, integer(), binary()}.
```

### Schema builders (erlmcp_schema)

```erlang
object([{Name, TypeSchema, Opts}]) -> schema().
field(Name :: binary(), TypeSchema) -> {binary(), schema(), []}.
field(Name :: binary(), TypeSchema, [Opt]) -> {binary(), schema(), [Opt]}.
string() -> schema().   integer() -> schema().
number() -> schema().   boolean() -> schema().
enum([binary()]) -> schema().
array(schema()) -> schema().
%% Opts: required, {doc, binary()}, {default, V}, {min, N}, {max, N}
```

### Content constructors (erlmcp)

```erlang
erlmcp:text(Binary) -> #{<<"type">> => <<"text">>, <<"text">> => Binary}.
```

### Error codes (JSON-RPC)

- `-32601` — tool not found (catch-all clause)
- `-32602` — invalid params (unknown vertex, bad input)
- `-32603` — internal error (graph not loaded)

---

## graffeo API reference (subset needed for this slice)

```erlang
%% Read accessors
vertex_label(Graph, Vertex) -> {ok, Label} | error.
in_degree(Graph, Vertex) -> non_neg_integer().
out_degree(Graph, Vertex) -> non_neg_integer().
in_neighbours(Graph, Vertex) -> [vertex()].
out_neighbours(Graph, Vertex) -> [vertex()].
edge_meta(Graph, V1, V2) -> {ok, EdgeMeta} | error.
vertices(Graph) -> [vertex()].

%% Traversal
bfs(Graph, Vertex, Opts) -> [{vertex(), non_neg_integer()}].
  %% Opts: #{direction => out|in|both,
  %%         filter => fun((From, To) -> bool())
  %%                 | fun((From, To, Meta) -> bool())}
  %% Arity-3 filter receives edge metadata — use for type filtering.

%% Connectivity / DAG operations
topsort(Graph) -> {ok, [vertex()]} | false.
reachable(Graph, [vertex()]) -> [vertex()].
reachable_neighbours(Graph, [vertex()]) -> [vertex()].
reaching(Graph, [vertex()]) -> [vertex()].
reaching_neighbours(Graph, [vertex()]) -> [vertex()].
is_acyclic(Graph) -> boolean().
condensation(Graph) -> Graph.

%% Constructive  — UNSUPPORTED on the Mnesia backend (see Amendment A1).
%% These begin with Backend:empty_like/1, which graffeo_mnesia refuses by
%% design. Run them only on a map-backed graph (graffeo:new/0).
filter_edges(Graph, fun(From, To, Meta) -> bool()) -> Graph.
subgraph(Graph, [vertex()]) -> Graph.
condensation(Graph) -> Graph.
```

All functions are called through the `graffeo` facade module (e.g.
`(graffeo:vertex_label graph id)`). Do not call backend modules directly.

**Backend capability boundary (read this before using any constructive op).**
graffeo splits every backend into a *read-half* (`graffeo_backend`: `vertices`,
`in/out_neighbours`, `in/out_degree`, `edge_meta`, `vertex_label`, `bfs`,
`topsort`, `reachable`, `reaching_neighbours`, …) that is **universal**, and a
*build-half* (`graffeo_builder`: `empty_like`, `build_add_vertex`,
`build_add_edge`) that the **disk backends (mnesia, dets) deliberately do not
support**. Any op that *materializes a derived graph* —
`filter_edges`/`subgraph`/`condensation`/`contract` — uses the build-half and
therefore must run on a map-backed graph. The runtime graph is Mnesia-backed,
so: read directly off it, but **project into `graffeo:new/0` (map) before any
constructive/DAG-shaping op.** `bfs` is read-half only and runs fine on Mnesia.

---

## What to build

### 1. `graffeo-mcp-query` (new module)

Pure query logic. No MCP types, no formatting, no persistent_term access.
Every function takes the graph handle as its first argument.

**Exports (suggested names — adjust if better names emerge):**

```lfe
(export
 (get-node-data 2)       ;; (graph, id) -> {ok, map()} | error
 (get-node-edges 3)      ;; (graph, id, direction) -> [edge-info()]
 (find-related 4)        ;; (graph, id, relationship, limit) -> [slug()]
 (neighborhood 4)        ;; (graph, id, radius, relationship) -> [{slug(), depth}]
 (prerequisites 2)       ;; (graph, id) -> {direct, transitive}
 (dependents 3)          ;; (graph, id, depth) -> {direct, all}
 (learning-path 2)       ;; (graph, id) -> {ok, [slug()]} | {error, reason}
 (topsort-prereqs 2)     ;; (graph, limit) -> {ok, [slug()]} | {error, reason}
 (project-prerequisites 1))  ;; (graph) -> subgraph
```

**Implementation notes:**

**`get-node-data/2`**: Look up the abstract vertex by id. Return a map with
concept name, category, tier, in-degree, out-degree, and source count (number
of source vertices that link to this concept via membership edges). Use
`vertex_label/2` for the label, `in_degree/2`, `out_degree/2`. For source
count, count tuple vertices in `in_neighbours/2` results.

```lfe
(defun get-node-data (graph id)
  (case (graffeo:vertex_label graph id)
    ((tuple 'ok label) (when (is_map label))
     (let* ((in-d  (graffeo:in_degree graph id))
            (out-d (graffeo:out_degree graph id))
            (in-ns (graffeo:in_neighbours graph id))
            (srcs  (length (lc ((<- v in-ns) (is_tuple v)) v))))
       (tuple 'ok (map 'id       id
                       'label    label
                       'in_degree  in-d
                       'out_degree out-d
                       'sources    srcs))))
    (_ (tuple 'error 'not_found))))
```

**`get-node-edges/3`**: For the given vertex, collect edges in the requested
direction (`<<"in">>`, `<<"out">>`, or `<<"both">>`). For each edge, include
the other vertex's slug, the relationship type, and the weight. Skip source
vertices in the output (filter to abstract-to-abstract edges only) UNLESS the
edge is a membership edge (those connect source→abstract and are useful context).

**`find-related/4`**: Find concepts connected to id by the specified relationship
type (or all types if relationship is `undefined`/not provided). Walk both
in-neighbours and out-neighbours, check edge_meta for type match. Apply limit.
Return concept slugs only (not source vertices).

**`neighborhood/4`**: Use `graffeo:bfs/3` from the concept vertex. Use an
arity-3 filter to restrict to abstract-to-abstract edges and optionally filter
by relationship type:

```lfe
(defun neighborhood (graph id radius relationship)
  (let* ((filter (make-bfs-filter relationship))
         (result (graffeo:bfs graph id (map 'direction 'both 'filter filter))))
    (lc ((<- (tuple v d) result)
         (is_binary v)
         (> d 0)
         (<= d radius))
        (tuple v d))))
```

The BFS filter function:

```lfe
(defun make-bfs-filter
  (('undefined)
   (lambda (from to _meta) (andalso (is_binary from) (is_binary to))))
  ((rel-type)
   (lambda (from to meta)
     (andalso (is_binary from) (is_binary to)
              (has-edge-type? meta rel-type)))))
```

**`project-prerequisites/1`**: Project the prerequisite subgraph into a **fresh
map-backed graph**. (See ledger Amendment A1: `graffeo:filter_edges/2` is a
constructive op and is **unsupported on the Mnesia backend** — it raises
`{unsupported_on_backend, empty_like, graffeo_mnesia}`. The same applies to
`subgraph`/`condensation`. The map backend supports all of them, so we project
into a map graph and run every downstream DAG op there.)

The map graph is functional (immutable): `add_vertex`/`add_edge` return a *new*
graph, so thread the accumulator rather than mutating in place.

```lfe
(defun project-prerequisites (graph)
  ;; graffeo:filter_edges/2 is unsupported on Mnesia (constructive op needs
  ;; empty_like). Build a map-backed projection from the read-half instead.
  (let* ((abs-vs (lc ((<- v (graffeo:vertices graph)) (is_binary v)) v))
         (g0     (lists:foldl
                  (lambda (v acc) (graffeo:add_vertex acc v))
                  (graffeo:new)
                  abs-vs)))
    (lists:foldl
     (lambda (from acc)
       (lists:foldl
        (lambda (to acc2)
          (if (is_binary to)
            (case (graffeo:edge_meta graph from to)
              ((tuple 'ok meta)
               (if (has-edge-type? meta 'prerequisites)
                 (graffeo:add_edge acc2 from to meta)
                 acc2))
              ('error acc2))
            acc2))
        acc
        (graffeo:out_neighbours graph from)))
     g0
     abs-vs)))
```

**`has-edge-type?/2`** (internal helper): Check whether an edge's metadata
includes the given type. Must handle both label shapes:

- Membership edges: `#{label => #{type => membership}}` → match against the
  `type` key
- Typed edges: `#{label => #{types => [atom()], ...}}` → check membership in
  the `types` list

```lfe
(defun has-edge-type? (meta type)
  (let ((label (maps:get 'label meta (map))))
    (case (maps:get 'type label 'undefined)
      (type 'true)        ;; matches the type atom directly
      ('undefined
       (lists:member type (maps:get 'types label '()))))))
```

**`prerequisites/2`**: Project prerequisite subgraph. Direct prerequisites =
`out_neighbours(prereq_subgraph, id)`. Transitive prerequisites =
`reachable_neighbours(prereq_subgraph, [id])`. Return both.

**`dependents/3`**: Project prerequisite subgraph. Direct dependents =
`in_neighbours(prereq_subgraph, id)`. If depth is `all`, transitive dependents =
`reaching_neighbours(prereq_subgraph, [id])`. If depth is an integer, use
`bfs(prereq_subgraph, id, #{direction => in})` and filter by `<= depth`.

**`learning-path/2`**: This is the most complex query.

1. Project prerequisite subgraph
2. `reachable(prereq_subgraph, [id])` — the dependency cone (id + all
   transitive prerequisites)
3. `subgraph(prereq_subgraph, cone)` — scoped subgraph
4. `topsort(scoped_subgraph)`:
   - If `{ok, Order}` — reverse it for learning order (foundations first)
   - If `false` (cycles exist) — use condensation approach:
     a. `condensation(scoped_subgraph)` — DAG of SCCs
     b. `topsort(condensed)` — should succeed (condensation is always a DAG)
     c. Reverse the SCC ordering
     d. Flatten: each SCC is a list of vertices; sort each SCC's members
        alphabetically for deterministic output
5. Return `{ok, OrderedList}`

Reference: the prototype `learning-order` function in
`graffeo/examples/erlang-concepts/src/lfeerlcpt-queries.lfe` — but note it
does NOT reverse, so it returns dependent-first order. You MUST reverse.

**`topsort-prereqs/2`**: Like learning-path but for the full prerequisite
graph (or scoped to a root if provided later in Slice 02). Uses the same
condensation+reverse approach. Apply limit to the result.

### 2. Update `graffeo-mcp-tools` (existing module)

Add 8 tool specs to `tools/0` and 8 clauses to `handle_tool/3`.

**Tool specs — each MUST have all discoverability keys:**

```
name, description, input_schema,
category, when_to_use, returns, next, entry_point, annotations
```

**Tool catalog:**

| # | name | category | entry_point | input_schema | next |
|---|------|----------|-------------|--------------|------|
| 1 | `get_node` | navigation | true | `id` (required) | `[get_node_edges, prerequisites, related]` |
| 2 | `get_node_edges` | navigation | false | `id` (required), `direction` (optional, enum: in/out/both, default both) | `[related, neighborhood]` |
| 3 | `related` | navigation | false | `id` (required), `relationship` (optional, enum: prerequisites/extends/related/contrasts_with), `limit` (optional, integer, default 20) | `[get_node, neighborhood]` |
| 4 | `neighborhood` | navigation | false | `id` (required), `radius` (optional, integer, default 2, max 5), `relationship` (optional, enum) | `[get_node, related]` |
| 5 | `prerequisites` | learning | false | `id` (required) | `[learning_path, dependents]` |
| 6 | `dependents` | learning | false | `id` (required), `depth` (optional, integer, default all) | `[prerequisites, learning_path]` |
| 7 | `learning_path` | learning | true | `id` (required) | `[get_node, prerequisites]` |
| 8 | `topsort` | learning | false | `limit` (optional, integer, default 50, max 200) | `[learning_path, get_node]` |

**`description` and `when_to_use` — write these carefully.** Each description
is one sentence explaining what the tool does. Each `when_to_use` explains
when an LLM should reach for this tool vs. alternatives. Be specific — these
are the primary discoverability signals.

Suggested descriptions (refine as needed):

- **get_node**: "Look up an Erlang concept by slug and get its category, tier,
  degree counts, and source coverage."
- **get_node_edges**: "List all edges (prerequisites, extends, related,
  contrasts_with, membership) for a concept, optionally filtered by direction."
- **related**: "Find concepts connected to a given concept through a specific
  relationship type."
- **neighborhood**: "Explore the local neighborhood around a concept via
  breadth-first search, limited to a specified radius."
- **prerequisites**: "List the direct and transitive prerequisites for a
  concept — what you need to learn first."
- **dependents**: "Find concepts that depend on a given concept — what builds
  on top of it."
- **learning_path**: "Get a topologically sorted learning path for a concept,
  starting from foundational prerequisites."
- **topsort**: "Get a topological ordering of the entire prerequisite graph —
  the global learning sequence."

**`returns` — be specific** about what the response text contains so the LLM
knows what to expect.

**`annotations`**: All 8 tools are read-only: `#{readOnlyHint => true,
idempotentHint => true}`.

**`handle_tool/3` clauses** — add before the catch-all. Pattern:

```lfe
((#"get_node" input _ctx)
 (case (persistent_term:get (tuple 'graffeo_mcp 'graph) 'undefined)
   ('undefined
    (tuple 'error -32603 #"Graph not loaded. The server is still starting."))
   (graph
    (let ((id (maps:get #"id" input #"")))
      (case (graffeo-mcp-query:get-node-data graph id)
        ((tuple 'ok data)
         (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-node data))))
        ((tuple 'error 'not_found)
         (tuple 'error -32602
                (iolist_to_binary
                 (list #"Unknown concept: " id)))))))))
```

For tools with optional params, use `maps:get` with a default:

```lfe
(let ((direction (maps:get #"direction" input #"both"))
      (limit     (maps:get #"limit" input 20)))
  ...)
```

### 3. Update `graffeo-mcp-format` (existing module)

Add format functions for each tool's response. Each function takes the query
result and returns a text binary.

**New exports:**

```lfe
(export
 ...existing...
 (format-node 1)
 (format-node-edges 1)
 (format-related 1)
 (format-neighborhood 1)
 (format-prerequisites 1)
 (format-dependents 1)
 (format-learning-path 1)
 (format-topsort 1))
```

**Format specifications:**

**`format-node/1`** — takes the data map from `get-node-data`:
```
Concept: <concept name from label>
Slug: <id>
Category: <category> | Tier: <tier>
In-degree: <N> | Out-degree: <M>
Sources: <count>
```

**`format-node-edges/1`** — takes `{id, edges}`:
```
Edges for <id>:

Outgoing:
  -> <target> (<type>, weight <W>)
  ...

Incoming:
  <- <source> (<type>, weight <W>)
  ...
```

**`format-related/1`** — takes `{id, relationship, concepts}`:
```
Related to <id> (<N> concepts):
  <slug> (<type>)
  ...
```

**`format-neighborhood/1`** — takes `{id, radius, vertices_with_depth}`:
```
Neighborhood of <id> (radius <R>, <N> concepts):
  Depth 1: <slug>, <slug>, ...
  Depth 2: <slug>, <slug>, ...
```

**`format-prerequisites/1`** — takes `{id, direct, transitive}`:
```
Prerequisites for <id>:
  Direct (<N>): <slug>, <slug>, ...
  Transitive (<M> total): <slug>, <slug>, ...
```

**`format-dependents/1`** — takes `{id, direct, all}`:
```
Dependents of <id>:
  Direct (<N>): <slug>, <slug>, ...
  All (<M> total): <slug>, <slug>, ...
```

**`format-learning-path/1`** — takes `{id, path}`:
```
Learning path to <id> (<N> steps):
  1. <slug>
  2. <slug>
  ...
  N. <id>
```

**`format-topsort/1`** — takes `{order, total}`:
```
Topological order (<N> of <total> concepts):
  1. <slug>
  2. <slug>
  ...
```

### 4. Tests

**Shared fixture design.** The Arc 1 fixture (1 source, 1–2 abstract concepts)
is too small. Build a richer fixture for Arc 2 tests:

```
Source vertices:
  {src-a, concept-a}
  {src-a, concept-b}
  {src-a, concept-c}

Abstract vertices:
  concept-a  (category: concurrency, tier: basic)
  concept-b  (category: concurrency, tier: intermediate)
  concept-c  (category: otp,         tier: basic)
  concept-d  (category: otp,         tier: advanced)  ← ghost (no source)

Edges:
  {src-a, concept-a} → concept-a  membership (weight 0.5)
  {src-a, concept-b} → concept-b  membership (weight 0.5)
  {src-a, concept-c} → concept-c  membership (weight 0.5)
  concept-b → concept-a           prerequisites (weight 1.0)  ← b requires a
  concept-d → concept-b           prerequisites (weight 1.0)  ← d requires b
  concept-c → concept-a           extends       (weight 1.0)  ← c extends a
  concept-a → concept-c           related       (weight 2.0)  ← a related to c
```

This fixture supports:

- `get_node` on concept-a: has label, category, tier, degree counts, 1 source
- `get_node_edges` on concept-a: in-edges (membership, prerequisites, extends),
  out-edges (related)
- `related` on concept-a with type=related: returns concept-c
- `neighborhood` on concept-a radius 1: concept-b, concept-c (abstract only)
- `prerequisites` of concept-d: direct=[concept-b], transitive=[concept-b,
  concept-a] (d→b→a)
- `dependents` of concept-a: direct=[concept-b], transitive=[concept-b,
  concept-d] (b→a←, d→b→a←)

  Wait — dependents of concept-a means "things that depend on a." Edge
  direction: b→a means "b requires a." So b depends on a. And d→b means
  d depends on b, which depends on a. So dependents of a = {b, d}. Correct.

- `learning_path` to concept-d: [concept-a, concept-b, concept-d]
  (a is foundational, then b, then d)
- `topsort`: reverse of topsort(prereq) should start with concept-a

**`graffeo-mcp-query-tests` (new module, ~8+ tests):**

Define a `setup-rich-graph` function using the fixture above. MUST test:

1. `get-node-data` returns correct data map for known vertex
2. `get-node-data` returns error for unknown vertex
3. `get-node-edges` returns correct edges (check type, check weight)
4. `find-related` filters by relationship type
5. `neighborhood` respects radius
6. `prerequisites` returns correct direct and transitive sets
7. `dependents` returns correct sets
8. `learning-path` returns foundations-first ordering

Each test creates and tears down its own Mnesia graph in try/after.

**`graffeo-mcp-tools-tests` (extend, ~8+ new tests):**

Add a `setup-rich-graph` function (same fixture or a simplified version).
Use the existing `with-graph` pattern (persistent_term setup/cleanup).

MUST add tests:

1. `get-node-returns-ok` — dispatch test: handle_tool returns `{ok, Content}`
   with concept data in text
2. `get-node-unknown-returns-error` — handle_tool returns `{error, -32602, _}`
3. Each of the remaining 7 tools: at least one dispatch test verifying the
   `{ok, Content}` path
4. `new-tools-handle-missing-graph` — test that all 8 new tool names return
   `{error, -32603, _}` when persistent_term has no graph

**`graffeo-mcp-format-tests` (extend, ~4+ new tests):**

Test at least: format-node, format-learning-path, and two others of your choice.
Assert that output text is binary and contains expected key strings.

**Register all new test modules in `rebar.config` under `eunit_tests`.**

---

## LFE conventions (enforced)

- 2-space indent, 80-char max, kebab-case modules
- Alphabetical exports (public API first, then callbacks if applicable)
- Docstrings on all public functions
- Explicit exports — no `(export all)`
- `mref`/`mset` for map access, `#"..."` for binary strings
- Pattern match in function heads where natural
- `try ... (after ...)` for Mnesia cleanup in tests
- Use LFE list comprehensions `(lc ...)` for filtering/mapping

## Ledger discipline

Work against the ledger. Update each row's Status/Evidence as you close it.
If a criterion is wrong or impossible, raise an amendment — do not silently
work around it. Closing report = per-row walk with disposition for every row.

## Acceptance summary

| ID | Short | Verify |
|----|-------|--------|
| S1-01 | Query module exists | grep |
| S1-02 | 10 tool specs | test |
| S1-03 | Full discoverability metadata | grep count ≥10 |
| S1-04 | Entry point correctness | test |
| S1-05 | Input schemas correct | code |
| S1-06 | get_node works | test |
| S1-07 | get_node unknown error | test |
| S1-08 | get_node_edges typed | test |
| S1-09 | get_node_edges direction | test |
| S1-10 | related filters | test |
| S1-11 | neighborhood radius | test |
| S1-12 | prerequisites chain | test |
| S1-13 | dependents | test |
| S1-14 | learning_path ordered | test |
| S1-15 | topsort valid | test |
| S1-16 | next chains connected | grep/code |
| S1-17 | Missing graph handled | test |
| S1-18 | Zero compile warnings | rebar3 compile |
| S1-19 | All tests pass | rebar3 eunit |
