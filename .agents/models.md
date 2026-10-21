# Models per tier

`scripts/agent` reads this table (the quest's `meta:` line names the tier);
`scripts/context-watch` reads the context columns. `warn` and `hard` are the
context sizes (tokens) at which the hook tells the agent to stop exploring
and to finish or hand the quest back; `compact` caps the CLI's automatic
compaction just above `hard`, so a quest is handed back before it is
summarized. Reasons: `docs/design.md` §12.

| tier   | claude            | codex         | warn   | hard   | compact |
|--------|-------------------|---------------|--------|--------|---------|
| squire | claude-haiku-5-5  | gpt-5.6-luna  | 80000  | 95000  | 100000  |
| hero   | claude-sonnet-5-5 | gpt-5.6-terra | 120000 | 160000 | 180000  |
| cleric | claude-opus-5-5   | gpt-5.6-sol   | 160000 | 220000 | 240000  |
| judge  | claude-opus-5-5   | gpt-5.6-sol   | -      | -      | 240000  |
