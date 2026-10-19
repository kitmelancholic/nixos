# dangoNix

NixOS and Home Manager flake for one machine (a ThinkPad, host `nixos`):
Hyprland with switchable themes. Claude Code reads this file via `CLAUDE.md`.

## Invariants

- Never edit `hosts/nixos/hardware-configuration.nix`.
- A theme never changes the host: themes live in the home configuration only.
- Every theme passes the checks (`scripts/check`).
- Never remove or rebind an existing key binding.

## Loop

`edit → nix fmt → dangonix check --fast → dangonix check → scripts/closure-diff`

- `dangonix` is the one CLI (`lib/dangonix/`; `nix run . -- …` before it is
  installed); discover it with `dangonix --dry --json commands`. `--dry`
  plans any command, `scripts/check` is `dangonix check`.
- `git add` new files before any check (flakes ignore untracked files);
  stage paths explicitly, never `git commit -a`.
- State-changing tests run in a worktree under `.campaign/` (tasks.md rules).
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
  | squire | claude-haiku-5-5  | gpt-5.6-luna   |
  | hero   | claude-sonnet-5-5 | gpt-5.6-terra  |
  | cleric | claude-opus-5-5   | gpt-5.6-sol    |
  | judge  | claude-opus-5-5   | gpt-5.6-sol    |

## Git

- Commit and tag only on branch `redesign`; never push.
- Subjects: Conventional Commits `<type>(<quest id>)[!]: …`; `!` needs a
  `BREAKING CHANGE:` line. SemVer tags `vX.Y.Z` only from `scripts/next-version`.

## Permissions

- Same Bash rules in `.claude/settings.json` and `.codex/rules/dangonix.rules`;
  change both together. Headless runs refuse anything not allowed.
- Agents run `dangonix --dry …` and `dangonix check …`; every real `dangonix`
  change asks.
- Both run `git-guard` and the fail-closed `bash-guard` (no hook = no Bash).
  Claude also runs `scripts/context-watch`: obey its 80k/95k-token warnings.
- Edit/Write deny rules exist only in Claude Code; Codex has no file-edit
  hook, so its sandbox and the GM's review guard those paths.

## Layout

- `hosts/` the one NixOS host; `home/` Home Manager modules for every theme.
- `profiles/` theme registry (default `noctalia`) and shell themes.
- `lib/` flake helpers and `lib/dangonix/` (command table `commands.nix`);
  `scripts/` quest tooling, git hooks, `opt`.
- `state.json` holds the GM's choices; change it only when asked.
- Checks live in `lib/checks.nix`; the bind fixture `tests/binds/` changes
  only with a declared behavior change.
- `docs/` vision, design, plan, journal.
- `.agents/skills/` shared skills; `.claude/`, `.codex/` per-CLI config.
