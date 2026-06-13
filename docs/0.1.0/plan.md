# graffeo-mcp 0.1.0 — Project Plan

**Date:** 2026-06-12
**Status:** Planning
**Architecture:** [docs/architecture.md](../architecture.md)

---

## Goal

Deliver an LFE/OTP MCP server that exposes 23 tools over a Mnesia-backed
Erlang knowledge graph (1,664 concept cards, ~3,061 vertices, ~14,341 edges),
serving as the first consumer and integration test for erlmcp 0.6.0, and
producing material for a 3-part LFE blog series.

## Arc overview

| Arc | Capability | Blog post | Slices |
|-----|-----------|-----------|--------|
| [01-foundation](arc01-foundation/arc-plan.md) | OTP app + Mnesia graph + ingest + meta tools + stdio | Post 1: Clear Thinking | 2 |
| [02-core-tools](arc02-core-tools/arc-plan.md) | Navigation, learning, path, source tools + discoverability | Post 2: Writing for Discoverability | 3 |
| [03-advanced-demo](arc03-advanced-demo/arc-plan.md) | Analysis tools + HTTP streaming + QA sessions + polish | Post 3: Demonstration | 2 |

**Total: 3 arcs, 7 slices.**

## Dependencies

```
Arc 1 ──► Arc 2 ──► Arc 3
  │                    │
  │                    ▼
  │              Blog Post 3 (QA transcripts)
  │
  ▼
Blog Post 1 can be drafted in parallel with Arc 1 implementation
Blog Post 2 drafting begins during Arc 2, Slice 3 (discoverability iteration)
```

Arc 1 is the critical path — nothing else can start until there is a running
server with a populated graph. Arc 2 is the bulk of the tool work. Arc 3 is
the demonstration and polish layer.

## External dependencies

- **erlmcp 0.6.0** on `release/0.6.x` — ready and waiting for release. Any
  bugs found during graffeo-mcp development feed back into erlmcp before the
  0.6.0 tag.
- **graffeo 0.3.x** — `graffeo_mnesia` backend, algorithms, `graffeo_backend`
  behaviour. Assumed stable.
- **Concept cards** — 1,664 cards in `billosys/ai-engineering`. Fetched via
  `make fetch-cards` into `priv/concept-cards/`.

## Known erlmcp gap

`returns` and `summary` are not projected into `_meta` by
`erlmcp_server_session:disc_meta/1`. Feed this back as a DISC-1 gap. Does not
block graffeo-mcp — the keys are stored in the tool spec and available to the
directory tool, just not in `tools/list` responses.

## Iteration budget

5 iterations per slice (per collaboration framework). If a slice needs more,
it was too large or under-specified — split it.
