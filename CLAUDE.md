# dangoNix

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
