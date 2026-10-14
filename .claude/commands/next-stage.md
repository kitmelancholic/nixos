---
description: Execute the next pending stage of docs/redesign-plan.md
---
Execute exactly one stage of docs/redesign-plan.md, then stop.

1. Read CLAUDE.md and docs/progress.md. From the plan read only: §0
   decisions, the rules for every stage, and the first stage not marked
   done in docs/progress.md. Do not read other stages.
2. If the last entry in docs/progress.md is needs-human or blocked,
   print it and stop.
3. Implement the stage. Loop: edit -> nix fmt -> fast check -> fix.
   Run the full check and the oracle once at the end.
4. Stop rules. If the result differs from the stage's expected diff, a
   check fails twice in a row, or the stage needs a decision not in §0:
   discard your uncommitted changes, append a `blocked` entry (max 5
   lines: what, why, what you need from me), stop.
5. If the stage needs switch, sudo, a reboot or a manual check: commit,
   append a `needs-human` entry with the exact commands and a short
   checklist for me, stop.
6. Otherwise commit on branch `redesign` as `stage N: <title>`, listing
   the changed derivations in the body; append a `done` entry (max 5
   lines); stop.
7. If the stage is a checkpoint: run a reviewer subagent on the diff
   since the previous checkpoint tag, add its findings to a
   `needs-human` entry, tag the commit, stop.

Never print full build logs: show the last 40 lines or grep for errors.
Never push. Never edit docs/redesign-plan.md except the stage's status.
Before committing, check that the current branch is `redesign`.
If it is not, append a `blocked` entry and stop.
