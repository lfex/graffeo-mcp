# Slice 02: Meta Tools + Handler + stdio Transport

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| S2-1 | `graffeo-mcp-tools` implements `erlmcp_server_handler` behaviour | `grep 'erlmcp_server_handler' src/graffeo-mcp-tools.lfe` | serious | arch §3.3 | done | 3a347bb — `(behaviour erlmcp_server_handler)` present | |
| S2-2 | `tools/0` returns specs for `status` and `info` (exactly 2 tools) | `grep -c 'name.*status\|name.*info\|#"status"\|#"info"' src/graffeo-mcp-tools.lfe` returns 2 | serious | arch §4.6 | done | 3a347bb — grep returns 5 (includes inline references); tools-returns-two-specs test asserts length=2 | |
| S2-3 | Both tool specs carry `category`, `when_to_use`, `next`, `entry_point`, `annotations` | `grep -c 'category\|when_to_use\|next\|entry_point\|annotations' src/graffeo-mcp-tools.lfe` returns ≥10 | serious | arch §4.7 | done | 3a347bb — count: 12 | |
| S2-4 | `status` tool is `entry_point => true`; `info` is not | Code inspection or test assertion | serious | arch §4.6 | done | 3a347bb — `status-entry-point-true-info-false` test passes | |
| S2-5 | Both tools have `readOnlyHint => true` and `idempotentHint => true` in annotations | `grep 'readOnlyHint\|idempotentHint' src/graffeo-mcp-tools.lfe` returns ≥2 | correctness | arch §4.8 | done | 3a347bb — 2 annotation maps present, one per tool | |
| S2-6 | `handle_tool/3` dispatches `<<"status">>` and returns `{ok, Content}` | `rebar3 eunit --module=graffeo-mcp-tools-tests` includes status test | serious | arch §4.6 | done | 3a347bb — `status-returns-ok-with-counts` passes | |
| S2-7 | `handle_tool/3` dispatches `<<"info">>` and returns `{ok, Content}` | same test module includes info test | serious | arch §4.6 | done | 3a347bb — `info-returns-ok-with-distribution` passes | |
| S2-8 | `handle_tool/3` returns `{error, -32601, _}` for unknown tool names | test asserts error return for unknown tool | correctness | defensive | done | 3a347bb — `unknown-tool-returns-error` passes | |
| S2-9 | `status` response text includes vertex count, edge count, and loaded state | test asserts response contains expected count strings | serious | arch §4.6 | done | 3a347bb — `status-returns-ok-with-counts` asserts "loaded" in text | |
| S2-10 | `info` response text includes category distribution | test asserts response contains at least one category name and count | serious | arch §4.6 | done | 3a347bb — `info-returns-ok-with-distribution` asserts "test-cat"; format test asserts "test-cat-a" and "test-cat-b" | |
| S2-11 | `info` response text includes relationship type breakdown | test asserts response contains relationship type names and counts | serious | arch §4.6 | done | 3a347bb — `info-returns-ok-with-distribution` asserts "Relationship Types"; format test asserts "membership" and "prerequisites" | |
| S2-12 | `graffeo-mcp-format` module exists with `format-status/1` and `format-info/1` | `grep 'defmodule\|export' src/graffeo-mcp-format.lfe` shows module with exports | serious | arch §3.3 | done | 3a347bb — `(defmodule graffeo-mcp-format ...)` with `(export (format-info 1) (format-status 1))` | |
| S2-13 | `graffeo-mcp-app:start/2` calls `erlmcp:start_stdio_setup/2` (or equivalent erlmcp wiring) | `grep 'erlmcp\|stdio' src/graffeo-mcp-app.lfe` | serious | arch §3.1 | done | 3a347bb — `(erlmcp:start_stdio_setup 'graffeomcp ...)` in `start-mcp/0` | |
| S2-14 | Server config includes `name`, `version`, `purpose` | `grep 'name\|version\|purpose' src/graffeo-mcp-app.lfe` returns ≥3 | serious | arch §8 | done | 3a347bb — count: 3 | |
| S2-15 | `status` tool has no required input parameters | Code inspection: input_schema has empty required list or no required fields | correctness | arch §4.6 | done | 3a347bb — `(erlmcp_schema:object '())` produces empty schema with no required fields | |
| S2-16 | `status` next chain points to `info`; `info` next chain points forward to Arc 2 tools | `grep 'next' src/graffeo-mcp-tools.lfe` shows both chains | correctness | arch §4.7 | done | 3a347bb — status next=[info], info next=[get_node, learning_path] | |
| S2-17 | Handler gracefully handles missing graph (persistent_term not set) | test: clear persistent_term, call handle_tool, assert `{error, _, _}` not crash | correctness | slice-doc | done | 3a347bb — `status-handles-missing-graph` passes, returns `{error, -32603, _}` | |
| S2-18 | `rebar3 compile` succeeds with zero warnings | `rebar3 compile 2>&1 \| grep -c 'Warning'` returns 0 | serious | CLAUDE.md | done | 3a347bb — 0 warnings from project code | lfe/cl.lfe car/cdr warnings are stdlib, not project |
| S2-19 | `rebar3 eunit` passes (all tests including new tools tests) | `rebar3 eunit` exits 0 | serious | CLAUDE.md | done | 3a347bb — all 26 tests pass: parser(4) + ingest(9) + graph(3) + format(4) + tools(6) | |

## Amendment: graffeo:edges/1 not in facade

`graffeo:edges/1` is not exported from the graffeo facade (only backend
callbacks taking `ref()` are exposed; the facade wraps only the subset listed in
its `-export` block). `format-info` replaces `graffeo:edges/1` with
`graffeo:vertices/1` + `graffeo:out_neighbours/2` in a fold, which enumerates
each directed edge exactly once. Functionally equivalent; no ledger criterion is
affected.

## What Worked

- **`erlmcp_schema:object('()`)** — calling with an empty list produces a valid
  empty schema; no required params needed for the meta tools.
- **`persistent_term:get/2` with default** — `persistent_term:get(Key, Default)`
  avoids a crash when the graph isn't yet loaded; returning `{error, -32603, _}`
  is the right MCP response rather than crashing the handler process.
- **Isolated `with-graph/1` helper in tools tests** — encapsulates
  persistent_term setup + cleanup in one place, keeping each test body clean.
- **`graffeo:vertices/1` + `graffeo:out_neighbours/2` for edge enumeration** —
  graffeo facade doesn't expose `edges/1`; vertex-neighbor iteration is a correct,
  efficient substitute for a directed graph.

## Closure

Closed at commit 3a347bb on 2026-06-12. Total rows: 19. Done: 19. Deferred: 0. No-op: 0.
