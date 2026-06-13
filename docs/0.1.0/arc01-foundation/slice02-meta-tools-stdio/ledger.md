# Slice 02: Meta Tools + Handler + stdio Transport

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| S2-1 | `graffeo-mcp-tools` implements `erlmcp_server_handler` behaviour | `grep 'erlmcp_server_handler' src/graffeo-mcp-tools.lfe` | serious | arch §3.3 | | | |
| S2-2 | `tools/0` returns specs for `status` and `info` (exactly 2 tools) | `grep -c 'name.*status\|name.*info' src/graffeo-mcp-tools.lfe` returns 2 | serious | arch §4.6 | | | |
| S2-3 | Both tool specs carry `category`, `when_to_use`, `next`, `entry_point`, `annotations` | `grep -c 'category\|when_to_use\|next\|entry_point\|annotations' src/graffeo-mcp-tools.lfe` returns ≥10 | serious | arch §4.7 | | | |
| S2-4 | `status` tool is `entry_point => true`; `info` is not | Code inspection or test assertion | serious | arch §4.6 | | | |
| S2-5 | Both tools have `readOnlyHint => true` and `idempotentHint => true` in annotations | `grep 'readOnlyHint\|idempotentHint' src/graffeo-mcp-tools.lfe` returns ≥2 | correctness | arch §4.8 | | | |
| S2-6 | `handle_tool/3` dispatches `<<"status">>` and returns `{ok, Content}` | `rebar3 eunit --module=graffeo-mcp-tools-tests` includes status test | serious | arch §4.6 | | | |
| S2-7 | `handle_tool/3` dispatches `<<"info">>` and returns `{ok, Content}` | same test module includes info test | serious | arch §4.6 | | | |
| S2-8 | `handle_tool/3` returns `{error, -32601, _}` for unknown tool names | test asserts error return for unknown tool | correctness | defensive | | | |
| S2-9 | `status` response text includes vertex count, edge count, and loaded state | test asserts response contains expected count strings | serious | arch §4.6 | | | |
| S2-10 | `info` response text includes category distribution | test asserts response contains at least one category name and count | serious | arch §4.6 | | | |
| S2-11 | `info` response text includes relationship type breakdown | test asserts response contains relationship type names and counts | serious | arch §4.6 | | | |
| S2-12 | `graffeo-mcp-format` module exists with `format-status/1` and `format-info/1` (or equivalent) | `grep 'defmodule\|export' src/graffeo-mcp-format.lfe` shows module with exports | serious | arch §3.3 | | | |
| S2-13 | `graffeo-mcp-app:start/2` calls `erlmcp:start_stdio_setup/2` (or equivalent erlmcp wiring) | `grep 'erlmcp\|stdio' src/graffeo-mcp-app.lfe` | serious | arch §3.1 | | | |
| S2-14 | Server config includes `name`, `version`, `purpose` | `grep 'name\|version\|purpose' src/graffeo-mcp-app.lfe` returns ≥3 | serious | arch §8 | | | |
| S2-15 | `status` tool has no required input parameters | Code inspection: input_schema has empty required list or no required fields | correctness | arch §4.6 | | | |
| S2-16 | `status` next chain points to `info`; `info` next chain points forward to Arc 2 tools | `grep 'next' src/graffeo-mcp-tools.lfe` shows both chains | correctness | arch §4.7 | | | |
| S2-17 | Handler gracefully handles missing graph (persistent_term not set) | test: clear persistent_term, call handle_tool, assert `{error, _, _}` not crash | correctness | slice-doc | | | |
| S2-18 | `rebar3 compile` succeeds with zero warnings | `rebar3 compile 2>&1 \| grep -c 'Warning'` returns 0 | serious | CLAUDE.md | | | |
| S2-19 | `rebar3 eunit` passes (all tests including new tools tests) | `rebar3 eunit` exits 0 | serious | CLAUDE.md | | | |
