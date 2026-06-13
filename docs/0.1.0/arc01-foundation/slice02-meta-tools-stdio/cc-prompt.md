# CC Prompt — Slice 02: Meta Tools + Handler + stdio Transport

**Arc:** 01 (Foundation)
**Depends on:** Slice 01 (commit 7e693bd + CDC remediation)
**Iteration cap:** 5

## What to read first

1. **This prompt** (you're reading it)
2. **Slice doc:** `docs/0.1.0/arc01-foundation/slice02-meta-tools-stdio/slice-doc.md`
3. **Ledger:** `docs/0.1.0/arc01-foundation/slice02-meta-tools-stdio/ledger.md` (19 rows)
4. **Architecture doc §3.1, §4.6, §4.7, §4.8:** `docs/architecture.md`
5. **LFE style guide:** `lfe-manual/src/part7/ai-resources/style-guide.md`
6. **LFE language guide:** `lfe/doc/src/lfe_guide.7.md`
7. **Existing source:** all files in `src/` and `test/` (Slice 01 baseline)

You MUST load the erlang-guidelines skill before writing any code.

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
string() -> schema().
integer() -> schema().
number() -> schema().
boolean() -> schema().
enum([binary()]) -> schema().
array(schema()) -> schema().
%% Opts: required, {doc, binary()}, {default, V}, {min, N}, {max, N}
```

### Content constructors (erlmcp)

```erlang
erlmcp:text(Binary) -> #{<<"type">> => <<"text">>, <<"text">> => Binary}.
```

### Server setup

```erlang
erlmcp:start_stdio_setup(ServerId :: atom(), Config :: map()) ->
    {ok, pid()} | {error, term()}.
%% Config keys: name, version, purpose, source, handler, handlers, ...
%% handler => Module causes auto-registration of the handler module.
```

### Instructions generator

```erlang
erlmcp_instructions:generate(ServerIdentity :: map(), AllTools :: [map()]) ->
    binary().
%% ServerIdentity: #{name, version, purpose, source}
%% AllTools: the list returned by your tools/0
```

### Error codes (JSON-RPC)

- `-32601` — method/tool not found
- `-32602` — invalid params
- `-32603` — internal error

## What to build

### 1. `graffeo-mcp-tools` (new module)

MUST implement `erlmcp_server_handler` behaviour.

**`tools/0`** — returns a list of exactly 2 tool spec maps:

```lfe
;; Each tool map MUST contain all of these keys:
;;   name, description, input_schema,
;;   category, when_to_use, next, entry_point, annotations
```

**status tool spec:**
- `name => <<"status">>`
- `description` — one sentence: what the graph is and what this tool reports
- `input_schema` — `erlmcp_schema:object([])` (no required params)
- `category => <<"meta">>`
- `when_to_use` — when to call this tool (first thing, orientation, health check)
- `returns` — what the response contains (loaded state, counts, backend)
- `next => [<<"info">>]`
- `entry_point => true`
- `annotations => #{readOnlyHint => true, idempotentHint => true}`

**info tool spec:**
- `name => <<"info">>`
- `description` — one sentence: detailed statistics including distributions
- `input_schema` — `erlmcp_schema:object([])` (no required params)
- `category => <<"meta">>`
- `when_to_use` — when deeper statistics are needed beyond what status shows
- `returns` — what the response contains (counts, category dist, type breakdown)
- `next => [<<"get_node">>, <<"learning_path">>]`
- `entry_point => false`
- `annotations => #{readOnlyHint => true, idempotentHint => true}`

**`handle_tool/3`** — pattern-match on tool name:

```lfe
(defun handle_tool
  ((#"status" _input _ctx)
   ...)
  ((#"info" _input _ctx)
   ...)
  ((name _input _ctx)
   (tuple 'error -32601
          (iolist_to_binary (list #"Unknown tool: " name)))))
```

For both tools:
1. Get graph from `persistent_term:get({graffeo_mcp, graph}, undefined)`
2. If `undefined`, return `{error, -32603, <<"Graph not loaded">>}`
3. Otherwise, call the appropriate `graffeo-mcp-format` function
4. Wrap result in `(erlmcp:text Result)`
5. Return `{ok, Content}`

### 2. `graffeo-mcp-format` (new module)

Response formatting. MUST export at least two public functions for status
and info formatting. Suggested API:

**`format-status/1`** — takes the graph handle, returns a text binary:
```
Erlang Knowledge Graph: loaded
Vertices: <N> | Edges: <M>
Backend: Mnesia (disc_copies)
```

**`format-info/1`** — takes the graph handle, returns a text binary:
```
Graph Statistics

Vertices: <N> (source: <S>, abstract: <A>)
Edges: <M>

Categories (<C> categories):
  <category-1>: <count>
  <category-2>: <count>
  ...

Relationship Types:
  membership: <count> (weight 0.5)
  prerequisites: <count> (weight 1.0)
  extends: <count> (weight 1.0)
  related: <count> (weight 2.0)
  contrasts_with: <count> (weight 3.0)
```

To compute category distribution:
- Get abstract vertices via `graffeo-mcp-ingest:abstract-vertices/1`
- For each, read vertex label via `graffeo:vertex_label/2`
- Count by the `category` key in the label map

To compute relationship type breakdown:
- Get all edges via `graffeo:edges/1`
- For each `{From, To}`, read edge metadata via `graffeo:edge_meta/3`
- Count by the `type` key in `label` within the edge metadata (for
  membership edges) or by iterating the `types` list in `label` (for
  typed edges)

Note: membership edges have `label => #{type => membership}` while
abstract/source edges have `label => #{types => [atom()], asserted_by => [...]}`.
The format function MUST handle both label shapes.

### 3. Modify `graffeo-mcp-app` (existing module)

`start/2` MUST wire the erlmcp server after the supervisor is running.
The supervisor's `start_link` is synchronous — by the time it returns,
`graffeo-mcp-graph:init/1` has completed and the graph is in persistent_term.

Approach:

```lfe
(defun start (_type _args)
  (case (graffeo-mcp-sup:start-link)
    ((= (tuple 'ok _) result)
     (start-mcp)
     result)
    (error error)))

(defun start-mcp ()
  "Start the erlmcp server with stdio transport."
  (erlmcp:start_stdio_setup 'graffeomcp
    (map 'name    #"graffeo-mcp"
         'version #"0.1.0"
         'purpose #"Erlang knowledge graph for LLM-driven concept exploration"
         'handler 'graffeo-mcp-tools)))
```

If `start_stdio_setup` doesn't accept a `handler` key directly (test this —
compile and check), use the two-step approach:

```lfe
(defun start-mcp ()
  (let* ((config (map 'name    #"graffeo-mcp"
                      'version #"0.1.0"
                      'purpose #"Erlang knowledge graph ..."))
         ((tuple 'ok server) (erlmcp:start_server 'graffeomcp config)))
    (erlmcp:register_handler server 'graffeo-mcp-tools)
    ;; Wire stdio transport separately — check erlmcp API for the right call
    ))
```

The exact wiring depends on what erlmcp exposes. MUST compile and test —
do not guess. If you hit an erlmcp API issue, document it as a finding
and work around it (or raise an amendment if unworkable).

### 4. Tests: `graffeo-mcp-tools-tests` (new module)

MUST test all three handle_tool branches and both response formats.

**Test setup pattern:** each test creates a small Mnesia graph with known
content (reuse or adapt the fixture pattern from `graffeo-mcp-ingest-tests`),
stores it in persistent_term, calls `handle_tool/3` directly, and cleans up
in `(after ...)`.

Suggested fixture: 3 vertices (2 source + 1 abstract), 2 edges (1 membership
+ 1 prerequisite). This gives known counts for assertion.

**MUST include these tests:**

1. **status-returns-ok-with-counts** — set up graph, call `handle_tool(<<"status">>, #{}, ctx())`,
   assert `{ok, Content}` where Content text contains vertex and edge counts.
   For ctx, use a minimal map or `erlmcp_ctx:new(#{session => self(), request_id => 1})`.

2. **info-returns-ok-with-distribution** — set up graph with at least 2 categories,
   call `handle_tool(<<"info">>, #{}, ctx())`, assert response text contains
   category names and counts.

3. **unknown-tool-returns-error** — call `handle_tool(<<"nonexistent">>, #{}, ctx())`,
   assert `{error, -32601, _}`.

4. **status-handles-missing-graph** — ensure persistent_term key is absent
   (`persistent_term:erase({graffeo_mcp, graph})`), call status, assert
   `{error, -32603, _}`.

5. **tools-returns-two-specs** — call `tools()`, assert length is 2, assert
   both have `name`, `category`, `when_to_use`, `annotations` keys.

Add the new test module to `rebar.config` under `eunit_tests` in the test
profile.

### 5. Tests: `graffeo-mcp-format-tests` (new module)

MUST test format functions independently of the handler.

1. **format-status-includes-counts** — create graph with known vertex/edge
   counts, call format-status, assert the binary contains the expected numbers.

2. **format-info-includes-categories** — create graph with labeled vertices
   (different categories), call format-info, assert category names appear.

Add to `rebar.config` `eunit_tests`.

## LFE conventions (enforced)

- 2-space indent, 80-char max, kebab-case modules
- Alphabetical exports (public API first, then callbacks if applicable)
- Docstrings on all public functions
- Explicit exports — no `(export all)`
- `mref`/`mset` for map access, `#"..."` for binary strings
- Pattern match in function heads
- `try ... (after ...)` for Mnesia cleanup in tests

## Ledger discipline

Work against the ledger. Update each row's Status/Evidence as you close it.
If a criterion is wrong or impossible, raise an amendment — do not silently
work around it. Closing report = per-row walk with disposition for every row.

## Acceptance summary

| ID | Short | Verify |
|----|-------|--------|
| S2-1 | Handler behaviour | grep |
| S2-2 | 2 tool specs | grep |
| S2-3 | Full discoverability metadata | grep count ≥10 |
| S2-4 | Entry point correctness | code/test |
| S2-5 | Annotation hints | grep |
| S2-6 | status dispatch works | test |
| S2-7 | info dispatch works | test |
| S2-8 | Unknown tool error | test |
| S2-9 | status has counts | test |
| S2-10 | info has categories | test |
| S2-11 | info has type breakdown | test |
| S2-12 | format module exists | grep |
| S2-13 | App wires erlmcp | grep |
| S2-14 | Server identity | grep |
| S2-15 | No required params | code |
| S2-16 | Next chains | grep |
| S2-17 | Missing graph handled | test |
| S2-18 | Zero compile warnings | rebar3 compile |
| S2-19 | All tests pass | rebar3 eunit |
