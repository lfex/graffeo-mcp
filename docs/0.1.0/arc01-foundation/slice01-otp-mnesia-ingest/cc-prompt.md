# CC Prompt: Arc 01, Slice 01 — OTP Skeleton + Mnesia Graph + Ingest

## Assignment

Build the graffeo-mcp OTP application skeleton, Mnesia graph engine, concept
card parser, and ingest pipeline. This is an LFE project — all source files
are `.lfe`. Port the existing prototype from `graffeo/examples/erlang-concepts/`
with three adaptations: Mnesia backend, edge weights, and gen_server lifecycle.

## Before writing code

1. Read the **ledger** (`slice01-otp-mnesia-ingest/ledger.md`) — it is the
   specification, not a post-hoc checklist.
2. Read the **architecture doc** (`docs/architecture.md`) §§0–5.
3. Read the **LFE proto-skill** references:
   - Erlang SKILL: `priv/ai/erlang/SKILL.md` (via erlang-guidelines)
   - LFE guide: `lfe/doc/src/lfe_guide.7.md`
   - LFE style guide: `lfe-manual/src/part7/ai-resources/style-guide.md`
4. Read the **prototype source** to port from:
   - `graffeo/examples/erlang-concepts/src/lfeerlcpt-parser.lfe`
   - `graffeo/examples/erlang-concepts/src/lfeerlcpt-ingest.lfe`
   - `graffeo/examples/erlang-concepts/src/lfeerlcpt.lfe`
5. Read the **Mnesia backend API**: `graffeo/src/graffeo_mnesia.erl`
   (especially `open/2`, `add_vertex/2,3`, `add_edge/3,4`, `transaction/1`)
6. Read the **ledger discipline**: `priv/ai/LEDGER_DISCIPLINE.md`

## What to build

### Build infrastructure

**`rebar.config`:**
```erlang
{deps, [
    {lfe, "2.2.0"},
    {graffeo, {git, "https://github.com/erlsci/graffeo.git", {branch, "main"}}},
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {branch, "release/0.6.x"}}}
]}.
{plugins, [rebar3_lfe]}.
{provider_hooks, [{post, [{compile, {lfe, compile}}]}]}.
```

**`src/graffeomcp.app.src`:**
- Application name: `graffeomcp`
- Applications: `[kernel, stdlib, mnesia, graffeo, erlmcp]`
- Modules: `[]` (auto-populated)

**`Makefile`:**
- `compile`: `rebar3 compile`
- `test`: `rebar3 eunit`
- `fetch-cards`: shallow clone of `billosys/ai-engineering`, copy
  `knowledge/erlang/concept-cards/` to `priv/concept-cards/`
- `clean`: `rebar3 clean`

### Modules

**`graffeo-mcp-app`** — OTP application callback. Minimal: `start/2` calls
`graffeo-mcp-sup:start_link/0`, `stop/1` returns `ok`.

**`graffeo-mcp-sup`** — Supervisor. Strategy: `one_for_one`, intensity 5,
period 10. Single child: `graffeo-mcp-graph` as a `worker` with
`restart => permanent`.

**`graffeo-mcp-graph`** — gen_server managing the Mnesia graph lifecycle.

- `init/1`:
  1. Call `graffeo_mnesia:open("erlang_concepts", #{storage => disc_copies})`
  2. Check `graffeo:no_vertices/1` — if 0, run ingest synchronously
  3. Store handle: `persistent_term:put({graffeo_mcp, graph}, Graph)`
  4. Return `{ok, State}` where State holds the graph ref

- `handle_call`:
  - `get_graph` → return the graph handle
  - `graph_stats` → return `#{vertices => N, edges => M}`

- The cards directory defaults to `code:priv_dir(graffeomcp) ++ "/concept-cards"`

**`graffeo-mcp-parser`** — Port from `lfeerlcpt-parser.lfe`. Same API:
- `parse-file/1` → `{ok, Card}` | `{error, Reason}`
- `parse-string/1` → `{ok, Card}` | `{error, Reason}`

The parser is a near-direct port. Keep the same frontmatter extraction,
line classification, and card building logic.

**`graffeo-mcp-ingest`** — Port from `lfeerlcpt-ingest.lfe` with adaptations:

- `build/2` takes `(cards graph)` instead of `(cards)` — the graph is
  already opened by `graffeo-mcp-graph`, passed in as an argument.
- `build-from-dir/2` takes `(dir graph)` — parses all cards, then calls
  `build/2`.
- **Mnesia adaptation:** The prototype threads an accumulator (`g0 → g1 →
  ... → g5`). With Mnesia, mutations are in-place. Replace the threading
  with direct mutation on the passed-in graph handle. Wrap in
  `graffeo_mnesia:transaction/1`.
- **Edge weights:** When adding edges, include weight in metadata:
  - `prerequisite`: `#{weight => 1.0, label => #{types => ..., ...}}`
  - `extends`: `#{weight => 1.0, ...}`
  - `related`: `#{weight => 2.0, ...}`
  - `contrasts_with`: `#{weight => 3.0, ...}`
  - `membership`: `#{weight => 0.5, ...}`

### Tests

**`test/graffeo-mcp-parser-tests.lfe`:**
- Parse a known-good concept card file → assert all fields present
- Parse malformed input (no frontmatter) → assert `{error, _}`
- Parse input with missing required field → assert `{error, _}`
- Include a small test fixture card in `test/fixtures/`

**`test/graffeo-mcp-ingest-tests.lfe`:**
- Build a graph from 3-5 hand-crafted cards → assert vertex/edge counts
- Assert source vertices are tuples, abstract vertices are binaries
- Assert membership edges connect source to abstract
- Assert edge weights match specification
- Assert typed edges carry correct `types` metadata

**`test/graffeo-mcp-graph-tests.lfe`:**
- Start the gen_server with a test graph name → assert it opens and stores
  in persistent_term
- (Full integration test with real cards is F-17/F-18; may need the cards
  fetched first — note this dependency)

## LFE conventions to follow

- 2-space indent, 80-char lines
- Kebab-case module names matching filenames
- Explicit exports with arities, alphabetically sorted
- No `(export all)`
- Docstrings on all public functions
- Pattern match in function heads
- Use `mref` / `mset` for map access (short forms)
- Use `#"..."` for binary strings
- Comments: `;;;;` file, `;;;` section, `;;` block, `;` inline

## Ledger discipline

Work against the ledger. Update Evidence as you go. If a criterion is
wrong or impossible, raise an amendment — don't silently work around it.
Iteration budget: 5.

## Checkpoint

At slice close, these must all be true:
- `rebar3 compile` — zero warnings
- `rebar3 eunit` — all tests pass
- Application starts and populates a Mnesia graph
- `persistent_term:get({graffeo_mcp, graph})` returns a live handle
- Ledger rows updated with commit SHA + verify output
