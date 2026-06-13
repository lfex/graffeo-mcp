# Slice 01: OTP Skeleton + Mnesia Graph + Ingest Pipeline

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| F-1 | `rebar.config` declares deps: `lfe`, `graffeo`, `erlmcp`; plugins: `rebar3_lfe` | `grep -c 'lfe\|graffeo\|erlmcp\|rebar3_lfe' rebar.config` returns ≥4 | serious | arch §2 | open | | |
| F-2 | `graffeomcp.app.src` lists `kernel, stdlib, mnesia, graffeo, erlmcp` in `applications` | `grep 'applications' src/graffeomcp.app.src` shows all five | serious | arch §3.1 | open | | |
| F-3 | `rebar3 compile` succeeds with zero warnings | `rebar3 compile 2>&1 \| grep -c 'Warning'` returns 0 | serious | CLAUDE.md | open | | |
| F-4 | `Makefile` has `fetch-cards` target that populates `priv/concept-cards/` | `grep 'fetch-cards' Makefile` | correctness | arch §8 | open | | |
| F-5 | `graffeo-mcp-app` exports `start/2` and `stop/1` | `grep -A2 'export' src/graffeo-mcp-app.lfe` shows both | serious | arch §3.1 | open | | |
| F-6 | `graffeo-mcp-sup` uses `one_for_one` strategy | `grep 'one_for_one' src/graffeo-mcp-sup.lfe` | serious | arch §3.2 | open | | |
| F-7 | `graffeo-mcp-graph` is listed as a child spec in `graffeo-mcp-sup` | `grep 'graffeo-mcp-graph' src/graffeo-mcp-sup.lfe` | serious | arch §3.2 | open | | |
| F-8 | `graffeo-mcp-graph` calls `graffeo_mnesia:open` on init | `grep 'graffeo_mnesia' src/graffeo-mcp-graph.lfe` | serious | arch §3.4 | open | | |
| F-9 | Graph handle stored via `persistent_term:put` after init | `grep 'persistent_term' src/graffeo-mcp-graph.lfe` | serious | arch §3.4 | open | | |
| F-10 | `graffeo-mcp-parser:parse-file/1` returns `#(ok Card)` with all required fields | `rebar3 eunit --module=graffeo-mcp-parser-tests` passes | serious | arch §5.1 | open | | |
| F-11 | `graffeo-mcp-parser:parse-file/1` returns `#(error _)` for malformed input | `rebar3 eunit --module=graffeo-mcp-parser-tests` includes error case | correctness | arch §5.1 | open | | |
| F-12 | `graffeo-mcp-ingest:build/2` populates a Mnesia graph from parsed cards | `rebar3 eunit --module=graffeo-mcp-ingest-tests` passes | serious | arch §5.3 | open | | |
| F-13 | Ingest creates source vertices as `{SourceSlug, ConceptSlug}` tuples | Test asserts `is_tuple` on source-layer vertices | serious | arch §5.2 | open | | |
| F-14 | Ingest creates abstract vertices as bare binary slugs | Test asserts `is_binary` on abstract-layer vertices | serious | arch §5.2 | open | | |
| F-15 | Ingest creates membership edges from source to abstract vertices | Test asserts edge exists from `{Src, Slug}` to `Slug` | serious | arch §5.2 | open | | |
| F-16 | Edges carry weight metadata per architecture doc | Test asserts prerequisite edge has `weight => 1.0`, related has `weight => 2.0` | correctness | arch §5.5 | open | | |
| F-17 | Full ingest of 1,664 cards produces ≥3000 vertices | Integration test: `graffeo:no_vertices/1 >= 3000` | serious | arch §1 | open | | |
| F-18 | Full ingest of 1,664 cards produces ≥14000 edges | Integration test: `graffeo:no_edges/1 >= 14000` | serious | arch §1 | open | | |
| F-19 | `rebar3 eunit` passes (all parser + ingest + graph tests) | `rebar3 eunit` exits 0 | serious | CLAUDE.md | open | | |

## What Worked

_(Filled in at slice close.)_

## Closure

_(Filled in at slice close.)_
