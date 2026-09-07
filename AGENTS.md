# AGENTS.md — Nightshade

Persistent working instructions for agents in this repo.

## Codebase search: use `graphify`, not grep

This project keeps a knowledge graph at `graphify-out/` (see also `CLAUDE.md`).
It is far more efficient than raw `grep`/`rg` for navigating the code — a query
returns a scoped subgraph of related symbols with real file paths, instead of
thousands of raw hits.

Prefer `graphify` for any "where is X", "how do A and B relate", or "what
calls/uses this" question. Fall back to `rg` only for literal string/regex
searches (config values, error messages, TODOs) or when `graphify` doesn't
surface enough.

Commands (run from repo root; `graph.json` defaults to `graphify-out/graph.json`):

- `graphify query "<question>"` — BFS traversal for a question. Add `--budget N`
  to cap tokens, `--context <edge>` (e.g. `--context call`) to narrow.
- `graphify path "<A>" "<B>"` — shortest path / relationship between two nodes.
- `graphify explain "<concept>"` — focused plain-language explanation of a node + neighbors.
- `graphify affected "<X>"` — reverse traversal: what is impacted by X.
- Navigation: `graphify-out/wiki/index.md` for broad maps; `graphify-out/GRAPH_REPORT.md`
  only for full architecture review.

Keep the graph current after changing code:

- `graphify update .` — AST-only re-extract, no API cost. Run this after edits.

If `graphify-out/graph.json` is missing or stale, run `graphify update .` first.
