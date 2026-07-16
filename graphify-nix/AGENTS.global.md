## Graphify-first workflow

Graphify is the primary index for understanding repositories and their content.
Use it before broad file discovery, recursive text search, or architecture guesses.

Mandatory session behavior:

- At the start of substantive repository work, check for
  `graphify-out/graph.json` from the project root.
- When the graph exists, the first codebase investigation command must be
  `graphify query "<the user's request>"`. Use `graphify explain "<concept>"`
  for a focused entity and `graphify path "<A>" "<B>"` for a relationship.
- Treat Graphify as the navigation and scoping layer. Inspect raw source after
  the query to verify exact implementation details before editing; graph output
  does not replace source-level verification.
- Do not skip Graphify because `graphify-out/` is dirty. Generated graph changes
  are normal. Skip only when the user explicitly opts out, the task is itself
  diagnosing stale/incorrect graph output, or no usable graph exists.
- Prefer `graphify-out/wiki/index.md` for broad navigation when it exists. Read
  `GRAPH_REPORT.md` only for broad architecture review or when scoped commands
  do not provide enough context.
- After modifying code or project documentation, run `graphify update .` from
  the project root before final verification. Report any update failure rather
  than silently leaving the graph stale.
- If no graph exists, continue normally. When the repository is substantial and
  Graphify is installed, recommend building one; do not create a costly graph
  unless the task or repository instructions authorize it.

Repository-local `AGENTS.md` files may add stricter Graphify requirements and
project-specific commands.
