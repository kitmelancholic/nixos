# Redesign progress

Journal for docs/redesign-plan.md, newest entry last. One entry per stage
run, appended, never edited:

    ## stage N — done|needs-human|blocked|approved
    (at most 5 lines: what happened, and for needs-human/blocked what is
    needed from you)

The agent writes done, needs-human and blocked, and commits every entry
it writes: inside the stage commit, or alone as `journal: stage N blocked`.
After you handle a `needs-human` or `blocked` entry, append
`## stage N — done` yourself and leave it uncommitted; the next run commits
it alone before doing anything else. At a checkpoint, first push
`redesign` from your own terminal and merge its pull request on GitHub with
a merge commit (not squash or rebase), then
`git switch main && git pull --ff-only`. `approved` is yours only: it
releases a stage that waits for your OK before committing (stage 0).

Run stage 0 interactively (`/next-stage`); from then on `scripts/run-stages`
runs stages until one needs you.

