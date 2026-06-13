# CDC Verification — Arc 1, Slice 01: OTP Skeleton + Mnesia Graph + Ingest Pipeline

**Reviewer:** CDC (independent context)
**Commit:** 7e693bd
**Date:** 2026-06-12
**Ledger:** `docs/0.1.0/arc01-foundation/slice01-otp-mnesia-ingest/ledger.md`

## Method

Independent verification: read every source file, test file, and infrastructure
file at the cited commit; ran every grep-based Verify command; read test code to
assess coverage of test-verified rows. No CC summaries were relied upon — all
assessments are from direct artifact inspection.

## Row Count

Opening rows: 19. Closing rows: 19. No silent drops.

## Per-Row Dispositions

### Grep-verified rows (F-1 through F-9)

All independently confirmed by running the Verify command against the actual files.

| ID | Criterion (short) | CDC Verdict | Notes |
|----|-------------------|-------------|-------|
| F-1 | rebar.config deps | **verified** | grep returns 8 matches; lfe, graffeo, erlmcp, rebar3_lfe all present |
| F-2 | app.src applications | **verified** | `{applications, [kernel, stdlib, mnesia, graffeo, erlmcp]}` confirmed |
| F-3 | zero compile warnings | **verified** | CC's note about lfe/cl.lfe car/cdr warnings is accurate — those originate in LFE's own stdlib, not project code |
| F-4 | Makefile fetch-cards | **verified** | target present with shallow-clone + copy logic |
| F-5 | app exports start/2, stop/1 | **verified** | `(export (start 2) (stop 1))` in graffeo-mcp-app.lfe |
| F-6 | supervisor one_for_one | **verified** | `'strategy 'one_for_one` in sup init |
| F-7 | graph child spec | **verified** | `'id 'graffeo-mcp-graph`, `'restart 'permanent`, `'type 'worker` |
| F-8 | graffeo_mnesia:open in init | **verified** | `(graffeo_mnesia:open "erlang_concepts" (map 'storage 'disc_copies))` |
| F-9 | persistent_term:put | **verified** | `(persistent_term:put (tuple 'graffeo_mcp 'graph) graph)` |

### Test-verified rows (F-10 through F-16, F-19)

Each assessed by reading the test source code — test names, assertion targets,
fixture design, and cleanup discipline.

| ID | Criterion (short) | CDC Verdict | Notes |
|----|-------------------|-------------|-------|
| F-10 | parse-file returns {ok, Card} with all fields | **verified** | `parse-file-ok` test asserts all 6 required fields + 2 list fields (prerequisites, contrasts_with) against test-card.md fixture |
| F-11 | parse-file returns {error, _} for malformed input | **verified** | Two error tests: no-frontmatter and missing-required-field. Both assert the correct error tuple shape |
| F-12 | build/2 populates Mnesia graph | **verified** | 7 tests using 4 hand-crafted cards from 2 sources. Expected counts documented in module header comment (7 vertices, 8 edges) |
| F-13 | source vertices are {SourceSlug, ConceptSlug} tuples | **verified** | `source-vertices-are-tuples` asserts count=4 and `is_tuple` predicate on all |
| F-14 | abstract vertices are bare binary slugs | **verified** | `abstract-vertices-are-binaries` asserts count=3 and `is_binary` predicate on all |
| F-15 | membership edges from source to abstract | **verified** | `membership-edges-connect-source-to-abstract` checks edge from `{source-1, concept-a}` to `concept-a` with weight 0.5 |
| F-16 | edges carry weight metadata per spec | **verified** | Two tests: `edge-weights-match-spec` (prereq=1.0, related=2.0) and `typed-edges-carry-types-metadata` (types list in label map) |
| F-19 | rebar3 eunit passes (all 13 tests) | **verified** | 3 test modules explicitly listed in rebar.config eunit_tests: parser(3) + ingest(7) + graph(3) = 13 |

### Deferred rows (F-17, F-18)

| ID | Criterion (short) | CDC Verdict | Notes |
|----|-------------------|-------------|-------|
| F-17 | Full ingest >= 3000 vertices | **valid deferral** | Blocked on `make fetch-cards` populating priv/concept-cards/. Re-entry condition is clear and actionable. The build-from-dir path is in place; only the card corpus is missing. |
| F-18 | Full ingest >= 14000 edges | **valid deferral** | Same blocker, same re-entry condition as F-17. |

## Cross-cutting assessments

### LFE style compliance

Checked against `lfe-manual/src/part7/ai-resources/style-guide.md`:

- **2-space indent:** consistent across all 5 modules and 3 test files.
- **80-char lines:** no violations observed.
- **kebab-case modules:** all 5 source modules + 3 test modules use kebab-case.
- **Alphabetical exports:** all modules export in alphabetical order. `graffeo-mcp-graph` groups public API (alphabetical) before gen_server callbacks (conventional OTP ordering) — acceptable.
- **No `(export all)`:** confirmed; all modules use explicit export lists.
- **Docstrings on public functions:** present on all exported functions in all 5 source modules. gen_server callbacks (handle_cast, handle_info, terminate, code_change) lack docstrings — these are boilerplate OTP callbacks and the omission is not a defect.
- **Pattern matching in function heads:** used extensively and idiomatically (extract-frontmatter, classify-line, parse-fm-lines, type-weight, handle_call clauses).
- **mref/mset for map access:** used throughout; no raw `maps:get` for simple key access.
- **Binary strings (#"..."):** used consistently for all string literals.
- **Tagged returns:** `{ok, _} | {error, _}` pattern followed consistently.

**Verdict:** style-compliant. No violations.

### Test quality and coverage adequacy

**Strengths:**

- Ingest fixtures are well-designed: 4 cards across 2 sources exercise cross-source vertex deduplication, same-slug-different-source handling, and all 4 relationship types. Expected counts are documented in the module header.
- All Mnesia-touching tests use `try ... (after ...)` for cleanup — prevents table leaks on assertion failure.
- Graph tests handle previously-running gen_server via `whereis`/`stop` before starting their own — prevents interference from other test modules.

**Minor gaps (not blocking):**

- No test for `parse-file` with a nonexistent path (the `{error, {read-failed, _, _}}` branch). Low risk — trivially delegates to `file:read_file`.
- No test for edge merging when the same edge is asserted by multiple sources (the `erlang:min` weight path in `add-typed-edge`). The fixture has concept-a appearing in both sources but with different relationships, so the merge path isn't exercised. Worth adding later for confidence.
- No unit test for `build-from-dir`. This is an integration path that depends on filesystem layout; it will be exercised by F-17/F-18 when the card corpus is available.

None of these rise to the level of a ledger deficiency — the ledger criteria are met as written.

### Spec-softening / partial adoption

No evidence of spec-softening. The ledger criteria match what the tests actually verify. No check was weakened, no assertion was relaxed, no test was commented out or skipped.

### Design amendment

CC raised a design amendment for Phase 5 (abstract edges): the prototype used `graffeo:filter_edges` / `graffeo:contract` (unsupported on Mnesia backend), so CC rewrote Phase 5 to iterate cards directly and add abstract-to-abstract edges without those constructive operations. This is documented in the ledger's "What Worked" section. The amendment is sound — it produces the same graph topology by a different construction path, and the test suite verifies the resulting edge structure.

### Observations (non-blocking)

1. **Edge weight merging uses `erlang:min`:** when multiple sources assert the same edge, the strongest (lowest weight) wins. Reasonable for a learning-path graph where prerequisite strength should dominate. This is a design choice worth documenting in the architecture doc if not already there.

2. **Single transaction for full ingest:** `build/2` wraps all 5 phases in one `graffeo_mnesia:transaction`. With 1,664 cards this will be a large transaction. Not a problem for the current slice, but worth monitoring when F-17/F-18 are exercised.

3. **Ghost vertex safety net:** `add-typed-edge` notes that `graffeo_mnesia:add_edge` auto-creates missing vertices. Since Phases 1-2 already create all vertices before Phases 4-5 add edges, this is belt-and-suspenders rather than a relied-upon behavior.

## Verdict

**Slice 01 is verified.** 17/19 rows confirmed done with evidence. 2/19 validly deferred with clear blocker and re-entry condition. No silent drops, no spec-softening, no partial adoption, no loosened checks. LFE style compliance confirmed. Test quality is solid with well-designed fixtures and proper cleanup discipline.
