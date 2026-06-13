# Slice 01: OTP Skeleton + Mnesia Graph + Ingest Pipeline

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| F-1 | `rebar.config` declares deps: `lfe`, `graffeo`, `erlmcp`; plugins: `rebar3_lfe` | `grep -c 'lfe\|graffeo\|erlmcp\|rebar3_lfe' rebar.config` returns ≥4 | serious | arch §2 | done | 7e693bd — count: 8 | |
| F-2 | `graffeomcp.app.src` lists `kernel, stdlib, mnesia, graffeo, erlmcp` in `applications` | `grep 'applications' src/graffeomcp.app.src` shows all five | serious | arch §3.1 | done | 7e693bd — `{applications, [kernel, stdlib, mnesia, graffeo, erlmcp]}` | |
| F-3 | `rebar3 compile` succeeds with zero warnings | `rebar3 compile 2>&1 \| grep -c 'Warning'` returns 0 | serious | CLAUDE.md | done | 7e693bd — count: 0 | lfe/cl.lfe `car`/`cdr` redefinition warnings are from LFE stdlib, not our code |
| F-4 | `Makefile` has `fetch-cards` target that populates `priv/concept-cards/` | `grep 'fetch-cards' Makefile` | correctness | arch §8 | done | 7e693bd — target present with shallow-clone + copy logic | |
| F-5 | `graffeo-mcp-app` exports `start/2` and `stop/1` | `grep -A2 'export' src/graffeo-mcp-app.lfe` shows both | serious | arch §3.1 | done | 7e693bd — `(export (start 2) (stop 1))` | |
| F-6 | `graffeo-mcp-sup` uses `one_for_one` strategy | `grep 'one_for_one' src/graffeo-mcp-sup.lfe` | serious | arch §3.2 | done | 7e693bd — `(map 'strategy 'one_for_one ...)` | |
| F-7 | `graffeo-mcp-graph` is listed as a child spec in `graffeo-mcp-sup` | `grep 'graffeo-mcp-graph' src/graffeo-mcp-sup.lfe` | serious | arch §3.2 | done | 7e693bd — child spec with `'id 'graffeo-mcp-graph` and `'restart 'permanent` | |
| F-8 | `graffeo-mcp-graph` calls `graffeo_mnesia:open` on init | `grep 'graffeo_mnesia' src/graffeo-mcp-graph.lfe` | serious | arch §3.4 | done | 7e693bd — `(graffeo_mnesia:open "erlang_concepts" ...)` in `init/1` | |
| F-9 | Graph handle stored via `persistent_term:put` after init | `grep 'persistent_term' src/graffeo-mcp-graph.lfe` | serious | arch §3.4 | done | 7e693bd — `(persistent_term:put (tuple 'graffeo_mcp 'graph) graph)` | |
| F-10 | `graffeo-mcp-parser:parse-file/1` returns `#(ok Card)` with all required fields | `rebar3 eunit --module=graffeo-mcp-parser-tests` passes | serious | arch §5.1 | done | 7e693bd — `parse_file_ok_test` passes, asserts all 6 required fields + lists | |
| F-11 | `graffeo-mcp-parser:parse-file/1` returns `#(error _)` for malformed input | `rebar3 eunit --module=graffeo-mcp-parser-tests` includes error case | correctness | arch §5.1 | done | 7e693bd — `parse_string_no_frontmatter_test` and `parse_string_missing_required_field_test` both pass | |
| F-12 | `graffeo-mcp-ingest:build/2` populates a Mnesia graph from parsed cards | `rebar3 eunit --module=graffeo-mcp-ingest-tests` passes | serious | arch §5.3 | done | 7e693bd — all 7 ingest tests pass including vertex/edge counts | |
| F-13 | Ingest creates source vertices as `{SourceSlug, ConceptSlug}` tuples | Test asserts `is_tuple` on source-layer vertices | serious | arch §5.2 | done | 7e693bd — `source_vertices_are_tuples_test` passes, asserts 4 tuple vertices | |
| F-14 | Ingest creates abstract vertices as bare binary slugs | Test asserts `is_binary` on abstract-layer vertices | serious | arch §5.2 | done | 7e693bd — `abstract_vertices_are_binaries_test` passes, asserts 3 binary vertices | |
| F-15 | Ingest creates membership edges from source to abstract vertices | Test asserts edge exists from `{Src, Slug}` to `Slug` | serious | arch §5.2 | done | 7e693bd — `membership_edges_connect_source_to_abstract_test` passes, weight 0.5 confirmed | |
| F-16 | Edges carry weight metadata per architecture doc | Test asserts prerequisite edge has `weight => 1.0`, related has `weight => 2.0` | correctness | arch §5.5 | done | 7e693bd — `edge_weights_match_spec_test` passes; also typed-edge label test passes | |
| F-17 | Full ingest of 1,664 cards produces ≥3000 vertices | Integration test: `graffeo:no_vertices/1 >= 3000` | serious | arch §1 | deferred | | Blocked on `make fetch-cards` to populate priv/concept-cards/. Re-entry: run after fetch-cards in CI or manually. |
| F-18 | Full ingest of 1,664 cards produces ≥14000 edges | Integration test: `graffeo:no_edges/1 >= 14000` | serious | arch §1 | deferred | | Same as F-17. |
| F-19 | `rebar3 eunit` passes (all parser + ingest + graph tests) | `rebar3 eunit` exits 0 | serious | CLAUDE.md | done | 7e693bd — all 13 tests pass: parser(3) + ingest(7) + graph(3) | |

## What Worked

- **Direct Mnesia calls in ingest** — calling `graffeo_mnesia:add_vertex/3` and
  `graffeo_mnesia:add_edge/4` directly (instead of through the `graffeo` facade)
  made the mutation-vs-functional distinction explicit and avoided confusion about
  return types. The facade `graffeo:edge_meta/3` was still used for reads (polymorphic).

- **Rewriting phase 5 without filter_edges/contract** — the Mnesia backend
  explicitly does not support constructive ops. Iterating cards directly to add
  abstract-to-abstract edges turned out simpler than the projection approach,
  and produces the same graph topology.

- **ltest as test-profile dep** — `(behaviour ltest-unit)` + `deftest` macros
  gave idiomatic LFE tests with no awkward underscore hacks. Adding
  `eunit_tests` to rebar.config's test profile made `rebar3 eunit` (no flags)
  discover all three test modules.

- **`try ... (after ...)` for Mnesia cleanup in ingest tests** — ensures
  `graffeo_mnesia:delete` runs even when an assertion fails, preventing
  table leaks between test runs.

## Closure

Closed at commit 7e693bd on 2026-06-12. Total rows: 19. Done: 17. Deferred: 2 (F-17, F-18 — blocked on card corpus). No-op: 0.

F-17 and F-18 re-enter at arc02 or whenever `make fetch-cards` is run.
