# Ledger — Arc 2, Slice 01: Navigation + Learning Tools

**Arc:** 02 (Core Tools + Discoverability)
**Depends on:** Arc 01 complete (commit 738d5f3)
**Iteration cap:** 5

## Acceptance criteria

| ID | Criterion | Verify | Status | Evidence |
|----|-----------|--------|--------|----------|
| S1-01 | `graffeo-mcp-query` module exists with query exports | `grep 'export' src/graffeo-mcp-query.lfe` shows ≥8 exported functions | ✅ | 9 exports: dependents/3, find-related/4, get-node-data/2, get-node-edges/3, learning-path/2, neighborhood/4, prerequisites/2, project-prerequisites/1, topsort-prereqs/2 |
| S1-02 | `tools/0` returns exactly 10 tool specs (2 meta + 8 new) | test: `tools-returns-ten-specs` | ✅ | `tools-returns-ten-specs` passes; asserts length 10 + every discoverability key present |
| S1-03 | All 10 tools carry full discoverability metadata (category, when_to_use, returns, next, entry_point, annotations) | `grep -c 'when_to_use' src/graffeo-mcp-tools.lfe` ≥ 10 | ✅ | `grep -c when_to_use` = 10; `grep -c entry_point` = 10; `grep -c 'next` = 10 |
| S1-04 | Entry points correct: status, get_node, learning_path are true; all others false | test: `entry-point-correctness` | ✅ | `entry-point-correctness` passes; entry set = [get_node, learning_path, status] |
| S1-05 | Input schemas correct: lookup tools have required `id`; optional params have defaults | code inspection of `tools/0` | ✅ | All 6 id-keyed tools mark `id` required; direction default `both`, limit default 20/50, radius default 2/max 5, topsort limit default 50/max 200; dependents `depth` optional (absence = all) |
| S1-06 | `get_node` returns concept data (name, category, tier, degree counts) for known vertex | test: `get-node-returns-concept-data` | ✅ | query-test `get-node-returns-concept-data` + dispatch `get-node-returns-ok` pass |
| S1-07 | `get_node` returns `-32602` error for unknown vertex | test: `get-node-unknown-returns-error` | ✅ | query-test `get-node-unknown-returns-error` ({error,not_found}) + dispatch `get-node-unknown-returns-error` (-32602) pass |
| S1-08 | `get_node_edges` returns edges with type and weight | test: `get-node-edges-returns-typed-edges` | ✅ | `get-node-edges-returns-typed-edges` passes (a→c related, weight 2.0) |
| S1-09 | `get_node_edges` direction filter works (in-only vs out-only) | test: `get-node-edges-direction-filter` | ✅ | `get-node-edges-direction-filter` passes (out=1, in=3 incl. membership+prereq) |
| S1-10 | `related` returns concepts filtered by relationship type | test: `related-filters-by-type` | ✅ | `related-filters-by-type` passes (type=related → [{concept-c, related}]) |
| S1-11 | `neighborhood` returns BFS walk within specified radius | test: `neighborhood-respects-radius` | ✅ | `neighborhood-respects-radius` passes (r=1 → {b,c}; r=2 adds d). Required Amendment A2 (arity-2 BFS filter). |
| S1-12 | `prerequisites` returns transitive prerequisite chain | test: `prerequisites-returns-chain` | ✅ | `prerequisites-returns-chain` passes (d → direct [b], transitive [a,b]) |
| S1-13 | `dependents` returns reverse prerequisite dependencies | test: `dependents-returns-deps` | ✅ | `dependents-returns-deps` passes (a → direct [b], all [b,d]) |
| S1-14 | `learning_path` returns topological order (foundations first) | test: `learning-path-foundations-first` | ✅ | `learning-path-foundations-first` passes (d → [a,b,d]) |
| S1-15 | `topsort` returns valid topological ordering | test: `topsort-valid-ordering` | ✅ | `topsort-valid-ordering` passes (constrained order a≺b≺d) |
| S1-16 | `next` chains connect all tools — no orphans, no dead ends | grep + code inspection: every tool's `next` list names only tools that exist; every non-entry-point tool is named in at least one other tool's `next` | ✅ | `next-chains-name-existing-tools` test passes. Required Amendment A3: `topsort` was orphaned by the catalog's literal `next` values; added to `learning_path.next`. |
| S1-17 | All 8 new tools handle missing graph gracefully (return `-32603`) | test: `new-tools-handle-missing-graph` | ✅ | `new-tools-handle-missing-graph` iterates all 8 names → -32603 |
| S1-18 | Zero compile warnings | `rebar3 compile 2>&1 \| grep -ci warning` = 0 (excluding LFE stdlib warnings) | ✅ | `grep -ci warning` = 0 |
| S1-19 | All tests pass | `rebar3 eunit` | ✅ | `All 51 tests passed.` (was 27 before this slice) |

## Amendment A1 — `project-prerequisites/1` cannot use `graffeo:filter_edges/2`

**Raised:** before implementation, during a backend deep-dive.
**Status:** accepted — spec corrected; criteria unchanged.

The cc-prompt and slice-doc specify projecting the prerequisite subgraph with
`graffeo:filter_edges/2`, and the downstream learning-path design uses
`graffeo:subgraph/2` and `graffeo:condensation/1`. **All three are unavailable
on the Mnesia backend.** They are *constructive* ops: each begins with
`Backend:empty_like(G)`, and `graffeo_mnesia:empty_like/1` deliberately raises
`{unsupported_on_backend, empty_like, graffeo_mnesia}` (verified empirically and
in source — `graffeo_conn.erl` call sites 204/265/304/371; both disk backends,
mnesia and dets, refuse it by design — see the Arc 1 Slice 01 ledger
"Architectural boundary" note for the full trace).

The design was ported from the prototype `lfeerlcpt-queries.lfe`, which runs on
the **map** backend where these ops work. graffeo-mcp uses Mnesia for durable
storage, so the projection step must change.

**Corrected approach (functionally equivalent, verified end-to-end):**
`project-prerequisites/1` builds a fresh **map-backed** graph via `graffeo:new/0`
(map-backed, GC'd, no cleanup), iterating the Mnesia graph's abstract vertices +
`out_neighbours` + `edge_meta`, copying only `prerequisites`-typed
abstract→abstract edges. All downstream DAG ops (`reachable`,
`reachable_neighbours`, `reaching_neighbours`, `subgraph`, `topsort`,
`condensation`, `in/out_neighbours`) then run on the **map projection**, which
fully supports the build-half. `neighborhood` still uses `graffeo:bfs/3`
directly on the Mnesia graph (bfs is read-half only — verified working).

No acceptance criterion changes. The query results are identical to the
filter_edges-based design; only the projection mechanism differs. The map graph
is immutable/functional, so projection threads the accumulator (g0→gN) rather
than mutating in place.

## Amendment A2 — `neighborhood/4` cannot use a meta-aware (arity-3) BFS filter

**Raised:** during implementation, when `neighborhood-respects-radius` failed.
**Status:** accepted — implementation corrected; criteria unchanged.

The cc-prompt's `neighborhood/4` design (and `make-bfs-filter`) uses
`graffeo:bfs/3` with `#{direction => both}` and an **arity-3** filter
`fun(From, To, Meta) -> bool()` to restrict traversal to abstract↔abstract edges
and optionally by relationship type. **On the Mnesia backend, an arity-3 BFS
filter silently skips all incoming edges** — it is only ever invoked on outgoing
edges, so `direction => both`/`in` degenerate to out-only. Verified empirically:

```
arity2 both:  [{<<"a">>,0},{<<"b">>,1}]   %% b<-a in-edge traversed
arity3 both:  [{<<"a">>,0}]               %% in-edge dropped, filter never called
arity2 in:    [{<<"a">>,0},{<<"b">>,1}]
arity3 in:    [{<<"a">>,0}]
nofilter in:  [{<<"a">>,0},{<<"b">>,1}]
```

(Same read-half/build-half family of facade gaps as Amendment A1 and the Slice 02
`edges/1` gap — a graffeo behaviour is only partially wired through the facade
for one backend.)

**Corrected approach:** `neighborhood/4` uses an **arity-2** filter
`fun(From, To) -> is_binary(From) andalso is_binary(To)` (abstract-only), which
traverses both directions correctly. Relationship-type restriction — which
genuinely needs edge metadata — is handled *before* the walk by projecting a
type-filtered **map graph** (`project-by-type/2`, a generalization of
`project-prerequisites/1` over an arbitrary edge-type predicate) and running the
arity-2 BFS on that projection. The result is identical to the intended
meta-aware filter, without relying on the broken arity-3 path. `dependents/3`'s
bounded BFS uses `#{direction => in}` with **no** filter (the unfiltered path
traverses in-edges correctly) and post-filters by depth, so it is unaffected.

No acceptance criterion changes.

## Amendment A3 — `topsort` added to `learning_path`'s `next` chain

**Raised:** during implementation, reconciling the tool catalog against S1-16.
**Status:** accepted — minor `next`-chain refinement; criteria unchanged.

The cc-prompt catalog's literal `next` values leave **`topsort` orphaned**: it is
a non-entry-point tool, yet no other tool's `next` names it, which violates
S1-16 ("every non-entry-point tool is named in at least one other tool's
`next`"). The cc-prompt explicitly invites refining the chains ("refine as
needed"). Minimal fix: add `topsort` to `learning_path`'s `next`
(`[get_node, prerequisites, topsort]`) — a natural progression from a single
concept's path to the whole-graph ordering. All other catalog `next` values are
unchanged. Verified by the `next-chains-name-existing-tools` test (no dangling
names, no orphans).

## Notes

- Test names above are suggested; CC may adjust naming if the test structure
  warrants it, but the criterion each test satisfies must be clear.
- S1-17 may be a single test that iterates all 8 tool names, or 8 individual
  tests — either is acceptable as long as all 8 are covered.
- S1-16 is verified by code inspection and grep, not a unit test. CC should
  document the `next` chain graph in the closing report.
