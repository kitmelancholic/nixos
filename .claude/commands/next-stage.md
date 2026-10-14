---
description: Execute the next pending stage of docs/redesign-plan.md
---
Execute exactly one stage of docs/redesign-plan.md, then stop.

1. Read CLAUDE.md and docs/progress.md. From the plan read: §0
   decisions, the rules for every stage, the phase-1 execution table,
   the first stage not marked done in docs/progress.md, and every
   section that stage refers to (for example §2 theme contract, §3
   command surface and transactions, §5 agent docs target). Do not read
   or work on other stages.
2. Journal first. If the only uncommitted change is entries I appended
   to docs/progress.md (`approved`, or `done` after needs-human or
   blocked), commit them alone as `journal: stage N <status>`. Stage 0
   is the exception: its own `needs-human` entry is uncommitted too,
   because stage 0 commits nothing before my OK; the second run commits
   both entries together. Any other
   uncommitted change: append a `blocked` entry, commit it alone, stop.
3. If the last entry is needs-human or blocked, print it and stop. If it
   is `approved` (written only by me), continue that stage from the
   point the plan says follows my OK.
4. Implement the stage. Loop: edit -> nix fmt -> fast check -> fix.
   Run the full check and the oracle once at the end. Destructive tests
   (injected activation failures, recovery) only in the VM test, never
   on this machine.
5. Stop rules. If the result differs from the stage's expected diff, a
   check fails twice in a row, or the stage needs a decision not in §0:
   restore only the paths you changed (`git restore --source=HEAD
   --staged --worktree -- <paths>`, delete files you created; never
   `git clean`, `git reset --hard`, `git checkout .`, and never
   docs/progress.md), append a `blocked` entry (max 5 lines: what, why,
   what you need from me), commit it alone as `journal: stage N
   blocked`, stop.
6. Append the stage's entry to docs/progress.md (max 5 lines):
   - checkpoint: run a reviewer subagent on the diff since the previous
     checkpoint tag; `needs-human` with its findings (I approve by
     merging the `redesign` pull request on GitHub);
   - else, if the stage needs switch, sudo, a reboot or a manual check:
     `needs-human` with the exact commands and a short checklist;
   - otherwise `done`.
7. Commit on branch `redesign` as `stage N: <title>`, listing the
   changed derivations in the body, the journal entry included, without
   waiting for me. Then tag it if it is a checkpoint, and stop.
   Exception: stage 0 commits and tags nothing before an `approved`
   entry; its first run only appends its `needs-human` entry and
   commits nothing.

Never print full build logs: show the last 40 lines or grep for errors.
Never push. Never edit docs/redesign-plan.md except the stage's status.
Before committing, check that the current branch is `redesign`.
If it is not, append a `blocked` entry and stop.
