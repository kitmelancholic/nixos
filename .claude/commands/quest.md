---
description: Run one quest from docs/tasks.md (`/quest next`, `/quest c1q07`, `/quest retry c1q07`)
---
Run exactly one quest, then stop. Argument: $ARGUMENTS

1. Read `CLAUDE.md` and the last 20 lines of `docs/progress.md`.
   - If the last entry is `хід майстра` or `провалений кидок` and the
     argument is not `retry <id>`, print that entry and stop.
2. Pick the quest: `next` = the first quest in `docs/tasks.md` with no
   `виконано` entry in `docs/progress.md`; otherwise the given ID.
3. Read **only** that quest's section of `docs/tasks.md` (from its `## <id>`
   heading to the next `## `), plus the files it lists under *Read first*.
   Do not read other quests or explore beyond what the section names.
   For `retry`, also read the quest's last `провалений кидок` entry and the
   decision the GM appended under it.
4. Check *Preconditions*. If one fails or its outcome is not covered by the
   section, append `## <id> — провалений кидок` (max 5 lines: what, why,
   what you need from the GM), commit only `docs/progress.md` as
   `chore(<id>): провалений кидок`, stop.
5. Do *Steps*. Loop: edit → `nix fmt` → `scripts/check --fast` → fix. Respect *Do not*.
   Line numbers in the section are hints; re-locate code with grep.
   Stage new files with `git add` before any check (flakes ignore untracked
   files). Never `git commit -a`, `git clean`, `reset --hard`, `checkout .`.
6. Run `scripts/quest-verify <id>`. If it fails, fix and rerun. If it fails
   twice in a row: revert only the quest's paths, append `провалений кидок`,
   stop.
7. If the quest's `meta:` line says `boss=yes`: start a reviewer subagent on
   Opus (model `opus`) with the quest section and `git diff --staged`; ask it for concrete
   defects only. Fix what it finds, rerun step 6.
8. Update `CLAUDE.md` if the section's *CLAUDE.md* item says so.
9. Commit on branch `redesign` with the Conventional Commits subject from
   *Commit*, listing the changed derivations from the verify output in the
   body, plus a `BREAKING CHANGE:` line if the subject has `!`. Append to
   `docs/progress.md` in the same commit:
   - `## <id> — хід майстра` + the section's *GM's turn* checklist with exact
     commands, if it has one;
   - otherwise `## <id> — виконано` (max 5 lines).
10. If the quest ends an act (`rest=<tag>` in the meta line): run the Opus
    reviewer on `git diff <previous rest tag>..HEAD` (skip for `c1r0`, which
    has no previous tag), put its findings and the long-rest steps in a
    `хід майстра` entry, tag the commit with `<tag>` and with the version
    from `scripts/next-version` (`c1r3`: `v1.0.0`), stop.

Never print full build logs (tail -n 40 or grep errors). Never push.
Never edit `docs/tasks.md`. Before committing, check the branch is
`redesign`; if not, append `провалений кидок` and stop.
