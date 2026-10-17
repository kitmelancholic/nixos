# dangoNix

NixOS and Home Manager flake for one machine (a ThinkPad, host `nixos`):
Hyprland with switchable themes. Claude Code reads this file via `CLAUDE.md`.

## Invariants

- Never edit `hosts/nixos/hardware-configuration.nix`.
- A theme never changes the host: themes live in the home configuration only.
- Every theme passes the checks (`scripts/check`).
- Never remove or rebind an existing key binding.

## Loop

`edit → nix fmt → scripts/check --fast → scripts/quest-verify <id>`

- `git add` new files before any check (flakes ignore untracked files);
  stage paths explicitly, never `git commit -a`.
- State-changing tests (switch, lock, rebuild) run in a temporary worktree.
- Never print full build logs (`tail -n 40`); full check via `quest-verify`.
- Unsure of an option or package name: ask the `nixos` MCP server (mcp-nixos,
  26.05 channel). It does not know flake-input options (Noctalia, Caelestia,
  Home Manager): run `scripts/opt [--home [<theme id>]] <option path>`.

## Quests

- `/quest next|<id>|retry <id>` (Claude Code) or `$quest …` (Codex) runs
  `.agents/skills/quest/SKILL.md`; state is only `docs/` and git.
- Models per tier (`meta:` names tier and effort; `scripts/agent` reads it):

  | tier   | claude            | codex          |
  |--------|-------------------|----------------|
  | hero   | claude-sonnet-5-5 | gpt-6.1-sol    |
  | cleric | claude-opus-5-5   | gpt-6.1-sol    |
  | judge  | claude-opus-5-5   | gpt-6.1-sol    |

## Git

- Commit and tag only on branch `redesign`; never push.
- Subjects: Conventional Commits `<type>(<quest id>)[!]: …`; `!` needs a
  `BREAKING CHANGE:` line. SemVer tags `vX.Y.Z` only from `scripts/next-version`.

## Permissions

- Same Bash rules in `.claude/settings.json` and `.codex/rules/dangonix.rules`;
  change both together. Headless runs refuse anything not allowed.
- Both run `git-guard` and the fail-closed `bash-guard` (no hook = no Bash).
- Edit/Write deny rules exist only in Claude Code; Codex has no file-edit
  hook, so its sandbox and the GM's review guard those paths.

## Layout

- `hosts/` NixOS host configuration (one host).
- `home/` Home Manager modules shared by every theme.
- `profiles/` theme registry (default `catppuccin`) and shell themes.
- `themes/` colour variants of the classic desktop.
- `lib/` flake helpers: settings, home builder, repo apps.
- `scripts/` checks, quest tooling, git hooks, `opt`.
- `assets/` wallpapers. `docs/` vision, design, plan, journal.
- `.agents/skills/` shared skills; `.claude/`, `.codex/` per-CLI config.
