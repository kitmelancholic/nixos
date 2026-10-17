# dangoNix

Rules for every coding agent in this repo (Claude Code reads them through
`CLAUDE.md`, Codex reads this file directly). Both agents follow the same
workflow and can continue each other's quests.

## Quests

- Quests: `/quest next|<id>|retry <id>` in Claude Code, `$quest …` in Codex;
  the one procedure is `.agents/skills/quest/SKILL.md`.
- The shared memory is the repo: `docs/tasks.md` (plan), `docs/progress.md`
  (journal; every entry names the agent and model), git history. Keep no
  state anywhere else.
- Models per tier (the quest's `meta:` line names the tier and effort):

  | tier   | claude            | codex          |
  |--------|-------------------|----------------|
  | hero   | claude-sonnet-5-5 | gpt-6.1-sol    |
  | cleric | claude-opus-5-5   | gpt-6.1-sol    |
  | judge  | claude-opus-5-5   | gpt-6.1-sol    |

  `scripts/agent` reads this table; change models only here, between
  campaigns.

## Build output

- Never print full build logs. Pipe them through `tail -n 40`, or grep for
  errors (`grep -iE 'error|failed|warning'`).
- While editing, run only the fast check: `scripts/check --fast` (doc and
  commit lint, shellcheck, evaluation only; from quest c1q13, `dangonix check --fast`).
- Run the full check once per quest, at the end: `scripts/quest-verify <id>`
  (runs `scripts/check`, then the oracle).

## Git

- Commit and tag only on branch `redesign`; never push.
- Commit subjects follow Conventional Commits: `<type>(<quest id>)[!]: …`
  (types and `!` per quest in `docs/tasks.md`); `!` needs a
  `BREAKING CHANGE:` line in the body.
- Versions are SemVer git tags `vX.Y.Z`, set only at a long rest from
  `scripts/next-version`.
