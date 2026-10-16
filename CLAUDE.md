# dangoNix

## Build output

- Never print full build logs. Pipe them through `tail -n 40`, or grep for
  errors (`grep -iE 'error|failed|warning'`).
- While editing, run only the fast check: `nix flake check --no-build
  --no-write-lock-file` (evaluation only; from quest c1q13, `dangonix check --fast`).
- Run the full check once per quest, at the end: `nix flake check
  --no-write-lock-file` (from quest c1q13, `dangonix check`), then the oracle.

## Git

- Commit and tag only on branch `redesign`; never push.
