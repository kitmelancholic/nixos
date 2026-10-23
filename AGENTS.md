# dangoNix

NixOS and Home Manager flake for one machine (a ThinkPad, host `nixos`):
Hyprland with switchable themes. Claude Code reads this file via `CLAUDE.md`.

## Invariants

- Never edit `hosts/nixos/hardware-configuration.nix`.
- A theme never changes the host: themes live in the home configuration only.
- Every theme passes the checks (`scripts/check`).
- Never remove or rebind an existing key binding.
- Apps take dark/light, palettes and fonts from `dangonix.look` (`home/look.nix`); every theme sets `dangonix.look.appearance`.
- Noctalia's `settings.toml` wins over declarations; enforce runtime keys only through the named list.

## Loop

`edit → nix fmt → dangonix check --fast → dangonix check → scripts/closure-diff`

- `dangonix` is the one CLI (`lib/dangonix/`; `nix run . -- …` before it is
  installed); discover it with `dangonix --dry --json commands`. `--dry`
  plans any command, `scripts/check` is `dangonix check`.
- `git add` new files before any check (flakes ignore untracked files);
  stage paths explicitly, never `git commit -a`.
- State-changing tests run in a worktree under `.campaign/` (tasks.md rules).
- Never print full build logs (`tail -n 40`); full check via `quest-verify`.
- `dangonix check --vm` runs the VM transaction tests (slow; run it when
  transaction code changes).
- `nix build .#greeter-vm` tests the greeter; run it when SDDM, PAM or `thyx` change.
- Unsure of a name: ask the `nixos` MCP server (mcp-nixos, 26.05); options
  of flake inputs (Noctalia, Caelestia, HM): `scripts/opt [--home [<id>]] <path>`.
- Never start subagents. Compaction keeps the quest id, changed files, last `quest-verify`.
- A sandbox error from `nix` itself (`Operation not permitted`, `Permission
  denied` on a repo file) does not go away on retry: after the first one,
  write `провалений кидок` with the error line and `запит: permission`, as
  the quest skill says; never retry or work around it.
- Add to `docs/progress.md` with Edit, never Write.

## Quests

- `/quest next|<id>|retry <id>` (Claude Code) or `$quest …` (Codex) runs
  `.agents/skills/quest/SKILL.md`; state is only `docs/` and git. Model and
  context limits per tier (`meta:` names it): `.agents/models.md`. What an
  attempt did: `scripts/trace .campaign/<id>.<n>.json`.

## Git

- Commit and tag only on branch `redesign`; never push.
- Subjects: Conventional Commits `<type>(<quest id>)[!]: …`; `!` needs a
  `BREAKING CHANGE:` line. SemVer tags `vX.Y.Z` only from `scripts/next-version`.

## Permissions

- Same Bash rules in `.claude/settings.json` and `.codex/rules/dangonix.rules`;
  change both together. Denied: push, `reset --hard`, `clean`, history
  rewrites; ask (refused headless): sudo, rebuilds, real `dangonix` changes.
  A refusal the quest needs lifted is a `запит: permission`.
- Both run `git-guard` and the fail-closed `bash-guard` (no hook = no Bash),
  and `scripts/context-watch`: obey its context warnings.

## Layout

- `hosts/` the one NixOS host; `home/` Home Manager modules for every theme.
- `profiles/` theme registry (default `noctalia`) and shell themes.
- `lib/` flake helpers, `lib/dangonix/` (command table `commands.nix`), checks
  in `lib/checks.nix`; `scripts/` quest tooling, git hooks, `opt`.
- `state.json` holds the GM's choices; change it only when asked. The bind
  fixture `tests/binds/` changes only with a declared behavior change.
- `docs/` vision, design, plan, journal; `.agents/` shared skills and models.
