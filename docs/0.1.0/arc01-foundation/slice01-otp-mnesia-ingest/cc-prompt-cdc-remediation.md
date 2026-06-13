# CC Prompt — Slice 01 CDC Remediation

**Origin:** CDC verification of Arc 1, Slice 01 (commit 7e693bd)
**Scope:** test gaps and documentation items flagged by CDC review
**Iteration cap:** 2 (this is patch work, not a new slice)

## Context

CDC verified Slice 01 and passed it. Three test gaps and one documentation gap
were identified. These are quality-floor items — untested code paths and an
undocumented design decision. They MUST be addressed before starting Slice 02.

Read:
- `docs/0.1.0/arc01-foundation/slice01-otp-mnesia-ingest/cdc-verification.md`
  (the "Minor gaps" and "Observations" sections)
- `src/graffeo-mcp-ingest.lfe` lines 168–184 (the `add-typed-edge` function)
- `src/graffeo-mcp-parser.lfe` lines 8–13 (the `parse-file` error branch)
- `test/graffeo-mcp-ingest-tests.lfe` (existing fixture design)
- `test/graffeo-mcp-parser-tests.lfe` (existing error tests)

## Tasks

### R-1: MUST add test for parse-file read failure

`graffeo-mcp-parser:parse-file/1` has an `{error, {read-failed, Path, Reason}}`
branch (line 13) that is never tested. Add a test to
`graffeo-mcp-parser-tests.lfe`:

```
(deftest parse-file-nonexistent-returns-error
  "parse-file returns {error, {read-failed, _, _}} for a missing file."
  (case (graffeo-mcp-parser:parse-file "test/fixtures/no-such-file.md")
    ((tuple 'error (tuple 'read-failed _ _)) (is 'true))
    (other (is-equal (tuple 'error 'read-failed) other))))
```

Adapt the above to LFE style conventions; the exact form is illustrative. The
point is: exercise the `{error, {read-failed, _, _}}` return.

### R-2: MUST add test for edge merging (multi-source same edge)

The `add-typed-edge` function (ingest.lfe lines 168–184) has two branches: one
for a fresh edge, one for merging into an existing edge (takes `erlang:min` of
weights, `lists:usort` of types and asserted_by). The current fixture has
concept-a in both source-1 and source-2, but they don't share any relationship
targets, so the merge branch is never exercised.

Fix: extend the test fixtures so that two cards from different sources share a
relationship target, forcing the merge path. For example, add a prerequisite
from source-2's concept-a to concept-b (which source-1's concept-a already
declares as a prerequisite). Then add a test that verifies:

- The abstract edge from `concept-a` to `concept-b` has `weight => 1.0` (min of
  two prerequisite weights, both 1.0 — but the merge path was executed).
- The edge's `label => #{types => ..., asserted_by => ...}` has both sources in
  `asserted_by` (i.e., `lists:member(#"source-1", AssertedBy)` and
  `lists:member(#"source-2", AssertedBy)` are both true).

A stronger test: have source-2's concept-a declare concept-b as `related`
instead of `prerequisites`. Then the merged edge should have:
- `weight => 1.0` (min of prerequisite 1.0 and related 2.0)
- `types` containing both `prerequisites` and `related`
- `asserted_by` containing both `#"source-1"` and `#"source-2"`

This is the stronger version — it exercises weight minimization, type merging,
and multi-source attribution in one assertion. MUST use this version.

**Important:** when extending the fixture, update the expected counts in the
module header comment and in existing tests (vertex-counts, edge-counts) if the
new fixture card changes the totals. Do not break existing tests.

### R-3: MUST add test for build-from-dir

`graffeo-mcp-ingest:build-from-dir/2` (lines 39–52) is the entry point that the
gen_server actually calls, but it has no test. Add a test that:

1. Creates a temporary directory structure under `/tmp` (or uses an existing
   `test/fixtures/` subdirectory) with at least 2 `.md` card files in a
   subdirectory (build-from-dir expects `base-dir/*/%.md` — it wildcards one
   level of subdirectories).
2. Calls `build-from-dir` with that directory and a fresh Mnesia graph.
3. Asserts that the graph has the expected vertex count (> 0).
4. Cleans up via `graffeo_mnesia:delete` in `(after ...)`.

The simplest approach: create `test/fixtures/cards/test-source/` containing 2 small
card files, and call `build-from-dir` with `"test/fixtures/cards"` as the base
dir. The card files can be minimal — slug, concept, category, tier, source,
source_slug, and empty relationship lists.

### R-4: MUST document edge-weight merge strategy in architecture doc

The `erlang:min` merge strategy in `add-typed-edge` is a design decision: when
multiple sources assert the same abstract-to-abstract edge, the strongest
(lowest weight) wins. This is not documented anywhere except implicitly in the
code.

Add a short paragraph to `docs/architecture.md` in the section that discusses
edge weights (§5.5 or nearby). State:

- When the same abstract edge is asserted by multiple sources or relationship
  types, the edge is merged: weight takes `erlang:min` (strongest wins), types
  are unioned via `lists:usort`, and all asserting sources are recorded in
  `asserted_by`.
- Rationale: in a learning-path graph, the strongest relationship (lowest
  weight) should dominate path-finding, while the type union preserves the full
  semantic picture for tool consumers.

## Acceptance

| ID | Criterion | Verify |
|----|-----------|--------|
| R-1 | parse-file error branch tested | `rebar3 eunit --module=graffeo-mcp-parser-tests` passes with ≥4 tests |
| R-2 | Edge merge path tested with multi-source fixture | `rebar3 eunit --module=graffeo-mcp-ingest-tests` passes with ≥8 tests; new test asserts weight, types, and asserted_by |
| R-3 | build-from-dir tested | `rebar3 eunit --module=graffeo-mcp-ingest-tests` passes with ≥9 tests |
| R-4 | Merge strategy documented | `grep -c 'erlang:min\|merge\|asserted_by' docs/architecture.md` returns ≥2 |
| R-5 | All existing tests still pass | `rebar3 eunit` exits 0, total tests ≥ 16 |
| R-6 | Zero compile warnings | `rebar3 compile 2>&1 \| grep -c 'Warning'` returns 0 (excluding LFE stdlib) |

## Closing

Commit with message: `test+doc: CDC remediation — edge merge test, parse-file
error test, build-from-dir test, merge strategy docs`. Update the Slice 01
ledger "What Worked" section to note the CDC remediation round. No separate
ledger rows — this is a patch on an already-verified slice.
