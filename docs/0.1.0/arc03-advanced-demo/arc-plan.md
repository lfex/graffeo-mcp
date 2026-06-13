# Arc 03: Advanced Tools + Demonstration

**Delivers:** 8 advanced tools (structural analysis + remaining path/source
tools), HTTP streaming transport for Codex, QA session transcripts, and
response polish. The complete 23-tool surface.

**Blog post:** Post 3 — "Demonstration / Proof of Benefits." Real QA sessions
with Claude Desktop (stdio) and Codex (HTTP streaming). The focus is the
difference good discoverability makes — showing the complete system in action.

---

## Slices

### Slice 01: Analysis + Remaining Tools

**Delivers:** 8 tools completing the 23-tool catalog.

**Tools (analysis — 6):**

| Tool | Key args |
|------|----------|
| `centrality` | `limit?` |
| `bridges` | `limit?` |
| `components` | — |
| `strong_components` | — |
| `condensation` | — |
| `feedback_arc_set` | — |

**Tools (paths — 1):**

| Tool | Key args |
|------|----------|
| `dominators` | `root`, `target?` |

**Tools (sources — 1):**

| Tool | Key args |
|------|----------|
| `bridge_categories` | `category_a`, `category_b`, `limit?` |

**Key work:**
- `centrality` computes degree centrality (in-degree + out-degree); graffeo
  provides `graffeo:in_degree/2` and `graffeo:out_degree/2`
- `bridges` finds articulation-point-like concepts using
  `graffeo:bridges/1` or connectivity analysis
- `components` / `strong_components` use `graffeo:components/1` /
  `graffeo:strong_components/1`
- `condensation` uses `graffeo:condensation/1` — collapses SCCs into a DAG
- `feedback_arc_set` uses `graffeo:feedback_arc_set/1` — minimum edges to
  break all cycles
- `dominators` uses `graffeo:dominators/2`
- `bridge_categories` queries source vertices across two categories
- All tools carry full discoverability metadata; analysis tools share
  `category => <<"analysis">>` and form their own `next` sub-chain
- Tier/category filtering on `centrality`, `bridges`, `bridge_categories`

**Acceptance (high-level):**
- All 23 tools callable
- `centrality` returns the most-connected concepts (expect `<<"gen-server">>`,
  `<<"supervisor">>` near the top)
- `strong_components` finds circular dependency groups (if any exist in the
  concept graph)
- `condensation` returns a DAG (acyclic by definition)
- `feedback_arc_set` returns edges whose removal breaks all cycles

---

### Slice 02: HTTP Streaming + QA + Polish

**Delivers:** HTTP streaming transport (Codex-compatible), polished response
formatting, tuned error messages, QA session transcripts, and any erlmcp bug
fixes fed back to the release.

**Key work:**

**HTTP streaming:**
- Configure Cowboy via erlmcp's HTTP transport (the server-side is erlmcp's
  responsibility; graffeo-mcp provides config)
- Test with Codex (or equivalent HTTP-streaming MCP client)
- Verify: tool calls work identically over both transports

**Response polish:**
- Review formatting of all 23 tools' output for LLM readability
- Error messages that help LLMs recover: "Concept 'foo' not found. Try
  `status` to see available concepts, or check the spelling."
- Structured content where useful (JSON alongside text for tools that return
  tabular data)

**Instructions tuning:**
- Final pass on the auto-generated instructions string
- Decision: keep auto-generated or replace with hand-crafted
- Document the decision and rationale for Post 2/3

**QA sessions:**
- Run full QA sessions with Claude Desktop (stdio) — record transcripts
- Run full QA sessions with Codex (HTTP) — record transcripts
- Focus questions:
  - "Teach me about OTP supervision from scratch"
  - "Compare gen_server and gen_statem"
  - "What are the most important Erlang concepts to learn first?"
  - "Find cycles in the knowledge graph and explain what they mean"
  - "What concepts bridge concurrency and error handling?"
- Capture: tool call sequences, which tools the LLM chose and why, where
  discoverability succeeded or failed

**erlmcp feedback:**
- File any bugs found during QA
- Document workarounds applied
- The `returns`/`summary` _meta gap is the known issue; check whether others
  surface

**Acceptance (high-level):**
- HTTP streaming transport works with at least one client
- QA sessions produce substantive transcripts showing the tool surface in
  action
- Error messages on invalid tool calls help the LLM self-correct
- All erlmcp bugs found are filed or fixed
- Blog Post 3 material is captured (transcripts, observations, before/after)

---

## Arc-level acceptance

The arc is done when:
1. All 23 tools are implemented, tested, and callable over both transports
2. QA sessions demonstrate effective tool discovery and use
3. erlmcp bugs found during development are filed and (where possible) fixed
4. Blog Post 3 material is captured
5. The graffeo-mcp 0.1.0 release is ready to tag
