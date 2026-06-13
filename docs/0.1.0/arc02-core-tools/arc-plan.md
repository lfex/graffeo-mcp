# Arc 02: Core Tools + Discoverability

**Delivers:** 13 core tools across four categories (navigation, learning,
paths, sources), tier/category filtering on list-returning tools, full
discoverability metadata, and an iterated discoverability pass driven by LLM
exercises.

**Blog post:** Post 2 — "Writing for Discoverability." The arc's final slice
(discoverability iteration) IS the blog post content — running LLM exercises,
discovering what works and what doesn't in tool descriptions and `when_to_use`
text, refining `next` chains, and capturing the meta-cognitive analysis.

---

## Slices

### Slice 01: Navigation + Learning Tools

**Delivers:** 8 tools that let an LLM explore the knowledge graph and find
learning paths.

**Tools (navigation — 4):**

| Tool | Key args |
|------|----------|
| `get_node` ★ | `id` (required) |
| `get_node_edges` | `id`, `direction?` |
| `related` | `id`, `relationship?`, `limit?` |
| `neighborhood` | `id`, `radius?`, `relationship?` |

**Tools (learning — 4):**

| Tool | Key args |
|------|----------|
| `prerequisites` | `id` |
| `dependents` | `id`, `depth?` |
| `learning_path` ★ | `id` |
| `topsort` | `root?` |

**Key work:**
- Each tool: input schema via `erlmcp_schema`, handler clause in
  `graffeo-mcp-tools:handle_tool/3`, response formatting in
  `graffeo-mcp-format`
- `get_node` returns: concept name, category, tier, source, degree counts,
  vertex label
- `neighborhood` uses `graffeo:bfs/3` or equivalent to walk N hops
- `learning_path` uses topological sort over the prerequisite subgraph
- `topsort` uses `graffeo:topsort/1` (or subgraph variant)
- All tools: full discoverability metadata (category, when_to_use, returns,
  next, entry_point, annotations)

**Acceptance (high-level):**
- All 8 tools callable from Claude Desktop
- `get_node` on `<<"gen-server">>` returns meaningful concept data
- `learning_path` for a non-trivial concept returns ordered prerequisites
- `topsort` returns a valid topological ordering

---

### Slice 02: Path + Source Tools + Filtering

**Delivers:** 5 more tools covering weighted paths and provenance, plus
tier/category filtering on all list-returning tools.

**Tools (paths — 2):**

| Tool | Key args |
|------|----------|
| `shortest_path` ★ | `from`, `to`, `cost?` |
| `reachable` | `id` |

**Tools (sources — 3):**

| Tool | Key args |
|------|----------|
| `concept_sources` | `id` |
| `concept_variants` | `id` |
| `source_coverage` | `id` |

**Key work:**
- `shortest_path` uses `graffeo:dijkstra/4` with edge weights from the
  architecture doc (prerequisite=1.0, extends=1.0, related=2.0,
  contrasts_with=3.0, membership=0.5)
- Source tools query the two-layer model: source vertices `{SourceSlug,
  ConceptSlug}` linked to abstract vertices via membership edges
- **Tier/category filtering:** All tools that return lists of concepts accept
  optional `tier` and `category` args. Implemented as a post-query predicate
  over vertex labels — `fun(VertexId, Label) -> boolean()`.
- Filtering applies retroactively to Slice 01's tools too (related,
  neighborhood, prerequisites, dependents, etc.)

**Acceptance (high-level):**
- `shortest_path` from `<<"gen-server">>` to `<<"supervisor">>` returns a
  weighted path
- `concept_sources` returns source-specific variants with provenance
- Filtering: `related` with `tier=foundational` returns only foundational
  concepts
- All 13 tools (8 from Slice 01 + 5 new) are callable and carry discoverability
  metadata

---

### Slice 03: Discoverability Iteration

**Delivers:** Refined discoverability metadata across all 13 tools, based on
LLM exercises that reveal what works and what fails. This slice produces the
raw material for Blog Post 2.

**Key work:**
- Run structured LLM exercises against the tool surface:
  - "Find me a learning path for understanding supervision trees"
  - "What concepts bridge OTP behaviours and error handling?"
  - "How does gen_server relate to gen_statem?"
  - "What should I learn before tackling distributed Erlang?"
- Capture: which tools the LLM reaches for, which it misses, why
- Iterate on: `description` text, `when_to_use` phrasing, `next` chains,
  `entry_point` selection
- Test: does `erlmcp_instructions:generate/2` produce a good enough
  orientation string, or do we need a hand-crafted one?
- Document: before/after comparisons, failure modes, the taxonomy of
  discoverability mistakes

**This is not code-heavy — it is an analytical/editorial pass.** The output
is refined tool metadata and a set of observations that become Post 2's
content.

**Acceptance (high-level):**
- Every tool's `when_to_use` has been tested against at least one LLM exercise
- `next` chains form a connected, navigable graph (no dead ends, no orphans)
- Entry points (`status`, `get_node`, `learning_path`, `shortest_path`) are
  validated as effective starting points
- Instructions string (auto-generated or hand-crafted) orients a fresh LLM
  session effectively

---

## Arc-level acceptance

The arc is done when:
1. All 13 core tools are implemented, tested, and callable
2. Tier/category filtering works on all list-returning tools
3. Discoverability metadata has been iterated based on real LLM exercises
4. The tool surface is navigable: an LLM given only the instructions string
   and tool list can find its way to useful answers
5. Blog Post 2 material is captured (before/after, failure taxonomy, refined
   metadata)
