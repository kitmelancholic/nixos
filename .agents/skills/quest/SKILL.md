---
name: quest
description: Run one quest from docs/tasks.md (`quest next`, `quest c1q07`, `quest retry c1q07`)
disable-model-invocation: true
---
Run exactly one quest, then stop. Argument: $ARGUMENTS (if this still reads
as a placeholder, the argument is the text after the skill name in the
request: `next`, `<id>` or `retry <id>`).

The same procedure runs in Claude Code (`/quest …`) and Codex (`$quest …`).
End every journal entry with the line `agent: <claude|codex> <model id>`:
the values of `$DANGONIX_AGENT` and `$DANGONIX_MODEL` when they are set
(`scripts/agent` sets them), else the model you run as, in full. The GM
answers an entry below that line; `scripts/campaign` then runs `retry`.

**Ask, don't describe.** When the only thing between you and `виконано` is
the quest itself (a path missing from *Files*, a guessed `leaves=` or other
`meta:` value, a precondition with one obvious fix, a file outside the
quest that fails a check) or a permission (a command or path the steps need
that is denied), and you know the exact change: write it as a patch and ask.
- Make the patch without changing the file: `cp <path> .campaign/<id>.new`,
  edit the copy, then `diff -u --label a/<path> --label b/<path> <path>
  .campaign/<id>.new >> .campaign/<id>.request.patch` (one file at a time,
  then delete the copy). `git apply --check --recount
  .campaign/<id>.request.patch` must pass. If those commands are denied,
  write the unified diff with the Write tool, three lines of context. A permission changes
  `.claude/settings.json` and `.codex/rules/dangonix.rules` together.
- In the `провалений кидок` entry, put `запит: scope - <why>` or
  `запит: permission - <why>` (one line) right above the `agent:` line.
- Keep the quest's own work uncommitted, as for any failure. The judge and
  the GM see the patch in `scripts/campaign`; on yes the campaign applies and
  commits it, and the `retry` runs on the quest's own tier.
Never use a request to skip or weaken a step, a *Do not* or a check.

1. Read `AGENTS.md` and the last 20 lines of `docs/progress.md`.
   - If the last entry is `хід майстра`, `провалений кидок` or `на суд`
     and the argument is not `retry <id>`, print that entry and stop.
   - Any agent may continue any quest: the journal, `docs/tasks.md` and git
     are the whole state. Uncommitted changes you did not make inside the
     quest's paths (its *Files* item) are a previous run's work: keep them.
     Outside those paths they are the GM's: leave them unstaged and
     untouched and carry on, unless they are `.nix` files, `flake.lock` or
     `state.json` (they change what the checks evaluate): then write
     `провалений кидок` listing them.
2. Pick the quest: `next` = the first quest in `docs/tasks.md` with no
   `виконано` entry in `docs/progress.md`; otherwise the given ID.
3. Read **only** that quest's section of `docs/tasks.md` (from its `## <id>`
   heading to the next `## `), the header's *Shared rules*, and the files it
   lists under *Read first*.
   Do not read other quests or explore beyond what the section names.
   For `retry`, also read the quest's last entry (`провалений кидок` or
   `на суд`) and what the GM or the judge appended under it. If `.campaign/<id>.diagnosis.md`
   exists, read it too: the squire's summary of the quest's previous attempt
   (its first wrong step, what it wasted). Do not repeat that; the section
   and the journal still decide.
4. Check *Preconditions*. If one fails or its outcome is not covered by the
   section, append `## <id> - провалений кидок` (max 5 lines: what, why,
   what you need from the GM, plus the `agent:` line), commit only
   `docs/progress.md` as `chore(<id>): провалений кидок`, stop.
5. Do *Steps*. Loop: edit → `nix fmt` → `scripts/check --fast` → fix. Respect *Do not*.
   Line numbers in the section are hints; re-locate code with grep.
   Stage new files with `git add` before any check (flakes ignore untracked
   files). Never `git commit -a`, `git clean`, `reset --hard`, `checkout .`.
   An outcome the section lists under *Stop if*: append `провалений кидок`
   as in step 4 with what it asks for, keep your work uncommitted, stop.
6. Run `scripts/quest-verify <id>`. If it fails, fix and rerun. If it fails
   twice in a row: keep your work uncommitted (the retry continues from it),
   append `провалений кидок` with the failing lines of the verify output,
   commit only `docs/progress.md`, stop. A `leaves=` failure whose names are
   all build inputs or aggregates of what the quest adds or removes is still
   a failure: list the names, the GM widens the line.
7. If the quest's `meta:` line says `boss=yes` and its last entry is not a
   `на суд` with the judge's verdict under it: stage the quest's work, append
   `## <id> - на суд` (one line: `quest-verify` passed, the work is staged,
   plus the `agent:` line), commit only `docs/progress.md` as
   `chore(<id>): на суд`, stop. Never run `scripts/review` yourself: it
   needs the network, which the sandbox denies. `scripts/campaign` runs the
   judge on `git diff --staged` and writes its verdict (concrete defects or
   `no defects`) under the entry, then retries. On that retry fix every
   defect it lists, rerun step 6 and go on to step 8 (one judgement per
   quest).
8. Update `AGENTS.md` if the section's *AGENTS.md* item says so.
9. Commit on branch `redesign` with the Conventional Commits subject from
   *Commit*, listing the changed derivations from the verify output in the
   body, plus a `BREAKING CHANGE:` line if the subject has `!`. Append to
   `docs/progress.md` in the same commit, each entry ending with the
   `agent:` line:
   - `## <id> - хід майстра` + the section's *GM's turn* checklist with exact
     commands, if it has one;
   - otherwise `## <id> - виконано` (max 5 lines).
10. If the quest ends an act (`rest=<tag>` in the meta line): put the
    long-rest steps in the `хід майстра` entry, tag the commit with `<tag>`
    and with the version from `scripts/next-version` (`c1r3`: `v1.0.0`),
    stop. `scripts/campaign` runs the judge on the whole act
    (`<previous rest tag>..<tag>`) and shows its findings with the checklist.

Never print full build logs (tail -n 40 or grep errors). Never push.
Never start subagents (Claude's Agent tool, Codex's spawned agents): each
one rebuilds a whole context and multiplies the cost; read and search
yourself.
Never edit `docs/tasks.md`, except the quest's own `meta:` line when the
GM's decision under the last entry says so. Never edit the files the
section's shared rules list as never touched by agents; if a step needs
one, put the exact change into the `хід майстра` entry instead. Before
committing, check the branch is `redesign`; if not, append
`провалений кидок` and stop.
